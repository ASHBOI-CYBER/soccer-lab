// Step 12 (2026-11-01): the 6 iPhone Duo screenshots (out/app-store/screenshots-duo/01?06.jpg, 2007×2853 = Duo inner
// display, portrait; made by app/store-screenshots/render3d/duo.mjs) ? the APP_IPHONE_DUO set on every listing locale
// of version 1.0. With an Xcode 27.1+ build (build 5) this is what turns on the "Made for iPhone Duo" badge.
// Re-runnable: the old Duo set on each locale is deleted first. Then waits until every screenshot is COMPLETE.
import fs from 'node:fs'; import crypto from 'node:crypto';
import { api } from './asc.mjs';
const APP = '6828180179', TYPE = 'APP_IPHONE_DUO';
const DIR = new URL('../../../out/app-store/screenshots-duo/', import.meta.url).pathname;
const ok = (what, r) => { console.log(r.status < 300 ? 'ok  ' : 'FAIL', what, r.status < 300 ? '' : JSON.stringify(r.j.errors?.map(e => e.detail || e.title)).slice(0, 500)); return r.status < 300; };
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const files = fs.readdirSync(DIR).filter(f => /^\d\d\.jpg$/.test(f)).sort();
const vers = await api('GET', `/v1/apps/${APP}/appStoreVersions?filter%5BversionString%5D=1.0&include=appStoreVersionLocalizations`);
const locs = vers.j.included || [];
const made = [];
for (const vl of locs) {
  const sets = await api('GET', `/v1/appStoreVersionLocalizations/${vl.id}/appScreenshotSets`);
  for (const s of sets.j.data.filter(s => s.attributes.screenshotDisplayType === TYPE)) await api('DELETE', `/v1/appScreenshotSets/${s.id}`);
  const set = await api('POST', '/v1/appScreenshotSets', { data: { type: 'appScreenshotSets', attributes: { screenshotDisplayType: TYPE },
    relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: vl.id } } } } });
  if (!ok(`${vl.attributes.locale} Duo set`, set)) continue;
  for (const f of files) {
    const bytes = fs.readFileSync(DIR + f), md5 = crypto.createHash('md5').update(bytes).digest('hex');
    const name = `soccermax-duo-${f}`;
    const r = await api('POST', '/v1/appScreenshots', { data: { type: 'appScreenshots', attributes: { fileName: name, fileSize: bytes.length },
      relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: set.j.data.id } } } } });
    if (!ok(`${vl.attributes.locale} reserve ${name}`, r)) continue;
    for (const op of r.j.data.attributes.uploadOperations) {
      const headers = Object.fromEntries((op.requestHeaders || []).map(h => [h.name, h.value]));
      const put = await fetch(op.url, { method: op.method, headers, body: bytes.subarray(op.offset, op.offset + op.length) });
      if (!put.ok) throw new Error(`PUT ${name}: ${put.status}`);
    }
    if (ok(`${vl.attributes.locale} ${name}`, await api('PATCH', `/v1/appScreenshots/${r.j.data.id}`, { data: { type: 'appScreenshots', id: r.j.data.id, attributes: { uploaded: true, sourceFileChecksum: md5 } } })))
      made.push(r.j.data.id);
  }
}
// wait for Apple to process them (fresh ones sit at UPLOAD_COMPLETE for a few minutes ? notes/37)
for (let i = 0; i < 40; i++) {
  const st = await Promise.all(made.map(async id => (await api('GET', `/v1/appScreenshots/${id}`)).j.data?.attributes?.assetDeliveryState?.state));
  const done = st.filter(s => s === 'COMPLETE').length, bad = st.filter(s => s === 'FAILED').length;
  console.log(`processing: ${done}/${made.length} complete${bad ? `, ${bad} FAILED` : ''}`);
  if (done + bad === made.length) break;
  await sleep(30000);
}
