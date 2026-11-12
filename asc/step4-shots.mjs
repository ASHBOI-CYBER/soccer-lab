// Step 4: App Review screenshot (the paywall) on monthly, yearly and lifetime.
import fs from 'node:fs'; import crypto from 'node:crypto';
import { api } from './asc.mjs';
const ids = JSON.parse(fs.readFileSync('ids.json')), life = JSON.parse(fs.readFileSync('life.json'));
const file = 'paywall-review.png';
const bytes = fs.readFileSync(file);
const md5 = crypto.createHash('md5').update(bytes).digest('hex');

async function upload(type, rel, relType, id) {
  const r = await api('POST', `/v1/${type}`, { data: { type, attributes: { fileName: file, fileSize: bytes.length },
    relationships: { [rel]: { data: { type: relType, id } } } } });
  if (r.status >= 300) return 'reserve failed';
  const shot = r.j.data;
  for (const op of shot.attributes.uploadOperations) {
    const headers = Object.fromEntries((op.requestHeaders || []).map(h => [h.name, h.value]));
    const put = await fetch(op.url, { method: op.method, headers, body: bytes.subarray(op.offset, op.offset + op.length) });
    if (!put.ok) return 'upload failed ' + put.status;
  }
  const c = await api('PATCH', `/v1/${type}/${shot.id}`, { data: { type, id: shot.id, attributes: { uploaded: true, sourceFileChecksum: md5 } } });
  return c.status < 300 ? 'ok' : 'commit failed';
}
console.log('monthly', await upload('subscriptionAppStoreReviewScreenshots', 'subscription', 'subscriptions', ids.monthly));
console.log('yearly', await upload('subscriptionAppStoreReviewScreenshots', 'subscription', 'subscriptions', ids.yearly));
console.log('lifetime', await upload('inAppPurchaseAppStoreReviewScreenshots', 'inAppPurchaseV2', 'inAppPurchases', life.id));
