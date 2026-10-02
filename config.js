// Supabase project for Beitna analytics. Both values are public by design: the anon key can only call
// log_open() and read nothing; the data is readable only after signing in as the owner (row-level security).
window.BEITNA_ANALYTICS = {
  url: 'https://ojxaxcxdamhqeggfgmkr.supabase.co',
  key: 'sb_publishable_PNyENTYDhNLAb-PYtAJl2Q_hHUE9Gop'   // publishable key: can only call log_open(), reads nothing
};
