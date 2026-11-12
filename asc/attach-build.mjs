// Wait for an uploaded build to finish processing, then attach it to version 1.0 (2026-11-01).
//   node attach-build.mjs 4      (build number; default = project.yml's CURRENT_PROJECT_VERSION)
import fs from 'node:fs';
import { api } from './asc.mjs';
const APP = '6828180179';
const want = process.argv[2] || /CURRENT_PROJECT_VERSION: "(\d+)"/.exec(fs.readFileSync('../project.yml', 'utf8'))[1];
const sleep = ms => new Promise(r => setTimeout(r, ms));
let b;
for (let i = 0; i < 90; i++) {           // up to 45 min
  const r = await api('GET', `/v1/builds?filter%5Bapp%5D=${APP}&filter%5Bversion%5D=${want}&filter%5BpreReleaseVersion.version%5D=1.0&limit=1`);
  b = r.j.data?.[0];
  const st = b?.attributes?.processingState;
  console.log(new Date().toLocaleTimeString(), 'build', want, st ?? 'not there yet');
  if (st === 'VALID') break;
  if (st === 'INVALID' || st === 'FAILED') { console.error('build processing failed'); process.exit(1); }
  await sleep(30000);
}
if (b?.attributes?.processingState !== 'VALID') { console.error('timed out'); process.exit(1); }
// no export-compliance question (ITSAppUsesNonExemptEncryption = NO in Info.plist)
const ver = (await api('GET', `/v1/apps/${APP}/appStoreVersions?filter%5BversionString%5D=1.0`)).j.data[0];
const r = await api('PATCH', `/v1/appStoreVersions/${ver.id}/relationships/build`, { data: { type: 'builds', id: b.id } });
console.log(r.status < 300 ? `ok   build ${want} attached to 1.0` : 'FAIL attach ' + JSON.stringify(r.j).slice(0, 300));
