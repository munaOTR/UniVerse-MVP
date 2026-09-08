# UniVerse ICOS — Device Notifications

## What is included
- `dashboard.html`: keeps the existing app intact and adds device-notification permission, push subscription registration, foreground realtime popups, and notification settings.
- `notifications-sw.js`: browser service worker for background Web Push.
- `push_notifications.sql`: push subscription table + RLS + notification triggers for direct messages and message requests, while preserving the existing Orbit notification triggers.
- `send-push.ts`: Supabase Edge Function that sends Web Push to every active device subscription for a notification.

## Current deployment state
- The notification database migration has been applied to the UniVerse ICOS Supabase project.
- The `send-push` Edge Function has been deployed with JWT verification enabled.
- The Vercel production app serves `dashboard.html` and `notifications-sw.js` over HTTPS.
- Foreground device notifications can operate after browser permission is granted even before the VAPID background-push credentials are configured.

## Required for background notifications when the app is closed
1. Generate a fresh VAPID key pair with `npx web-push generate-vapid-keys` if the project does not already have one.
2. Put the public key into `UNIVERSEICOS_PUSH_VAPID_PUBLIC_KEY` in `dashboard.html`.
3. Store the public/private VAPID keys as Edge Function secrets `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY`.
4. Set `VAPID_SUBJECT=mailto:notifications@universeicos.app`.
5. Ensure `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are available to the Edge Function.
6. Create a Supabase Database Webhook for `public.notifications` → `INSERT` and point it at the deployed `send-push` function. The webhook must authenticate to the JWT-protected function.
7. Keep `notifications-sw.js` at the site root so it is reachable at `/notifications-sw.js`.
8. Each user must tap **Enable notifications** once on each browser/device.

## Important
Never commit VAPID private keys or the Supabase service-role key. The frontend must only contain the VAPID public key. Background Web Push is subject to browser/OS notification support and permissions.

The frontend displays notifications that exist in `public.notifications`. The database notification pipeline targets user-relevant MVP activity instead of broadcasting every campus event to every student.
