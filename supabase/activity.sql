-- Beitna analytics, part 2: sessions + in-app activity (screens, sheets, actions). Run once in SQL Editor after setup.sql.
-- Records which screens and buttons are used, never amounts or anything typed.
-- Also removes the setup test rows (US) that were sent while connecting the project.

-- shared city lookup: the IP is used here and never stored
create or replace function public._geo() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  hdr json := coalesce(nullif(current_setting('request.headers', true), '')::json, '{}'::json);
  ip  text := trim(split_part(coalesce(hdr ->> 'cf-connecting-ip', hdr ->> 'x-real-ip', hdr ->> 'x-forwarded-for', ''), ',', 1));
  res extensions.http_response;
begin
  if ip = '' then return '{}'::jsonb; end if;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '2500');
  res := extensions.http_get('https://ipwho.is/' || ip || '?fields=success,city,region,country,country_code,latitude,longitude');
  return case when res.status = 200 then res.content::jsonb else '{}'::jsonb end;
exception when others then return '{}'::jsonb;
end $$;
revoke all on function public._geo from public, anon, authenticated;

create table if not exists public.sessions (
  id          uuid primary key,
  started_at  timestamptz not null default now(),
  last_at     timestamptz not null default now(),
  role        text check (role in ('admin','guest')),
  method      text check (method in ('password','faceid','remembered')),
  device text, os text, browser text, standalone boolean, lang text,
  device_id text,        -- random id kept on the device (no personal data), for the Saved devices list
  remembered boolean,    -- the device stays signed in
  faceid boolean,        -- Face ID is set up on the device
  city text, region text, country text, country_code text, lat numeric(5,1), lon numeric(5,1),
  events      int not null default 0
);
create table if not exists public.events (
  id         bigint generated always as identity primary key,
  session_id uuid not null references public.sessions(id) on delete cascade,
  at         timestamptz not null default now(),
  kind       text not null check (kind in ('page','sheet','action','error')),
  name       text not null,
  detail     text
);
alter table public.sessions add column if not exists device_id text, add column if not exists remembered boolean, add column if not exists faceid boolean;
create index if not exists sessions_started_idx on public.sessions (started_at desc);
create index if not exists events_session_idx on public.events (session_id, at);
create index if not exists events_at_idx on public.events (at desc);
create index if not exists sessions_device_idx on public.sessions (device_id, started_at desc);

alter table public.sessions enable row level security;
alter table public.events enable row level security;
revoke all on public.sessions, public.events from anon, authenticated;
grant select on public.sessions, public.events to authenticated;
drop policy if exists "owner reads sessions" on public.sessions;
create policy "owner reads sessions" on public.sessions for select to authenticated using ((auth.jwt() ->> 'email') = 'bban4170@gmail.com');
drop policy if exists "owner reads events" on public.events;
create policy "owner reads events" on public.events for select to authenticated using ((auth.jwt() ->> 'email') = 'bban4170@gmail.com');

-- called by the lock screen when the app opens (creates the session with its city)
create or replace function public.start_session(
  p_id uuid, p_role text default null, p_method text default null, p_device text default null, p_os text default null,
  p_browser text default null, p_standalone boolean default null, p_lang text default null,
  p_device_id text default null, p_remembered boolean default null, p_faceid boolean default null
) returns void language plpgsql security definer set search_path = public, extensions as $$
declare g jsonb := public._geo();
begin
  if (select count(*) from public.sessions where started_at > now() - interval '1 minute') > 60 then return; end if;
  insert into public.sessions (id, role, method, device, os, browser, standalone, lang, device_id, remembered, faceid, city, region, country, country_code, lat, lon)
  values (p_id,
    case when p_role in ('admin','guest') then p_role end, case when p_method in ('password','faceid','remembered') then p_method end,
    left(p_device,20), left(p_os,30), left(p_browser,20), p_standalone, left(p_lang,5), left(p_device_id,40), p_remembered, p_faceid,
    left(g->>'city',60), left(g->>'region',60), left(g->>'country',60), left(g->>'country_code',2),
    round((g->>'latitude')::numeric,1), round((g->>'longitude')::numeric,1))
  on conflict (id) do update set role = excluded.role, method = excluded.method, device = excluded.device, os = excluded.os,
    browser = excluded.browser, standalone = excluded.standalone, lang = excluded.lang, device_id = excluded.device_id,
    remembered = excluded.remembered, faceid = excluded.faceid, city = excluded.city, region = excluded.region,
    country = excluded.country, country_code = excluded.country_code, lat = excluded.lat, lon = excluded.lon;
end $$;

-- called by the app in small batches: [{at, kind, name, detail}, ...]
create or replace function public.log_events(p_session uuid, p_events jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_session is null or jsonb_typeof(p_events) <> 'array' then return; end if;
  insert into public.sessions (id) values (p_session) on conflict (id) do nothing;   -- if events arrive before start_session
  if (select started_at from public.sessions where id = p_session) < now() - interval '24 hours' then return; end if;
  insert into public.events (session_id, at, kind, name, detail)
  select p_session, least(coalesce((e->>'at')::timestamptz, now()), now()), e->>'kind', left(e->>'name',40), left(e->>'detail',60)
  from jsonb_array_elements(p_events) with ordinality as x(e, i)
  where i <= 50 and e->>'kind' in ('page','sheet','action','error') and coalesce(e->>'name','') <> '';
  get diagnostics n = row_count;
  update public.sessions set last_at = now(), events = events + n where id = p_session;
end $$;

revoke all on function public.start_session, public.log_events from public;
grant execute on function public.start_session, public.log_events to anon, authenticated;

do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='sessions') then alter publication supabase_realtime add table public.sessions; end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='events') then alter publication supabase_realtime add table public.events; end if;
end $$;

-- names for saved devices (e.g. "BB iPhone"), set by the owner from the dashboard
create table if not exists public.device_names (
  device_id  text primary key,
  name       text not null check (char_length(name) between 1 and 40),
  updated_at timestamptz not null default now()
);
alter table public.device_names enable row level security;
revoke all on public.device_names from anon, authenticated;
grant select, insert, update, delete on public.device_names to authenticated;
drop policy if exists "owner manages device names" on public.device_names;
create policy "owner manages device names" on public.device_names for all to authenticated
  using ((auth.jwt() ->> 'email') = 'bban4170@gmail.com') with check ((auth.jwt() ->> 'email') = 'bban4170@gmail.com');

-- remove the setup test rows sent while connecting the project (they came from a US network)
delete from public.opens where country_code = 'US' or browser = 'Setup check';
