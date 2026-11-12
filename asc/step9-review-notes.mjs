// Step 9 (2026-10-30; iPhone Duo line 8 added 2026-11-01): review notes only (step5 would also re-PATCH the old keywords ? don't re-run step5 after step8).
import { api } from './asc.mjs';
const APP = '6828180179';
const notes = `Soccer Max is a soccer training app. Notes for review:
1. Paywall: after onboarding, full access needs a purchase: Monthly ($9.99), Yearly ($29.99, 7-day free trial) or Lifetime ($39.99). The in-app purchases are attached to this version. Restore Purchases is on the paywall and in Settings.
2. Teams are optional. Sign in with Apple is used only to make or join a team (Team tab). Joining a team with a 6-digit code also gives 7 days free, once per Apple ID, no payment. Everything else works without signing in.
3. Account deletion: Profile > Settings (gear) > Delete account (shown once signed in). It deletes the account and all team data on our server right away.
4. Team chat safety: long-press any teammate's message > Report (6 reasons) or Block. Tap a player's picture for Report / Block / Unblock on their profile. Blocking hides all their posts at once; reported messages are hidden for the reporter and reviewed by us within 24 hours. A word filter stops the worst words being sent. Chat is text only (no photos or video), and only between players on the same team.
5. Matchday: match data (lineups, events) comes from API-Football. The app rebuilds each match as its own 3D animation; there is no match video footage.
6. Player photos on some sessions are Wikimedia Commons images used under their licenses and credited in the app.
7. No ads and no tracking.
8. iPhone Duo (built with Xcode 27.2, tested on the iPhone Duo simulator): the app works folded and open. Folded, the outer display uses the normal portrait iPhone layout with the tab bar on the side. Open, the inner display fills the whole screen in landscape: every page is a centered, readable column with the background edge to edge, so nothing stretches; the session player and match films fill the screen. Opening or closing the phone keeps you on the same page.`;
const vers = await api('GET', `/v1/apps/${APP}/appStoreVersions?filter%5BversionString%5D=1.0`);
const ver = vers.j.data[0];
const rd = await api('GET', `/v1/appStoreVersions/${ver.id}/appStoreReviewDetail`);
const attributes = { contactFirstName: 'Jack', contactLastName: 'Steiner', contactEmail: 'jacksteiner7@icloud.com', contactPhone: '+1 585 629 8648', demoAccountRequired: false, notes };
const r = rd.j.data?.id
  ? await api('PATCH', `/v1/appStoreReviewDetails/${rd.j.data.id}`, { data: { type: 'appStoreReviewDetails', id: rd.j.data.id, attributes } })
  : await api('POST', '/v1/appStoreReviewDetails', { data: { type: 'appStoreReviewDetails', attributes, relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: ver.id } } } } });
console.log(r.status < 300 ? 'ok   review notes' : 'FAIL review notes');
