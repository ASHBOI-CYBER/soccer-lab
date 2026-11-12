// Step 10 (2026-10-30): the v3 store art into App Store Connect, version 1.0, every listing locale (en-US, es-MX, fr-FR).
//  - 9 iPhone 6.9" screenshots (out/app-store/screenshots-6.9/*.png) replace the APP_IPHONE_67 set (set-based flow, as step 8)
//  - product page HEADER image (out/app-store/header-3840x1646.png) and SEARCH RESULTS video
//    (out/app-store/search-results-video-1920x1280-19s.mp4) through the App Asset Library: reserve ? PUT parts ?
//    PATCH uploaded ? wait for PREPARE_FOR_SUBMISSION ? one placement per locale (DEFAULT_PROFILE).
// Nothing is submitted for review. Re-runnable: old header/search placements on these locales are deleted first.
//   node step10-creatives.mjs            (SKIP_SHOTS=1 to leave the screenshots alone, SHOTS_ONLY=1 for just them)
//   HEADER_VIDEO=1 ? the header is the 3D-kicks + mascot VIDEO (out/app-store/header-video-3840x1646-19s.mp4, 2026-10-30 v2)
//   HEADER_FILE / SEARCH_FILE (+ _NAME, _POSTER) = other files in out/app-store (v5 cut-outs: header-cutouts-3840x1646.mp4,
//   search-cutouts-1920x1280.mp4)
//   SEARCH_ID=<appAssetLibraryVideos id> ? reuse an already-uploaded search video instead of uploading it again
import fs from 'node:fs'; import crypto from 'node:crypto';
import { api } from './asc.mjs';
const APP = '6828180179';
const OUT = new URL('../../../out/app-store/', import.meta.url).pathname;
const ok = (what, r) => { console.log(r.status < 300 ? 'ok  ' : 'FAIL', what, r.status < 300 ? '' : JSON.stringify(r.j.errors?.map(e => e.detail || e.title)).slice(0, 600)); return r.status < 300; };
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

const putParts = async (ops, bytes, name) => {
  for (const op of ops) {
    const headers = Object.fromEntries((op.requestHeaders || []).map(h => [h.name, h.value]));
    const put = await fetch(op.url, { method: op.method, headers, body: bytes.subarray(op.offset, op.offset + op.length) });
    if (!put.ok) throw new Error(`PUT ${name} part @${op.offset}: ${put.status}`);
  }
};

const vers = await api('GET', `/v1/apps/${APP}/appStoreVersions?filter%5BversionString%5D=1.0&include=appStoreVersionLocalizations`);
const ver = vers.j.data[0];
const locs = vers.j.included || [];
console.log('version 1.0', ver.attributes.appStoreState || ver.attributes.appVersionState, '· locales', locs.map(l => l.attributes.locale).join(', '));

// ---- 1. screenshots -------------------------------------------------------------------------------------------
if (!process.env.SKIP_SHOTS) {
  const dir = OUT + 'screenshots-6.9/';
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.png')).sort();
  for (const vl of locs) {
    const sets = await api('GET', `/v1/appStoreVersionLocalizations/${vl.id}/appScreenshotSets`);
    for (const s of sets.j.data.filter(s => s.attributes.screenshotDisplayType === 'APP_IPHONE_67')) await api('DELETE', `/v1/appScreenshotSets/${s.id}`);
    const set = await api('POST', '/v1/appScreenshotSets', { data: { type: 'appScreenshotSets', attributes: { screenshotDisplayType: 'APP_IPHONE_67' },
      relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: vl.id } } } } });
    if (!ok(`${vl.attributes.locale} screenshot set`, set)) continue;
    for (const f of files) {
      const bytes = fs.readFileSync(dir + f), md5 = crypto.createHash('md5').update(bytes).digest('hex');
      const name = `soccermax-${f.slice(0, 2)}.png`;
      const r = await api('POST', '/v1/appScreenshots', { data: { type: 'appScreenshots', attributes: { fileName: name, fileSize: bytes.length },
        relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: set.j.data.id } } } } });
      if (!ok(`${vl.attributes.locale} reserve ${name}`, r)) continue;
      await putParts(r.j.data.attributes.uploadOperations, bytes, name);
      ok(`${vl.attributes.locale} ${name}`, await api('PATCH', `/v1/appScreenshots/${r.j.data.id}`, { data: { type: 'appScreenshots', id: r.j.data.id, attributes: { uploaded: true, sourceFileChecksum: md5 } } }));
    }
  }
}

if (process.env.SHOTS_ONLY) { console.log('screenshots only ? done'); process.exit(0); }

// ---- 2. header image + search video into the asset library -----------------------------------------------------
const upload = async (kind, file, attrs) => {
  const bytes = fs.readFileSync(file);
  const type = kind === 'image' ? 'appAssetLibraryImages' : 'appAssetLibraryVideos';
  const r = await api('POST', `/v1/${type}`, { data: { type, attributes: { fileName: file.split('/').pop(), fileSize: bytes.length, category: 'CREATIVE_ASSETS', ...attrs },
    relationships: { assetLibrary: { data: { type: 'appAssetLibraries', id: APP } } } } });
  if (!ok(`reserve ${kind} ${attrs.referenceName}`, r)) throw new Error('reserve failed');
  await putParts(r.j.data.attributes.uploadOperations, bytes, file);
  ok(`commit ${kind}`, await api('PATCH', `/v1/${type}/${r.j.data.id}`, { data: { type, id: r.j.data.id, attributes: { uploaded: true } } }));
  for (let i = 0; i < 90; i++) {
    const g = await api('GET', `/v1/${type}/${r.j.data.id}`);
    const st = g.j.data?.attributes?.state;
    if (st === 'PREPARE_FOR_SUBMISSION') { console.log(`ok   ${kind} processed (spec ${g.j.data.attributes.specId})`); return r.j.data.id; }
    if (st === 'FAILED') throw new Error(`${kind} FAILED: ${JSON.stringify(g.j.data.attributes.stateDetails)}`);
    await sleep(10000);
  }
  throw new Error(`${kind} still processing after 15 min`);
};
const headerKind = process.env.HEADER_VIDEO ? 'video' : 'image';
const headerId = headerKind === 'video'
  ? await upload('video', OUT + (process.env.HEADER_FILE || 'header-video-3840x1646-19s.mp4'), { referenceName: process.env.HEADER_NAME || 'Header ? mascot + 3D kicks video (2026-10-30)', previewFrameTimeCode: process.env.HEADER_POSTER || '00:00:00:10' })
  : await upload('image', OUT + 'header-3840x1646.png', { referenceName: 'Header ? mascot LET\'S TRAIN (2026-10-30)' });
const videoId = process.env.SEARCH_ID || await upload('video', OUT + (process.env.SEARCH_FILE || 'search-results-video-1920x1280-19s.mp4'), { referenceName: process.env.SEARCH_NAME || 'Search ? 3D bicycle kicks (2026-10-30)', previewFrameTimeCode: process.env.SEARCH_POSTER || '00:00:06:15' });

// ---- 3. place them on every locale --------------------------------------------------------------------------------
for (const vl of locs) {
  const have = await api('GET', `/v1/appStoreVersionLocalizations/${vl.id}/placements?limit=50`);
  for (const p of (have.j.data || []).filter(p => ['PRODUCT_PAGE_HEADER_ASSET', 'APP_STORE_SEARCH_RESULTS_ASSET'].includes(p.attributes.placementType)))
    await api('DELETE', `/v1/appAssetLibraryPlacements/${p.id}`);
  const place = (placementType, rel, id) => api('POST', '/v1/appAssetLibraryPlacements', { data: { type: 'appAssetLibraryPlacements',
    attributes: { placementType, placementGroup: 'DEFAULT_PROFILE' },
    relationships: { [rel]: { data: { type: rel === 'image' ? 'appAssetLibraryImages' : 'appAssetLibraryVideos', id } },
      appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: vl.id } } } } });
  ok(`${vl.attributes.locale} header placement`, await place('PRODUCT_PAGE_HEADER_ASSET', headerKind, headerId));
  ok(`${vl.attributes.locale} search placement`, await place('APP_STORE_SEARCH_RESULTS_ASSET', 'video', videoId));
}
console.log('done ? header', headerId, '· video', videoId);
