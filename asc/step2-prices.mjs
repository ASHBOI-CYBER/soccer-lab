// Step 2: availability (all territories), prices ($9.99 / $29.99 US + Apple's equalized price everywhere else),
// and a 1-week FREE TRIAL intro offer on yearly in every territory.
import fs from 'node:fs';
import { api } from './asc.mjs';
const ids = JSON.parse(fs.readFileSync('ids.json'));
const must = (r, what) => { if (r.status >= 300) { console.error('FAILED', what); process.exit(1) } return r.j };

async function all(path) {
  let out = [], next = path;
  while (next) {
    const r = must(await api('GET', next), next);
    out = out.concat(r.data); next = r.links?.next ? r.links.next.replace('https://api.appstoreconnect.apple.com', '') : null;
  }
  return out;
}

const territories = (await all('/v1/territories?limit=200')).map(t => t.id);
console.log('territories', territories.length);

for (const [key, usd] of [['monthly', '9.99'], ['yearly', '29.99']]) {
  const sub = ids[key];
  if (!ids[key + 'Avail']) {
    const r = must(await api('POST', '/v1/subscriptionAvailabilities', { data: { type: 'subscriptionAvailabilities',
      attributes: { availableInNewTerritories: true },
      relationships: { subscription: { data: { type: 'subscriptions', id: sub } },
        availableTerritories: { data: territories.map(id => ({ type: 'territories', id })) } } } }), key + ' availability');
    ids[key + 'Avail'] = r.data.id; fs.writeFileSync('ids.json', JSON.stringify(ids, null, 1));
  }
  const us = (await all(`/v1/subscriptions/${sub}/pricePoints?filter%5Bterritory%5D=USA&limit=200`))
    .find(p => p.attributes.customerPrice === usd);
  if (!us) { console.error('no US price point', usd); process.exit(1) }
  const eq = await all(`/v1/subscriptionPricePoints/${us.id}/equalizations?limit=200&include=territory`);
  const points = [{ id: us.id, terr: 'USA' }, ...eq.map(p => ({ id: p.id, terr: p.relationships?.territory?.data?.id }))];
  let ok = 0, bad = [];
  for (const p of points) {
    const r = await api('POST', '/v1/subscriptionPrices', { data: { type: 'subscriptionPrices',
      attributes: { preserveCurrentPrice: false },
      relationships: { subscription: { data: { type: 'subscriptions', id: sub } },
        subscriptionPricePoint: { data: { type: 'subscriptionPricePoints', id: p.id } } } } });
    r.status < 300 ? ok++ : bad.push(p.terr);
  }
  console.log(key, `US ${usd}: prices set in ${ok}/${points.length}`, bad.length ? 'failed: ' + bad.join(',') : '');
}

// 7 days free on yearly, every territory
let ok = 0, bad = [];
for (const t of territories) {
  const r = await api('POST', '/v1/subscriptionIntroductoryOffers', { data: { type: 'subscriptionIntroductoryOffers',
    attributes: { duration: 'ONE_WEEK', offerMode: 'FREE_TRIAL', numberOfPeriods: 1 },
    relationships: { subscription: { data: { type: 'subscriptions', id: ids.yearly } }, territory: { data: { type: 'territories', id: t } } } } });
  r.status < 300 ? ok++ : bad.push(t);
}
console.log(`free trial set in ${ok}/${territories.length}`, bad.length ? 'failed: ' + bad.slice(0, 20).join(',') : '');
