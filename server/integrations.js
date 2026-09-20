// Wearable cloud-API integrations (Whoop, Oura) — the generic "Path B" layer.
//
// Why this exists: HealthKit can't carry HRV or vendor recovery/strain scores from Whoop/Oura.
// So we OAuth into the vendor cloud, pull the raw signals, and normalise them into the SAME shape
// our app already understands (per-day RecoveryDay-ish rows + workouts). The app then feeds those
// through its own BodyMetrics engine — so a Whoop/Oura user gets a full, non-estimated dashboard
// with the identical UI.
//
// Tokens are stored per user in Firestore at users/{uid}/integrations/{vendor}. The client secret
// lives only here (Fly secrets), never in the app. State is a short-lived signed JWT (uid+vendor).
import { SignJWT, jwtVerify } from "jose";

const PUBLIC_BASE = process.env.PUBLIC_BASE_URL ?? "https://fatloss-analyzer.fly.dev";
const APP_CALLBACK = "fatlosscoach://wearable"; // ASWebAuthenticationSession catches this scheme
const STATE_SECRET = new TextEncoder().encode(
  process.env.WEARABLE_STATE_SECRET ?? process.env.ADMIN_KEY ?? "dev-only-insecure-state-secret");

// ---- vendor catalogue ----------------------------------------------------------------------

/** Each vendor: OAuth endpoints, scopes, and a `pull(accessToken)` that returns normalised data. */
export const VENDORS = {
  whoop: {
    name: "WHOOP",
    authUrl: "https://api.prod.whoop.com/oauth/oauth2/auth",
    tokenUrl: "https://api.prod.whoop.com/oauth/oauth2/token",
    // `offline` is required to receive a refresh token.
    scope: "read:recovery read:sleep read:workout read:cycles read:profile offline",
    clientId: () => process.env.WHOOP_CLIENT_ID,
    clientSecret: () => process.env.WHOOP_CLIENT_SECRET,
    pull: pullWhoop,
  },
  oura: {
    name: "Oura",
    authUrl: "https://cloud.ouraring.com/oauth/authorize",
    tokenUrl: "https://api.ouraring.com/oauth/token",
    scope: "daily heartrate workout spo2 personal",
    clientId: () => process.env.OURA_CLIENT_ID,
    clientSecret: () => process.env.OURA_CLIENT_SECRET,
    pull: pullOura,
  },
};

export function vendorConfigured(vendor) {
  const v = VENDORS[vendor];
  return Boolean(v && v.clientId() && v.clientSecret());
}

export function redirectUri(vendor) {
  return `${PUBLIC_BASE}/connect/${vendor}/callback`;
}

// ---- OAuth ---------------------------------------------------------------------------------

export async function makeState(uid, vendor) {
  return new SignJWT({ uid, vendor })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime("10m")
    .sign(STATE_SECRET);
}

export async function readState(state) {
  const { payload } = await jwtVerify(state, STATE_SECRET);
  return { uid: payload.uid, vendor: payload.vendor };
}

export async function authorizeUrl(vendor, state) {
  const v = VENDORS[vendor];
  const q = new URLSearchParams({
    response_type: "code",
    client_id: v.clientId(),
    redirect_uri: redirectUri(vendor),
    scope: v.scope,
    state,
  });
  return `${v.authUrl}?${q}`;
}

async function tokenRequest(vendor, params) {
  const v = VENDORS[vendor];
  const res = await fetch(v.tokenUrl, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: v.clientId(),
      client_secret: v.clientSecret(),
      ...params,
    }),
  });
  if (!res.ok) throw new Error(`${vendor} token: ${res.status} ${await res.text()}`);
  return res.json();
}

export async function exchangeCode(vendor, code) {
  const t = await tokenRequest(vendor, {
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectUri(vendor),
  });
  return normaliseToken(t);
}

export async function refresh(vendor, refreshToken) {
  const scope = vendor === "whoop" ? "offline" : undefined;
  const t = await tokenRequest(vendor, {
    grant_type: "refresh_token",
    refresh_token: refreshToken,
    ...(scope ? { scope } : {}),
  });
  return normaliseToken(t, refreshToken);
}

function normaliseToken(t, prevRefresh) {
  return {
    accessToken: t.access_token,
    refreshToken: t.refresh_token ?? prevRefresh ?? null,
    expiresAt: Date.now() + (t.expires_in ?? 3600) * 1000,
  };
}

/** The app-scheme deep link we bounce back to after the callback. */
export function appReturn(vendor, ok, error) {
  const q = new URLSearchParams({ vendor, ok: ok ? "1" : "0" });
  if (error) q.set("error", error);
  return `${APP_CALLBACK}?${q}`;
}

// ---- data pull + normalise -----------------------------------------------------------------
//
// Normalised shape the app consumes (all optional per row):
//   { vendor, days: { "YYYY-MM-DD": { hrv, rhr, sleepH, deepH, remH, resp, spo2 } },
//     workouts: [ { date, name, kcal, minutes, avgHR } ],
//     scores:   { "YYYY-MM-DD": { recovery, strain } } }

async function apiGet(url, accessToken) {
  const res = await fetch(url, { headers: { authorization: `Bearer ${accessToken}` } });
  if (!res.ok) throw new Error(`GET ${url}: ${res.status} ${await res.text()}`);
  return res.json();
}

const dayKey = (iso) => (iso ? iso.slice(0, 10) : null);
const hoursFromMs = (ms) => (ms ? +(ms / 3_600_000).toFixed(2) : undefined);
const hoursFromSec = (s) => (s ? +(s / 3600).toFixed(2) : undefined);

async function pullWhoop(accessToken, sinceISO) {
  const base = "https://api.prod.whoop.com/developer";
  const start = `start=${encodeURIComponent(sinceISO)}`;
  const days = {}, scores = {}, workouts = [];
  const row = (k) => (days[k] ??= {});

  // Recovery: HRV (rmssd), resting HR, recovery score. Keyed by cycle → use created day.
  const rec = await apiGet(`${base}/v2/recovery?${start}&limit=25`, accessToken).catch(() => ({ records: [] }));
  for (const r of rec.records ?? []) {
    const k = dayKey(r.created_at ?? r.updated_at);
    if (!k) continue;
    const s = r.score ?? {};
    if (s.hrv_rmssd_milli != null) row(k).hrv = +Number(s.hrv_rmssd_milli).toFixed(1);
    if (s.resting_heart_rate != null) row(k).rhr = s.resting_heart_rate;
    if (s.recovery_score != null) (scores[k] ??= {}).recovery = Math.round(s.recovery_score);
  }
  // Sleep: stages + respiratory rate.
  const sleep = await apiGet(`${base}/v2/activity/sleep?${start}&limit=25`, accessToken).catch(() => ({ records: [] }));
  for (const r of sleep.records ?? []) {
    const k = dayKey(r.end ?? r.created_at);
    if (!k) continue;
    const st = r.score?.stage_summary ?? {};
    const light = st.total_light_sleep_time_milli ?? 0;
    const sws = st.total_slow_wave_sleep_time_milli ?? 0;
    const rem = st.total_rem_sleep_time_milli ?? 0;
    const total = light + sws + rem;
    if (total) row(k).sleepH = hoursFromMs(total);
    if (sws) row(k).deepH = hoursFromMs(sws);
    if (rem) row(k).remH = hoursFromMs(rem);
    if (r.score?.respiratory_rate != null) row(k).resp = +Number(r.score.respiratory_rate).toFixed(1);
  }
  // Cycles: strain.
  const cycles = await apiGet(`${base}/v2/cycle?${start}&limit=25`, accessToken).catch(() => ({ records: [] }));
  for (const r of cycles.records ?? []) {
    const k = dayKey(r.start ?? r.created_at);
    if (k && r.score?.strain != null) (scores[k] ??= {}).strain = +Number(r.score.strain).toFixed(1);
  }
  // Workouts.
  const wk = await apiGet(`${base}/v2/activity/workout?${start}&limit=25`, accessToken).catch(() => ({ records: [] }));
  for (const r of wk.records ?? []) {
    const k = dayKey(r.start);
    if (!k) continue;
    const kj = r.score?.kilojoule;
    workouts.push({
      date: k,
      name: r.sport_name ?? "Workout",
      kcal: kj != null ? Math.round(kj / 4.184) : undefined,
      minutes: r.start && r.end ? Math.round((new Date(r.end) - new Date(r.start)) / 60000) : undefined,
      avgHR: r.score?.average_heart_rate,
    });
  }
  return { vendor: "whoop", days, scores, workouts };
}

async function pullOura(accessToken, sinceISO) {
  const base = "https://api.ouraring.com/v2/usercollection";
  const sd = dayKey(sinceISO);
  const range = `start_date=${sd}`;
  const days = {}, scores = {}, workouts = [];
  const row = (k) => (days[k] ??= {});

  // Detailed sleep: HRV (rmssd), avg HR, breath, stages.
  const sleep = await apiGet(`${base}/sleep?${range}`, accessToken).catch(() => ({ data: [] }));
  for (const r of sleep.data ?? []) {
    const k = r.day;
    if (!k) continue;
    if (r.average_hrv != null) row(k).hrv = +Number(r.average_hrv).toFixed(1);
    if (r.average_heart_rate != null) row(k).rhr = Math.round(r.average_heart_rate);
    if (r.average_breath != null) row(k).resp = +Number(r.average_breath).toFixed(1);
    if (r.total_sleep_duration != null) row(k).sleepH = hoursFromSec(r.total_sleep_duration);
    if (r.deep_sleep_duration != null) row(k).deepH = hoursFromSec(r.deep_sleep_duration);
    if (r.rem_sleep_duration != null) row(k).remH = hoursFromSec(r.rem_sleep_duration);
  }
  // Daily readiness: Oura's own score.
  const ready = await apiGet(`${base}/daily_readiness?${range}`, accessToken).catch(() => ({ data: [] }));
  for (const r of ready.data ?? []) {
    if (r.day && r.score != null) (scores[r.day] ??= {}).recovery = Math.round(r.score);
  }
  // SpO2.
  const spo2 = await apiGet(`${base}/daily_spo2?${range}`, accessToken).catch(() => ({ data: [] }));
  for (const r of spo2.data ?? []) {
    const v = r.spo2_percentage?.average;
    if (r.day && v != null) row(r.day).spo2 = +Number(v).toFixed(1);
  }
  // Workouts.
  const wk = await apiGet(`${base}/workout?${range}`, accessToken).catch(() => ({ data: [] }));
  for (const r of wk.data ?? []) {
    const k = r.day;
    if (!k) continue;
    workouts.push({
      date: k,
      name: r.activity ?? "Workout",
      kcal: r.calories != null ? Math.round(r.calories) : undefined,
      minutes: r.start_datetime && r.end_datetime
        ? Math.round((new Date(r.end_datetime) - new Date(r.start_datetime)) / 60000) : undefined,
    });
  }
  return { vendor: "oura", days, scores, workouts };
}
