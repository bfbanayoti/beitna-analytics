-- Beitna analytics, part 3: wrong-password attempts + a device id on every open (to count people, not just tries).
-- Run once in SQL Editor after setup.sql and activity.sql.

alter table public.opens add column if not exists device_id text;
alter table public.opens drop constraint if exists opens_event_check;
alter table public.opens add constraint opens_event_check check (event in ('view','unlock','fail'));   -- fail = wrong password
create index if not exists opens_device_idx on public.opens (device_id, at desc);

drop function if exists public.log_open(text, text, text, text, text, text, boolean, text);
create or replace function public.log_open(
  p_event text, p_role text default null, p_method text default null,
  p_device text default null, p_os text default null, p_browser text default null,
  p_standalone boolean default null, p_lang text default null, p_device_id text default null
) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare g jsonb;
begin
  if p_event not in ('view','unlock','fail') then return; end if;
  if (select count(*) from public.opens where at > now() - interval '1 minute') > 120 then return; end if;
  g := public._geo();
  insert into public.opens (event, role, method, device, os, browser, standalone, lang, device_id, city, region, country, country_code, lat, lon)
  values (p_event,
    case when p_event = 'unlock' and p_role in ('admin','guest') then p_role end,
    case when p_method in ('password','faceid','remembered') then p_method end,
    left(p_device,20), left(p_os,30), left(p_browser,20), p_standalone, left(p_lang,5), left(p_device_id,40),
    left(g->>'city',60), left(g->>'region',60), left(g->>'country',60), left(g->>'country_code',2),
    round((g->>'latitude')::numeric,1), round((g->>'longitude')::numeric,1));
end $$;
revoke all on function public.log_open from public;
grant execute on function public.log_open to anon, authenticated;
