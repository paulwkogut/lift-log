# Lift Log

A phone-first workout weight logger. Sign in with email and password; each account keeps its own exercises, sets, and units. The site is static (no build step) and is hosted on GitHub Pages.

## Setup

1. In the Supabase dashboard, open the SQL editor and run [`supabase/schema.sql`](supabase/schema.sql) once. The script is safe to run again.
2. In **Authentication → URL Configuration**:
   - Set **Site URL** to `https://paulwkogut.github.io/lift-log/`
   - Add `https://paulwkogut.github.io/lift-log/` to **Redirect URLs**.

Password reset and email confirmation return to that page. `index.html` loads `@supabase/supabase-js` v2 from a CDN. The project URL and publishable key in the page are public; Row Level Security limits every row to `user_id = auth.uid()`.

If this browser still has a Lift Log from before accounts (`localStorage` key `lift-log-v1`), signing in offers a one-time import into that account.

Push / Pull / Legs templates are included. If you ran `supabase/schema.sql` before that feature, paste [`supabase/templates.sql`](supabase/templates.sql) in the SQL editor. Until that table exists, the app still offers the three built-in workouts and keeps template edits in this browser. Set targets (default 3×10) need [`supabase/sets-tracking.sql`](supabase/sets-tracking.sql) if `templates` already existed; without it, workouts still use 3×10.

## Lock-screen rest alerts

The on-screen rest timer works with nothing else set up. Lock-screen alerts need the steps below. The VAPID private key is not in this repo; it was handed over with the change. If you lose it, generate a new pair, put the new private key in the secret, and replace `VAPID_PUBLIC_KEY` in `index.html`.

1. In the Supabase SQL editor, paste and run [`supabase/push.sql`](supabase/push.sql). It is safe to run again.
2. Open **Edge Functions → Create a new function**. Name it exactly `rest-alert`. Paste the whole file [`supabase/functions/rest-alert/index.ts`](supabase/functions/rest-alert/index.ts) and deploy. You do not need the Supabase CLI.
3. Open **Edge Functions → Secrets** (also under **Project Settings → Edge Functions**) and add:
   - `VAPID_PUBLIC_JWK` = the public JWK JSON (one line):

     `{"key_ops":["verify"],"ext":true,"kty":"EC","x":"jjoFo7nGufvhSNE-2Nd9hl4pwJWFBtDo0rUaBCMB5NU","y":"CQic-WiYvjA-qaEYIz4omQhGZaSsbezuRHH1ETUnKtU","crv":"P-256","alg":"ES256"}`

   - `VAPID_PRIVATE_JWK` = the private JWK JSON from the setup note. Do not paste it into git, the README, or a pull request.
   - `VAPID_SUBJECT` is optional. If you skip it, the function uses `mailto:lift-log@paulwkogut.github.io`.

   CLI equivalent, from a trusted machine, if you would rather not use the dashboard:

   ```
   npx supabase secrets set --project-ref iogspfmaiiurwgjjjteq \
     VAPID_PUBLIC_JWK='{"key_ops":["verify"],"ext":true,"kty":"EC","x":"jjoFo7nGufvhSNE-2Nd9hl4pwJWFBtDo0rUaBCMB5NU","y":"CQic-WiYvjA-qaEYIz4omQhGZaSsbezuRHH1ETUnKtU","crv":"P-256","alg":"ES256"}' \
     VAPID_PRIVATE_JWK='PASTE_PRIVATE_JWK_HERE'
   ```

4. Paste and run [`supabase/delete-account.sql`](supabase/delete-account.sql). That adds **Delete account** in Settings. Until it is run, the button says account deletion isn't set up yet. The script does not use the service role key.

The phone must be added to the Home Screen (iOS 16.4+) before **Lock-screen alerts** can be turned on. The alert is scheduled when a set is logged and cancelled if the timer is skipped, paused, or changed.

Timing: the function waits in the background and, before the platform stops it (150 seconds on the Free plan, 400 seconds on a paid plan), calls itself to keep waiting. A rest of up to 5 minutes still arrives within about a second. The commented `pg_cron` block at the bottom of `supabase/push.sql` is only a backup; a swept alert can be up to 60 seconds late. The screen-awake switch uses the Wake Lock API and does not start audio.
