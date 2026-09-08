# UniVerse ICOS — Device Notifications

## What is included
- `index.html`: keeps the existing app intact and adds device-notification permission, push subscription registration, foreground realtime popups, and notification settings.
- `notifications-sw.js`: browser service worker for background Web Push.
- `push_notifications.sql`: push subscription table + RLS + notification triggers for direct messages, message requests, Orbit likes/comments/mentions.
- `send-push.ts`: Supabase Edge Function that sends Web Push to every active device subscription for a notification.

## Required Supabase setup
1. Run `push_notifications.sql` in Supabase SQL Editor.
2. Deploy `send-push.ts` as an Edge Function named `send-push`.
3. Set Edge Function secrets:
   - Generate a VAPID key pair once with `npx web-push generate-vapid-keys`.
   - Put the generated public key into `UNIVERSEICOS_PUSH_VAPID_PUBLIC_KEY` in `index.html`.
   - Store the generated private key only as the Edge Function secret `VAPID_PRIVATE_KEY`.
   - Store the generated public key as the Edge Function secret `VAPID_PUBLIC_KEY` too.
   - `VAPID_SUBJECT=mailto:notifications@universeicos.app`
   - `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` (Supabase normally supplies these to Edge Functions; never put the service-role key in `index.html`).
4. In Supabase Dashboard → Database → Webhooks, create a webhook for:
   - Table: `public.notifications`
   - Event: `INSERT`
   - URL: the deployed `send-push` Edge Function URL
   - Send the database webhook payload to the function.
5. Serve `index.html` and `notifications-sw.js` from the same HTTPS origin. The service worker must be reachable at `/notifications-sw.js`.
6. Users must tap **Enable notifications** once per browser/device. After that, the browser can display notifications even when UniVerse ICOS is not the active tab, subject to OS/browser notification permissions.

## Important
Do not commit VAPID private keys. If the project already has a VAPID key pair, reuse it. Otherwise generate a fresh pair with `npx web-push generate-vapid-keys`. Never expose the private key in client-side code or Git.

The frontend only displays notifications that exist in `public.notifications`. The included SQL makes the core targeted MVP activities create those notification rows. Generic campus posts are intentionally not broadcast to every student because that would create notification spam.
