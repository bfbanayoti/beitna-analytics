// Supabase project for Beitna analytics. Both values are public by design: the anon key can only call
// log_open() and read nothing; the data is readable only after signing in as the owner (row-level security).
window.BEITNA_ANALYTICS = {
  url: '',   // e.g. https://abcdefghijklmnop.supabase.co
  key: ''    // Project Settings → API → anon / publishable key
};
