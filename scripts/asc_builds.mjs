// List TestFlight builds for the app with their processing state.
// Usage: node scripts/asc_builds.mjs
import crypto from 'node:crypto';
import fs from 'node:fs';

const kid = 'F32V65ACX6';
const iss = '60384b84-0407-4489-bb63-c2c1b708e376';
const appId = '6809046427';
const key = fs.readFileSync(`${process.env.HOME}/.appstoreconnect/private_keys/AuthKey_${kid}.p8`);

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const header = b64({ alg: 'ES256', kid, typ: 'JWT' });
const payload = b64({ iss, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' });
const sig = crypto.sign('sha256', Buffer.from(`${header}.${payload}`), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
const jwt = `${header}.${payload}.${sig}`;

const url = `https://api.appstoreconnect.apple.com/v1/builds?filter[app]=${appId}&sort=-uploadedDate&limit=10&fields[builds]=version,uploadedDate,processingState,expired`;
const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` } });
const json = await res.json();
if (!json.data) { console.error(JSON.stringify(json, null, 2)); process.exit(1); }
for (const b of json.data) {
  const a = b.attributes;
  console.log(`build ${a.version}\t${a.processingState}\t${a.uploadedDate}${a.expired ? '\texpired' : ''}`);
}
