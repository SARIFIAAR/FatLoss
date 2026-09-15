// Push App Store title (name), subtitle and keywords to the editable version.
// Usage: node scripts/asc_metadata.mjs [--apply]   (omit --apply for a dry run)
import crypto from 'node:crypto';
import fs from 'node:fs';

const kid = 'F32V65ACX6';
const iss = '60384b84-0407-4489-bb63-c2c1b708e376';
const appId = '6809046427';
const key = fs.readFileSync(`${process.env.HOME}/.appstoreconnect/private_keys/AuthKey_${kid}.p8`);
const APPLY = process.argv.includes('--apply');

const NAME = 'HUMANS®: Health Performance';
const SUBTITLE = 'Recovery, Strain, Sleep & HRV';
const KEYWORDS = 'apple,watch,body,fat,loss,weight,heart,rate,calories,macros,steps,stress,workout,tracker,coach,diet';

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
function token() {
  const now = Math.floor(Date.now() / 1000);
  const header = b64({ alg: 'ES256', kid, typ: 'JWT' });
  const payload = b64({ iss, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' });
  const sig = crypto.sign('sha256', Buffer.from(`${header}.${payload}`), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  return `${header}.${payload}.${sig}`;
}
const jwt = token();
const api = async (path, opts = {}) => {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    ...opts,
    headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json', ...(opts.headers || {}) },
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : {};
  if (!res.ok) { console.error(`HTTP ${res.status} ${path}\n`, JSON.stringify(json, null, 2)); process.exit(1); }
  return json;
};

console.log(`Mode: ${APPLY ? 'APPLY (writing)' : 'DRY RUN (read only)'}\n`);

// ---- 1. Name + subtitle live on the EDITABLE appInfo's localization (en-US) ----
const infos = await api(`/v1/apps/${appId}/appInfos`);
const editableInfo = infos.data.find(i =>
  ['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED', 'WAITING_FOR_REVIEW', 'READY_FOR_DISTRIBUTION'].includes(i.attributes.appStoreState)
) || infos.data[0];
const locs = await api(`/v1/appInfos/${editableInfo.id}/appInfoLocalizations`);
const enInfo = locs.data.find(l => l.attributes.locale === 'en-US') || locs.data[0];
console.log('appInfo state:', editableInfo.attributes.appStoreState, '| locale:', enInfo.attributes.locale);
console.log('  name:     ', JSON.stringify(enInfo.attributes.name), '->', JSON.stringify(NAME));
console.log('  subtitle: ', JSON.stringify(enInfo.attributes.subtitle), '->', JSON.stringify(SUBTITLE));

// ---- 2. Keywords live on the EDITABLE appStoreVersion's localization ----
const versions = await api(`/v1/apps/${appId}/appStoreVersions?limit=5`);
const editableVer = versions.data.find(v =>
  ['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'].includes(v.attributes.appStoreState)
) || versions.data[0];
const verLocs = await api(`/v1/appStoreVersions/${editableVer.id}/appStoreVersionLocalizations`);
const enVer = verLocs.data.find(l => l.attributes.locale === 'en-US') || verLocs.data[0];
console.log('\nversion:', editableVer.attributes.versionString, '| state:', editableVer.attributes.appStoreState, '| locale:', enVer.attributes.locale);
console.log('  keywords: ', JSON.stringify(enVer.attributes.keywords), '->', JSON.stringify(KEYWORDS), `(${KEYWORDS.length} chars)`);

if (!APPLY) { console.log('\nDry run complete. Re-run with --apply to write.'); process.exit(0); }

// ---- Apply ----
await api(`/v1/appInfoLocalizations/${enInfo.id}`, {
  method: 'PATCH',
  body: JSON.stringify({ data: { type: 'appInfoLocalizations', id: enInfo.id, attributes: { name: NAME, subtitle: SUBTITLE } } }),
});
console.log('\n✓ name + subtitle updated');
await api(`/v1/appStoreVersionLocalizations/${enVer.id}`, {
  method: 'PATCH',
  body: JSON.stringify({ data: { type: 'appStoreVersionLocalizations', id: enVer.id, attributes: { keywords: KEYWORDS } } }),
});
console.log('✓ keywords updated');
console.log('\nDone. Review in App Store Connect before submitting.');
