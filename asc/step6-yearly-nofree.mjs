// Step 6 (2026-10-29): "Yearly" with NO free trial ? the same $29.99/year plan, sold only to people who already had
// their one free week without a card (team invite or a friend's gift). Apple gives its own free trial on the normal
// yearly to anyone it thinks is new, so the app needs a product without one ("maximum 1 free or card 7 day trial").
import fs from 'node:fs'; import crypto from 'node:crypto';
import { api } from './asc.mjs';
const ids = JSON.parse(fs.readFileSync('ids.json'));
const save = () => fs.writeFileSync('ids.json', JSON.stringify(ids, null, 1));
const must = (r, what) => { if (r.status >= 300) { console.error('FAILED', what); process.exit(1) } return r.j };
async function all(path) {
  let out = [], next = path;
  while (next) {
    const r = must(await api('GET', next), next);
    out = out.concat(r.data); next = r.links?.next ? r.links.next.replace('https://api.appstoreconnect.apple.com', '') : null;
  }
  return out;
}

if (!ids.yearlyNoFree) {
  let r = await api('POST', '/v1/subscriptions', { data: { type: 'subscriptions',
    attributes: { name: 'SOCCER MAX Yearly (no trial)', productId: 'com.jacksteiner.soccermax.yearly.notrial',
      subscriptionPeriod: 'ONE_YEAR', groupLevel: 1, familySharable: false },
    relationships: { group: { data: { type: 'subscriptionGroups', id: ids.group } } } } });
  ids.yearlyNoFree = must(r, 'sub').data.id; save();
  must(await api('POST', '/v1/subscriptionLocalizations', { data: { type: 'subscriptionLocalizations',
    attributes: { name: 'Soccer Max Yearly', description: 'Every drill, session and film.', locale: 'en-US' },
    relationships: { subscription: { data: { type: 'subscriptions', id: ids.yearlyNoFree } } } } }), 'loc');
}
const territories = (await all('/v1/territories?limit=200')).map(t => t.id);
if (!ids.yearlyNoFreeAvail) {
  const r = must(await api('POST', '/v1/subscriptionAvailabilities', { data: { type: 'subscriptionAvailabilities',
    attributes: { availableInNewTerritories: true },
    relationships: { subscription: { data: { type: 'subscriptions', id: ids.yearlyNoFree } },
      availableTerritories: { data: territories.map(id => ({ type: 'territories', id })) } } } }), 'availability');
  ids.yearlyNoFreeAvail = r.data.id; save();
}
if (!ids.yearlyNoFreePriced) {
  const us = (await all(`/v1/subscriptions/${ids.yearlyNoFree}/pricePoints?filter%5Bterritory%5D=USA&limit=200`))
    .find(p => p.attributes.customerPrice === '29.99');
  const eq = await all(`/v1/subscriptionPricePoints/${us.id}/equalizations?limit=200&include=territory`);
  let ok = 0;
  for (const p of [us, ...eq]) {
    const r = await api('POST', '/v1/subscriptionPrices', { data: { type: 'subscriptionPrices', attributes: { preserveCurrentPrice: false },
      relationships: { subscription: { data: { type: 'subscriptions', id: ids.yearlyNoFree } },
        subscriptionPricePoint: { data: { type: 'subscriptionPricePoints', id: p.id } } } } });
    if (r.status < 300) ok++;
  }
  console.log(`prices ${ok}/${eq.length + 1}`);
  ids.yearlyNoFreePriced = true; save();
}
if (!ids.yearlyNoFreeShot) {
  const file = 'paywall-review.png', bytes = fs.readFileSync(file);
  const r = must(await api('POST', '/v1/subscriptionAppStoreReviewScreenshots', { data: { type: 'subscriptionAppStoreReviewScreenshots',
    attributes: { fileName: file, fileSize: bytes.length },
    relationships: { subscription: { data: { type: 'subscriptions', id: ids.yearlyNoFree } } } } }), 'shot');
  const shot = r.data;
  for (const op of shot.attributes.uploadOperations) {
    const headers = Object.fromEntries((op.requestHeaders || []).map(h => [h.name, h.value]));
    await fetch(op.url, { method: op.method, headers, body: bytes.subarray(op.offset, op.offset + op.length) });
  }
  must(await api('PATCH', `/v1/subscriptionAppStoreReviewScreenshots/${shot.id}`, { data: { type: 'subscriptionAppStoreReviewScreenshots',
    id: shot.id, attributes: { uploaded: true, sourceFileChecksum: crypto.createHash('md5').update(bytes).digest('hex') } } }), 'commit');
  ids.yearlyNoFreeShot = shot.id; save();
}
console.log(ids);
const s = await api('GET', `/v1/subscriptions/${ids.yearlyNoFree}`);
console.log('state', s.j.data?.attributes?.state);
