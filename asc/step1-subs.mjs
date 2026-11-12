// Step 1: subscription group "SOCCER MAX" + monthly + yearly (with App Store names/descriptions).
import fs from 'node:fs';
import { api } from './asc.mjs';
const APP = '6828180179';
const ids = fs.existsSync('ids.json') ? JSON.parse(fs.readFileSync('ids.json')) : {};
const save = () => fs.writeFileSync('ids.json', JSON.stringify(ids, null, 1));
const must = (r, what) => { if (r.status >= 300) { console.error('FAILED', what); process.exit(1) } return r.j.data };

if (!ids.group) {
  ids.group = must(await api('POST', '/v1/subscriptionGroups', { data: { type: 'subscriptionGroups', attributes: { referenceName: 'SOCCER MAX' },
    relationships: { app: { data: { type: 'apps', id: APP } } } } }), 'group').id; save();
  must(await api('POST', '/v1/subscriptionGroupLocalizations', { data: { type: 'subscriptionGroupLocalizations',
    attributes: { name: 'SOCCER MAX', locale: 'en-US' },
    relationships: { subscriptionGroup: { data: { type: 'subscriptionGroups', id: ids.group } } } } }), 'group loc');
}
const subs = [
  { key: 'yearly', name: 'SOCCER MAX Yearly', productId: 'com.jacksteiner.soccermax.yearly', period: 'ONE_YEAR', level: 1,
    loc: { name: 'Soccer Max Yearly', description: 'Every drill, session and film. 7 days free.' } },
  { key: 'monthly', name: 'SOCCER MAX Monthly', productId: 'com.jacksteiner.soccermax.monthly', period: 'ONE_MONTH', level: 2,
    loc: { name: 'Soccer Max Monthly', description: 'Every drill, session and film.' } },
];
for (const s of subs) {
  if (ids[s.key]) continue;
  ids[s.key] = must(await api('POST', '/v1/subscriptions', { data: { type: 'subscriptions',
    attributes: { name: s.name, productId: s.productId, subscriptionPeriod: s.period, groupLevel: s.level, familySharable: false },
    relationships: { group: { data: { type: 'subscriptionGroups', id: ids.group } } } } }), s.key).id; save();
  must(await api('POST', '/v1/subscriptionLocalizations', { data: { type: 'subscriptionLocalizations',
    attributes: { ...s.loc, locale: 'en-US' },
    relationships: { subscription: { data: { type: 'subscriptions', id: ids[s.key] } } } } }), s.key + ' loc');
}
console.log(ids);
