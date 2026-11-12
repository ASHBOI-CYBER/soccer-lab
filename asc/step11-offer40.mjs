// Step 11 (2026-10-30): the 40% OFF offer paywall (app/native/SoccerMax/Screens/StayOffer.swift) ? all three plans 40% off:
//   com.jacksteiner.soccermax.monthly.off40   $5.99 / month   (same group, no trial)
//   com.jacksteiner.soccermax.yearly.off40    $17.99 / year   (same group, no trial)
//   com.jacksteiner.soccermax.lifetime.off40  $23.99 once     (non-consumable)
// Only sold from the long-press "WAIT, DON'T DELETE ME!" page to people who reached the paywall and didn't pay.
// Re-runs skip what's done (keys in off40.json). Review screenshot = SHOT env (default offer-review.png).
import fs from 'node:fs'; import crypto from 'node:crypto';
import { api } from './asc.mjs';
const APP = '6828180179';
const ids = JSON.parse(fs.readFileSync('ids.json'));
const o = fs.existsSync('off40.json') ? JSON.parse(fs.readFileSync('off40.json')) : {};
const save = () => fs.writeFileSync('off40.json', JSON.stringify(o, null, 1));
const must = (r, what) => { if (r.status >= 300) { console.error('FAILED', what, JSON.stringify(r.j).slice(0, 600)); process.exit(1) } return r.j };
async function all(path) {
  let out = [], next = path;
  while (next) {
    const r = must(await api('GET', next), next);
    out = out.concat(r.data); next = r.links?.next ? r.links.next.replace('https://api.appstoreconnect.apple.com', '') : null;
  }
  return out;
}
const territories = (await all('/v1/territories?limit=200')).map(t => t.id);

// --- the two subscriptions
const subs = [
  { key: 'yearly', name: 'SOCCER MAX Yearly (40% off)', productId: 'com.jacksteiner.soccermax.yearly.off40', period: 'ONE_YEAR', level: 1, price: '17.99' },
  { key: 'monthly', name: 'SOCCER MAX Monthly (40% off)', productId: 'com.jacksteiner.soccermax.monthly.off40', period: 'ONE_MONTH', level: 2, price: '5.99' },
];
for (const s of subs) {
  const k = s.key;
  if (!o[k]) {
    o[k] = must(await api('POST', '/v1/subscriptions', { data: { type: 'subscriptions',
      attributes: { name: s.name, productId: s.productId, subscriptionPeriod: s.period, groupLevel: s.level, familySharable: false },
      relationships: { group: { data: { type: 'subscriptionGroups', id: ids.group } } } } }), k).data.id; save();
    must(await api('POST', '/v1/subscriptionLocalizations', { data: { type: 'subscriptionLocalizations',
      attributes: { name: k === 'yearly' ? 'Soccer Max Yearly' : 'Soccer Max Monthly', description: 'Every drill, session and film. 40% off.', locale: 'en-US' },
      relationships: { subscription: { data: { type: 'subscriptions', id: o[k] } } } } }), k + ' loc');
  }
  if (!o[k + 'Avail']) {
    o[k + 'Avail'] = must(await api('POST', '/v1/subscriptionAvailabilities', { data: { type: 'subscriptionAvailabilities',
      attributes: { availableInNewTerritories: true },
      relationships: { subscription: { data: { type: 'subscriptions', id: o[k] } },
        availableTerritories: { data: territories.map(id => ({ type: 'territories', id })) } } } }), k + ' availability').data.id; save();
  }
  if (!o[k + 'Priced']) {
    const us = (await all(`/v1/subscriptions/${o[k]}/pricePoints?filter%5Bterritory%5D=USA&limit=200`))
      .find(p => p.attributes.customerPrice === s.price);
    if (!us) { console.error('no price point', s.price); process.exit(1) }
    const eq = await all(`/v1/subscriptionPricePoints/${us.id}/equalizations?limit=200&include=territory`);
    let ok = 0;
    for (const p of [us, ...eq]) {
      const r = await api('POST', '/v1/subscriptionPrices', { data: { type: 'subscriptionPrices', attributes: { preserveCurrentPrice: false },
        relationships: { subscription: { data: { type: 'subscriptions', id: o[k] } },
          subscriptionPricePoint: { data: { type: 'subscriptionPricePoints', id: p.id } } } } });
      if (r.status < 300) ok++;
    }
    console.log(k, `prices ${ok}/${eq.length + 1}`);
    o[k + 'Priced'] = true; save();
  }
}

// --- lifetime
if (!o.lifetime) {
  o.lifetime = must(await api('POST', '/v2/inAppPurchases', { data: { type: 'inAppPurchases',
    attributes: { name: 'SOCCER MAX Lifetime (40% off)', productId: 'com.jacksteiner.soccermax.lifetime.off40', inAppPurchaseType: 'NON_CONSUMABLE', familySharable: false },
    relationships: { app: { data: { type: 'apps', id: APP } } } } }), 'iap').data.id; save();
}
if (!o.lifetimeLoc) {
  o.lifetimeLoc = must(await api('POST', '/v1/inAppPurchaseLocalizations', { data: { type: 'inAppPurchaseLocalizations',
    attributes: { name: 'Soccer Max Lifetime', description: 'Every drill, session and film. Pay once. 40% off.', locale: 'en-US' },
    relationships: { inAppPurchaseV2: { data: { type: 'inAppPurchases', id: o.lifetime } } } } }), 'iap loc').data.id; save();
}
if (!o.lifetimePrice) {
  const us = (await all(`/v2/inAppPurchases/${o.lifetime}/pricePoints?filter%5Bterritory%5D=USA&limit=200`))
    .find(p => p.attributes.customerPrice === '23.99');
  if (!us) { console.error('no 23.99 price point'); process.exit(1) }
  o.lifetimePrice = must(await api('POST', '/v1/inAppPurchasePriceSchedules', {
    data: { type: 'inAppPurchasePriceSchedules', relationships: {
      inAppPurchase: { data: { type: 'inAppPurchases', id: o.lifetime } },
      baseTerritory: { data: { type: 'territories', id: 'USA' } },
      manualPrices: { data: [{ type: 'inAppPurchasePrices', id: '${p1}' }] } } },
    included: [{ type: 'inAppPurchasePrices', id: '${p1}', attributes: { startDate: null },
      relationships: { inAppPurchaseV2: { data: { type: 'inAppPurchases', id: o.lifetime } },
        inAppPurchasePricePoint: { data: { type: 'inAppPurchasePricePoints', id: us.id } } } }] }), 'iap price').data.id; save();
}
if (!o.lifetimeAvail) {
  o.lifetimeAvail = must(await api('POST', '/v1/inAppPurchaseAvailabilities', { data: { type: 'inAppPurchaseAvailabilities',
    attributes: { availableInNewTerritories: true },
    relationships: { inAppPurchase: { data: { type: 'inAppPurchases', id: o.lifetime } },
      availableTerritories: { data: territories.map(id => ({ type: 'territories', id })) } } } }), 'iap availability').data.id; save();
}

// --- App Review screenshot on all three
const file = process.env.SHOT || 'offer-review.png';
if (fs.existsSync(file)) {
  const bytes = fs.readFileSync(file), md5 = crypto.createHash('md5').update(bytes).digest('hex');
  async function upload(key, type, rel, relType, id) {
    if (o[key]) return;
    const r = must(await api('POST', `/v1/${type}`, { data: { type, attributes: { fileName: file, fileSize: bytes.length },
      relationships: { [rel]: { data: { type: relType, id } } } } }), key);
    const shot = r.data;
    for (const op of shot.attributes.uploadOperations) {
      const headers = Object.fromEntries((op.requestHeaders || []).map(h => [h.name, h.value]));
      await fetch(op.url, { method: op.method, headers, body: bytes.subarray(op.offset, op.offset + op.length) });
    }
    must(await api('PATCH', `/v1/${type}/${shot.id}`, { data: { type, id: shot.id, attributes: { uploaded: true, sourceFileChecksum: md5 } } }), key + ' commit');
    o[key] = shot.id; save();
  }
  await upload('yearlyShot', 'subscriptionAppStoreReviewScreenshots', 'subscription', 'subscriptions', o.yearly);
  await upload('monthlyShot', 'subscriptionAppStoreReviewScreenshots', 'subscription', 'subscriptions', o.monthly);
  await upload('lifetimeShot', 'inAppPurchaseAppStoreReviewScreenshots', 'inAppPurchaseV2', 'inAppPurchases', o.lifetime);
} else console.log('no review screenshot yet:', file);

console.log(o);
for (const k of ['yearly', 'monthly']) console.log(k, (await api('GET', `/v1/subscriptions/${o[k]}`)).j.data?.attributes?.state);
console.log('lifetime', (await api('GET', `/v2/inAppPurchases/${o.lifetime}`)).j.data?.attributes?.state);
