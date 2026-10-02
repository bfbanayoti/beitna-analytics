-- Beitna analytics: run once in Supabase → SQL Editor → New query → Run.
-- Records each time Beitna is opened: event, role, approximate city/country, device, time.
-- The visitor's IP address is used only inside log_open() to look up the city and is never stored.

create extension if not exists http with schema extensions;

create table if not exists public.opens (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  event       text not null check (event in ('view','unlock')),   -- view = lock screen shown, unlock = password/Face ID accepted
  role        text check (role in ('admin','guest')),
  method      text check (method in ('password','faceid','remembered')),
  device      text,          -- iPhone, iPad, Android, Mac, Windows, Other
  os          text,          -- e.g. iOS 18.5
  browser     text,          -- Safari, Chrome, Firefox, Edge, Other
  standalone  boolean,       -- opened from the Home Screen icon
  lang        text,
  city        text,
  region      text,
  country     text,
  country_code text,
  lat         numeric(5,1),  -- rounded to ~10 km, enough for a map, not an address
  lon         numeric(5,1)
);
create index if not exists opens_at_idx on public.opens (at desc);

-- Nobody can read or write the table directly. The app can only call log_open();
-- the dashboard can only read, and only when signed in as the owner below.
alter table public.opens enable row level security;
revoke all on public.opens from anon, authenticated;
grant select on public.opens to authenticated;

drop policy if exists "owner reads opens" on public.opens;
create policy "owner reads opens" on public.opens for select to authenticated
  using ((auth.jwt() ->> 'email') = 'bban4170@gmail.com');   -- change if the dashboard login uses another email

create or replace function public.log_open(
  p_event text, p_role text default null, p_method text default null,
  p_device text default null, p_os text default null, p_browser text default null,
  p_standalone boolean default null, p_lang text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  hdr   json := coalesce(nullif(current_setting('request.headers', true), '')::json, '{}'::json);
  ip    text := trim(split_part(coalesce(hdr ->> 'cf-connecting-ip', hdr ->> 'x-real-ip', hdr ->> 'x-forwarded-for', ''), ',', 1));
  geo   jsonb := '{}'::jsonb;
  res   extensions.http_response;
begin
  if p_event not in ('view','unlock') then return; end if;
  -- light abuse guard: at most 120 events a minute overall
  if (select count(*) from public.opens where at > now() - interval '1 minute') > 120 then return; end if;
  if ip <> '' then
    begin
      perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '2500');
      res := extensions.http_get('https://ipwho.is/' || ip || '?fields=success,city,region,country,country_code,latitude,longitude');
      if res.status = 200 then geo := res.content::jsonb; end if;
    exception when others then geo := '{}'::jsonb;   -- lookup failure never blocks logging
    end;
  end if;
  insert into public.opens (event, role, method, device, os, browser, standalone, lang, city, region, country, country_code, lat, lon)
  values (
    p_event,
    case when p_role in ('admin','guest') then p_role end,
    case when p_method in ('password','faceid','remembered') then p_method end,
    left(p_device, 20), left(p_os, 30), left(p_browser, 20), p_standalone, left(p_lang, 5),
    left(geo ->> 'city', 60), left(geo ->> 'region', 60), left(geo ->> 'country', 60), left(geo ->> 'country_code', 2),
    round((geo ->> 'latitude')::numeric, 1), round((geo ->> 'longitude')::numeric, 1)
  );
end $$;

revoke all on function public.log_open from public;
grant execute on function public.log_open to anon, authenticated;
