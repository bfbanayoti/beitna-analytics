# Beitna Analytics

A private dashboard showing who opens [Beitna](https://bfbanayoti.github.io/Beitna/) and from where: Admin or Guest, approximate city and country, device, browser, Home Screen or browser, and how they unlocked (password, Face ID, remembered device).

It is a separate site. The Beitna lock screen sends one event when it is shown (`view`) and one when it is unlocked (`unlock`). Supabase turns the visitor's network address into an approximate city inside `log_open()`; **IP addresses are never stored**, and coordinates are rounded to about 10 km.

## Password

The site itself is encrypted: `index.html` is a lock screen plus the dashboard as AES-256-GCM ciphertext, opened with the site password (kept locally in `.password`, never committed). After that, the dashboard asks once for the owner's Supabase login.

```bash
../Beitna/.venv/bin/python build.py          # dashboard.html -> index.html
../Beitna/.venv/bin/python build.py unpack   # restore dashboard.html with the password
```

## Setup (once)

1. Create a Supabase project (region: Frankfurt, closest to Jordan).
2. **SQL Editor → New query**: paste `supabase/setup.sql` and run it. It creates the `opens` table, the `log_open()` function, and row-level security so only the owner's login can read data.
3. **Authentication → Users → Add user**: create the owner login (the email in `setup.sql`), with a password, and tick *Auto confirm*. Then **Authentication → Sign In / Providers**: turn off *Allow new users to sign up*.
4. **Project Settings → API**: copy the Project URL and the `anon` (publishable) key into `config.js` here and into `analytics.json` in the Beitna repo, then rebuild Beitna.

Both values are public by design: the anon key can only call `log_open()` and cannot read anything.

## Files

| File | Purpose |
|------|---------|
| `index.html` | Built, encrypted page (lock screen + dashboard ciphertext) |
| `dashboard.html` | Dashboard source, local only (owner sign-in, map, opens over time, places, devices, recent opens) |
| `login.html`, `build.py` | Lock screen and the encryption build |
| `config.js` | Supabase project URL + anon key |
| `supabase/setup.sql` | Table, logging function, security policies |
