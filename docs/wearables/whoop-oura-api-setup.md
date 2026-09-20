# Whoop & Oura API integration — setup & status

The generic "Path B" wearable-API layer is **built and compiling**. It pulls HRV + each vendor's
own scores (which Apple Health can't carry) and merges them into the same dashboard. What's left is
**account/credential setup** — steps only you can do — then a server deploy and an end-to-end test.

## Architecture (already implemented)

```
App (iOS)                         Fly server (fatloss-analyzer)            Vendor cloud
─────────                         ─────────────────────────────           ────────────
Profile → "Connect WHOOP"  ──▶  GET /connect/whoop/url  ───────────▶  authorize screen
  ASWebAuthenticationSession  ◀── { authorize URL }                        (user logs in)
        │  user approves ─────────────────────────────────────────────▶  redirect w/ code
        │                        GET /connect/whoop/callback  ◀───────────────┘
        │                          exchange code → tokens (client secret here)
        │                          store at users/{uid}/integrations/whoop (Firestore)
        ◀── fatlosscoach://wearable?ok=1 ──  302 back to app scheme
POST /connect/whoop/sync  ──────▶  refresh token if needed → pull vendor API
  merge into Store        ◀──────  normalised { days, workouts, scores }
```

- **Client secret never ships in the app** — token exchange happens on the Fly server.
- Pulled HRV/RHR/sleep feed our existing `BodyMetrics`, so Recovery/Stress become **full-accuracy**
  (no "· Estimate" tag) with identical UI.
- Code: `server/integrations.js` (vendor configs + OAuth + normalise), `server/server.js`
  (`/connect/*` routes), `FatLossCoach/Core/WearableLink.swift` (app client),
  `Store.applyWearable(...)` (merge), `Features/Profile/WearableConnectCard.swift` (UI).

## What you need to do

### 1. Register a WHOOP developer app
- Go to **developer.whoop.com** → create an app.
- **Redirect URI:** `https://fatloss-analyzer.fly.dev/connect/whoop/callback`
- **Scopes:** `read:recovery read:sleep read:workout read:cycles read:profile offline`
- Copy the **Client ID** and **Client Secret**.

### 2. Register an Oura developer app
- Go to **cloud.ouraring.com/oauth/applications** → create an app.
- **Redirect URI:** `https://fatloss-analyzer.fly.dev/connect/oura/callback`
- **Scopes:** `daily heartrate workout spo2 personal`
- Copy the **Client ID** and **Client Secret**.

### 3. Set the Fly secrets (you run these — Claude is blocked from `flyctl secrets`)
```bash
flyctl -a fatloss-analyzer secrets set \
  WHOOP_CLIENT_ID=xxx  WHOOP_CLIENT_SECRET=xxx \
  OURA_CLIENT_ID=xxx   OURA_CLIENT_SECRET=xxx \
  WEARABLE_STATE_SECRET="$(openssl rand -hex 24)"
```
(`WEARABLE_STATE_SECRET` signs the short-lived OAuth `state`; any long random string works.)
Firestore must also be enabled (it already is if `FIREBASE_SERVICE_ACCOUNT` is set — required so the
server can store per-user tokens).

### 4. Deploy + test
- Deploy: from `server/` → `flyctl deploy --ha=false`.
- `GET /health` should still be OK. Then in the app: Profile → **Connect a wearable** → Connect WHOOP.
- The card shows "Coming soon — server not configured" until the secrets above are set; after that it
  shows a **Connect** button.

## Notes / gotchas
- **HRV units differ:** Whoop & Oura report RMSSD; Apple reports SDNN. Each source's history is
  internally consistent (baseline z-scores), so don't mix a user's Apple HRV and vendor HRV on the
  same axis — the sync overwrites the day's HRV with the vendor value when present.
- **Rate limits:** Oura 5,000 req / 5 min; Whoop is generous. We pull ~30 days on connect + on "Sync
  now". A future improvement is vendor webhooks for auto-refresh instead of manual sync.
- **Firebase Spark limit:** we deliberately host OAuth on Fly (not Cloud Functions), so the free
  Firebase plan is fine.
- Oura temperature is a *deviation*, not absolute °C, so we don't map it (our engine expects °C);
  Recovery still runs from HRV + RHR + sleep + resp + SpO₂.
