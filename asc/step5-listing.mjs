// Step 5 (2026-10-28): the App Store listing for version 1.0 ? text, URLs, categories, free price, age rating, review notes.
// Re-runnable: every call is a PATCH of the same values (the price schedule is skipped once set).
import { api } from './asc.mjs';
const APP = '6828180179';
const report = (what, r) => console.log(r.status < 300 ? 'ok  ' : 'FAIL', what, r.status < 300 ? '' : JSON.stringify(r.j.errors?.map(e => e.detail || e.title)).slice(0, 400));

const description = `Train like the pros, 10 minutes at a time.

Soccer Max is a soccer training app for players 13 and up. Every drill shows you exactly what to do, so you can train on your own, with a friend or with your team.

DRILLS YOU CAN SEE
? 400+ drills: dribbling, first touch, passing, shooting, juggling, weak foot, fitness and more
? Every drill is a video of a 3D player doing it, or a clear top-down coach board
? Sets, reps and simple steps for every drill

SESSIONS BUILT FOR YOU
? Answer a few questions and get a training week planned around your position, your level and the days you can train
? Ready-made skill and fitness sessions, from park level to world class
? Build and save your own sessions

MATCHDAY
? Real games from the top leagues, rebuilt in 3D as short highlight reels
? Each key moment freezes and shows you what happened and why

TRACK YOUR GAME
? Keep your streak alive with 10 minutes of training every 3 days
? Watch your player graph grow as you train
? Levels, ranks and your minutes week by week
? Home screen widgets for your streak and your training days

TRAIN WITH YOUR TEAM
? Make a team or join one with a 6-digit code
? Team chat, a team streak everyone keeps alive, and a leaderboard
? Joining a friend's team gets you 7 days free

SUBSCRIPTION
Soccer Max is free to download. Full access needs one of these:
? Yearly: $29.99 per year, with a 7-day free trial for new subscribers
? Monthly: $9.99 per month
? Lifetime: $39.99, paid once
Prices are in US dollars and may be different in your country. Payment is charged to your Apple ID when you confirm the purchase. Subscriptions renew automatically unless you turn off auto-renew at least 24 hours before the end of the current period, and your account is charged for the renewal within 24 hours before the period ends. You can manage or cancel your subscription in your App Store account settings. Any unused part of a free trial ends when you buy a subscription.

Terms of Use: https://soccermax.app/terms/
Privacy Policy: https://soccermax.app/privacy/`;

const keywords = 'football,drills,training,skills,dribbling,workout,coach,practice,footwork,juggling,team,fitness';
if (keywords.length > 100) throw new Error('keywords too long ' + keywords.length);
const subtitle = 'Soccer drills you can see';
const promo = '400+ drills you can see in 3D, sessions built for your position, and real games broken down. 10 minutes keeps your streak alive.';

const vers = await api('GET', `/v1/apps/${APP}/appStoreVersions?filter%5BversionString%5D=1.0&include=appStoreVersionLocalizations`);
const ver = vers.j.data[0];
const vloc = vers.j.included.find(l => l.attributes.locale === 'en-US');

report('version text + URLs', await api('PATCH', `/v1/appStoreVersionLocalizations/${vloc.id}`, { data: { type: 'appStoreVersionLocalizations', id: vloc.id,
  attributes: { description, keywords, promotionalText: promo, supportUrl: 'https://soccermax.app/support/', marketingUrl: 'https://soccermax.app/' } } }));
report('copyright', await api('PATCH', `/v1/appStoreVersions/${ver.id}`, { data: { type: 'appStoreVersions', id: ver.id,
  attributes: { copyright: '2026 Soccer Max' } } }));

const infos = await api('GET', `/v1/apps/${APP}/appInfos?include=appInfoLocalizations`);
const info = infos.j.data.find(i => i.attributes.appStoreState !== 'READY_FOR_DISTRIBUTION') || infos.j.data[0];
const iloc = infos.j.included.find(l => l.type === 'appInfoLocalizations' && l.attributes.locale === 'en-US');
report('subtitle + privacy URL', await api('PATCH', `/v1/appInfoLocalizations/${iloc.id}`, { data: { type: 'appInfoLocalizations', id: iloc.id,
  attributes: { subtitle, privacyPolicyUrl: 'https://soccermax.app/privacy/' } } }));
report('categories', await api('PATCH', `/v1/appInfos/${info.id}`, { data: { type: 'appInfos', id: info.id, relationships: {
  primaryCategory: { data: { type: 'appCategories', id: 'HEALTH_AND_FITNESS' } },
  secondaryCategory: { data: { type: 'appCategories', id: 'SPORTS' } } } } }));

// age rating: a training app with team chat between users ? user content + messaging; everything else none/no
report('age rating', await api('PATCH', `/v1/ageRatingDeclarations/${info.id}`, { data: { type: 'ageRatingDeclarations', id: info.id, attributes: {
  alcoholTobaccoOrDrugUseOrReferences: 'NONE', contests: 'NONE', gamblingSimulated: 'NONE', gunsOrOtherWeapons: 'NONE',
  horrorOrFearThemes: 'NONE', matureOrSuggestiveThemes: 'NONE', medicalOrTreatmentInformation: 'NONE',
  profanityOrCrudeHumor: 'NONE', sexualContentGraphicAndNudity: 'NONE', sexualContentOrNudity: 'NONE',
  violenceCartoonOrFantasy: 'NONE', violenceRealistic: 'NONE', violenceRealisticProlongedGraphicOrSadistic: 'NONE',
  gambling: false, lootBox: false, unrestrictedWebAccess: false, advertising: false, ageAssurance: false, parentalControls: false,
  healthOrWellnessTopics: true, messagingAndChat: true, userGeneratedContent: true, socialMedia: false,
  ageRatingOverrideV2: 'THIRTEEN_PLUS' } } }));  // the app, privacy policy + terms are for 13 and up (onboarding decision)

// free app (the money is the in-app purchases)
const sched = await api('GET', `/v1/apps/${APP}/appPriceSchedule?include=manualPrices`);
if (!(sched.j.included || []).length) {
  const pts = await api('GET', `/v1/apps/${APP}/appPricePoints?filter%5Bterritory%5D=USA&limit=10`);
  const free = pts.j.data.find(p => Number(p.attributes.customerPrice) === 0);
  report('price = free', await api('POST', '/v1/appPriceSchedules', { data: { type: 'appPriceSchedules', relationships: {
      app: { data: { type: 'apps', id: APP } }, baseTerritory: { data: { type: 'territories', id: 'USA' } },
      manualPrices: { data: [{ type: 'appPrices', id: '${free}' }] } } },
    included: [{ type: 'appPrices', id: '${free}', attributes: { startDate: null },
      relationships: { appPricePoint: { data: { type: 'appPricePoints', id: free.id } } } }] }));
} else console.log('ok   price already set');

const notes = `Soccer Max is a soccer training app. Notes for review:
1. Paywall: after onboarding, full access needs a purchase: Monthly ($9.99), Yearly ($29.99, 7-day free trial) or Lifetime ($39.99). All three in-app purchases are attached to this version. Restore Purchases is on the paywall and in Settings.
2. Teams are optional. Sign in with Apple is used only to make or join a team. Joining a team with a 6-digit code also gives 7 days free, once per Apple ID, no payment. Everything else works without signing in.
3. Matchday: match data (lineups, events) comes from API-Football. The app rebuilds each match as its own 3D animation; there is no match video footage.
4. Player photos on some sessions are Wikimedia Commons images used under their licenses and credited in the app.
5. No ads and no tracking.`;
const contact = process.env.PHONE ? { contactFirstName: 'Jack', contactLastName: 'Steiner', contactEmail: 'jacksteiner7@icloud.com', contactPhone: process.env.PHONE, demoAccountRequired: false, notes } : { demoAccountRequired: false, notes };  // PHONE=+1? node step5-listing.mjs adds the contact
const rd = await api('GET', `/v1/appStoreVersions/${ver.id}/appStoreReviewDetail`);
if (rd.j.data?.id) report('review notes', await api('PATCH', `/v1/appStoreReviewDetails/${rd.j.data.id}`, { data: { type: 'appStoreReviewDetails', id: rd.j.data.id, attributes: contact } }));
else report('review notes', await api('POST', '/v1/appStoreReviewDetails', { data: { type: 'appStoreReviewDetails', attributes: contact,
  relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: ver.id } } } } }));
