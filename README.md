# Lift Log

A phone-first workout weight logger. Sign in with email and password; each account keeps its own exercises, sets, and units. The site is static (no build step) and is hosted on GitHub Pages.

## Setup

1. In the Supabase dashboard, open the SQL editor and run [`supabase/schema.sql`](supabase/schema.sql) once. The script is safe to run again.
2. In **Authentication → URL Configuration**:
   - Set **Site URL** to `https://paulwkogut.github.io/lift-log/`
   - Add `https://paulwkogut.github.io/lift-log/` to **Redirect URLs**.

Password reset and email confirmation return to that page. `index.html` loads `@supabase/supabase-js` v2 from a CDN. The project URL and publishable key in the page are public; Row Level Security limits every row to `user_id = auth.uid()`.

If this browser still has a Lift Log from before accounts (`localStorage` key `lift-log-v1`), signing in offers a one-time import into that account.
