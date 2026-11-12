// App Store Connect API helper for Soccer Max (key chosen by the user: 2J4BPNT7DQ).
import crypto from 'node:crypto'; import fs from 'node:fs'; import os from 'node:os';
const ISS = '201c6926-4131-4e62-9e7c-d66e71f09b3d';
const KID = 'B8B72B9R2P'; // user's choice 2026-10-28 (2J4BPNT7DQ was rejected)
const KEY = fs.readFileSync(`${os.homedir()}/.appstoreconnect/private_keys/AuthKey_${KID}.p8`);
function jwt() {
  const b = o => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const h = b({ alg: 'ES256', kid: KID, typ: 'JWT' }), p = b(process.env.INDIV ? { sub: 'user', iat: now, exp: now + 1100, aud: 'appstoreconnect-v1' } : { iss: ISS, iat: now, exp: now + 1100, aud: 'appstoreconnect-v1' });
  const s = crypto.sign('sha256', Buffer.from(h + '.' + p), { key: KEY, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  return `${h}.${p}.${s}`;
}
export async function api(method, path, body) {
  const r = await fetch('https://api.appstoreconnect.apple.com' + path, { method, headers: { Authorization: 'Bearer ' + jwt(), 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const t = await r.text(); let j; try { j = JSON.parse(t) } catch { j = t }
  if (!r.ok) console.error(method, path, r.status, JSON.stringify(j).slice(0, 800));
  return { status: r.status, j };
}
if (process.argv[2] && import.meta.url === `file://${process.argv[1]}`) {
  const [m, p, b] = process.argv.slice(2);
  const r = await api(m, p, b ? JSON.parse(b) : undefined);
  console.log(r.status, JSON.stringify(r.j, null, 1).slice(0, +(process.env.MAX || 4000)));
}
