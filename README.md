# Beitna Analytics

A private dashboard showing who opens [Beitna](https://bfbanayoti.github.io/Beitna/) and from where: Admin or Guest, approximate city and country, device, browser, Home Screen or browser, and how they unlocked (password, Face ID, remembered device).

It is a separate site. The Beitna lock screen sends one event when it is shown (`view`) and one when it is unlocked (`unlock`). Supabase turns the visitor's network address into an approximate city inside `log_open()`; **IP addresses are never stored**, and coordinates are rounded to about 10 km.

## Setup (once)

1. Create a Supabase project (region: Frankfurt, closest to Jordan).
2. **SQL Editor → New query**: paste `supabase/setup.sql` and run it. It creates the `opens` table, the `log_open()` function, and row-level security so only the owner's login can read data.
3. **Authentication → Users → Add user**: create the owner login (the email in `setup.sql`), with a password, and tick *Auto confirm*. Then **Authentication → Sign In / Providers**: turn off *Allow new users to sign up*.
4. **Project Settings → API**: copy the Project URL and the `anon` (publishable) key into `config.js` here and into `analytics.json` in the Beitna repo, then rebuild Beitna.

Both values are public by design: the anon key can only call `log_open()` and cannot read anything.

## Files

| File | Purpose |
|------|---------|
| `index.html` | The dashboard (owner sign-in, live map, opens over time, places, devices, recent opens) |
| `config.js` | Supabase project URL + anon key |
| `supabase/setup.sql` | Table, logging function, security policies |
