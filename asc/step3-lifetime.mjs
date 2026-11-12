// Step 3: LIFETIME $39.99 non-consumable, all territories (Apple equalizes prices from the US base price).
import fs from 'node:fs';
import { api } from './asc.mjs';
const APP = '6828180179';
const life = fs.existsSync('life.json') ? JSON.parse(fs.readFileSync('life.json')) : {};
const save = () => fs.writeFileSync('life.json', JSON.stringify(life, null, 1));
const must = (r, what) => { if (r.status >= 300) { console.error('FAILED', what); process.exit(1) } return r.j };
async function all(path) {
  let out = [], next = path;
  while (next) { const r = must(await api('GET', next), next); out = out.concat(r.data);
    next = r.links?.next ? r.links.next.replace('https://api.appstoreconnect.apple.com', '') : null; }
  return out;
}

if (!life.id) {
  life.id = must(await api('POST', '/v2/inAppPurchases', { data: { type: 'inAppPurchases',
    attributes: { name: 'SOCCER MAX Lifetime', productId: 'com.jacksteiner.soccermax.lifetime', inAppPurchaseType: 'NON_CONSUMABLE', familySharable: false },
    relationships: { app: { data: { type: 'apps', id: APP } } } } }), 'iap').data.id; save();
}
if (!life.loc) {
  life.loc = must(await api('POST', '/v1/inAppPurchaseLocalizations', { data: { type: 'inAppPurchaseLocalizations',
    attributes: { name: 'Soccer Max Lifetime', description: 'Every drill, session and film. Pay once.', locale: 'en-US' },
    relationships: { inAppPurchaseV2: { data: { type: 'inAppPurchases', id: life.id } } } } }), 'iap loc').data.id; save();
}
if (!life.price) {
  const us = (await all(`/v2/inAppPurchases/${life.id}/pricePoints?filter%5Bterritory%5D=USA&limit=200`))
    .find(p => p.attributes.customerPrice === '39.99');
  if (!us) { console.error('no 39.99 price point'); process.exit(1) }
  life.price = must(await api('POST', '/v1/inAppPurchasePriceSchedules', {
    data: { type: 'inAppPurchasePriceSchedules', relationships: {
      inAppPurchase: { data: { type: 'inAppPurchases', id: life.id } },
      baseTerritory: { data: { type: 'territories', id: 'USA' } },
      manualPrices: { data: [{ type: 'inAppPurchasePrices', id: '${p1}' }] } } },
    included: [{ type: 'inAppPurchasePrices', id: '${p1}', attributes: { startDate: null },
      relationships: { inAppPurchaseV2: { data: { type: 'inAppPurchases', id: life.id } },
        inAppPurchasePricePoint: { data: { type: 'inAppPurchasePricePoints', id: us.id } } } }] }), 'iap price').data.id; save();
}
if (!life.avail) {
  const territories = (await all('/v1/territories?limit=200')).map(t => t.id);
  life.avail = must(await api('POST', '/v1/inAppPurchaseAvailabilities', { data: { type: 'inAppPurchaseAvailabilities',
    attributes: { availableInNewTerritories: true },
    relationships: { inAppPurchase: { data: { type: 'inAppPurchases', id: life.id } },
      availableTerritories: { data: territories.map(id => ({ type: 'territories', id })) } } } }), 'iap availability').data.id; save();
  console.log('available in', territories.length);
}
console.log(life);
