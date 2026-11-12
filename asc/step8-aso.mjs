// Step 8 (2026-10-29): ASO pass ? new title/subtitle/keywords/promo (en-US), the two extra locales Apple ALSO indexes
// for the US store (es-MX + fr-FR, each its own 100-char keyword field, no repeated words), and the 6.9" screenshots.
// Research + reasoning: notes/37-aso-launch.md. Re-runnable (PATCHes; screenshots replaced only with SHOTS=1).
import fs from 'node:fs'; import crypto from 'node:crypto';
import { api } from './asc.mjs';
const APP = '6828180179';
const ok = (what, r) => console.log(r.status < 300 ? 'ok  ' : 'FAIL', what, r.status < 300 ? '' : JSON.stringify(r.j.errors?.map(e => e.detail || e.title)).slice(0, 500));

const subsText = {
  'es-MX': `Soccer Max se descarga gratis. El acceso completo necesita uno de estos planes: Anual ($29.99 al año, con 7 días gratis para nuevos suscriptores), Mensual ($9.99 al mes) o De por vida ($39.99, un solo pago). Los precios pueden variar según tu país. El pago se carga a tu Apple ID al confirmar la compra. La suscripción se renueva automáticamente salvo que desactives la renovación al menos 24 horas antes de que termine el periodo actual; el cargo de renovación se hace en las 24 horas previas. Puedes administrar o cancelar tu suscripción en los ajustes de tu cuenta del App Store. Cualquier parte no usada de la prueba gratis termina al comprar una suscripción.`,
  'fr-FR': `Soccer Max est gratuit à télécharger. L'accès complet demande un de ces forfaits : Annuel (29,99 $ par an, 7 jours gratuits pour les nouveaux abonnés), Mensuel (9,99 $ par mois) ou À vie (39,99 $, un seul paiement). Les prix peuvent varier selon votre pays. Le paiement est débité sur votre identifiant Apple à la confirmation de l'achat. L'abonnement se renouvelle automatiquement sauf si vous désactivez le renouvellement au moins 24 heures avant la fin de la période en cours ; le renouvellement est débité dans les 24 heures avant la fin de la période. Gérez ou annulez votre abonnement dans les réglages de votre compte App Store. Toute partie non utilisée d'un essai gratuit prend fin à l'achat d'un abonnement.`,
};
const L = {
  'en-US': {
    name: 'Soccer Max: Training & Drills', subtitle: 'Football Skills & Workout Plan',
    keywords: 'trainer,practice,dribbling,ball,mastery,juggling,footwork,touch,passing,shooting,agility,speed,coach',
    promo: 'Watch 400+ soccer drills in 3D, then train them. Get a weekly plan built for your position and level, keep your streak alive and climb your team leaderboard.',
  },
  'es-MX': {
    name: 'Soccer Max: Entrena Fútbol', subtitle: 'Ejercicios, regates y rutinas',
    keywords: 'pelota,entrenamiento,ejercicio,weak,foot,stretch,warmup,core,ladder,conditioning,technique,control',
    promo: 'Mira más de 400 ejercicios de fútbol en 3D y entrénalos. Un plan semanal para tu posición y tu nivel, tu racha y la tabla de tu equipo.',
    description: `Entrena como los profesionales, 10 minutos a la vez.

Soccer Max es una app de entrenamiento de fútbol para jugadores de 13 años en adelante. Cada ejercicio te muestra exactamente qué hacer, para entrenar solo, con un amigo o con tu equipo.

EJERCICIOS QUE PUEDES VER
? Más de 400 ejercicios: regate, primer toque, pase, tiro, dominadas, pierna débil, físico y más
? Cada ejercicio es un video de un jugador en 3D o una pizarra clara vista desde arriba
? Series, repeticiones y pasos simples

SESIONES HECHAS PARA TI
? Un plan semanal según tu posición, tu nivel y los días que puedes entrenar
? Sesiones listas de técnica y físico, del parque al nivel mundial

PARTIDOS REALES EN 3D
? Partidos de las mejores ligas convertidos en resúmenes 3D que explican cada jugada

TU PROGRESO Y TU EQUIPO
? Racha, niveles, rangos y widgets
? Crea un equipo o únete con un código: chat, racha de equipo y tabla

SUSCRIPCIÓN
${subsText['es-MX']}

Términos de uso: https://soccermax.app/terms/
Política de privacidad: https://soccermax.app/privacy/`,
  },
  'fr-FR': {
    name: 'Soccer Max : Entraînement Foot', subtitle: 'Exercices de foot en 3D',
    keywords: 'tactics,highlight,streak,team,leaderboard,youth,teen,athlete,strength,sprint,cone,solo,home,player',
    promo: 'Plus de 400 exercices de foot en 3D, un plan chaque semaine pour votre poste et votre niveau, votre série et le classement de votre équipe.',
    description: `Entraînez-vous comme les pros, 10 minutes à la fois.

Soccer Max est une app d'entraînement de football pour les joueurs de 13 ans et plus. Chaque exercice vous montre exactement quoi faire, seul, avec un ami ou avec votre équipe.

DES EXERCICES QUE VOUS VOYEZ
? Plus de 400 exercices : dribble, contrôle, passe, frappe, jonglage, pied faible, physique et plus
? Chaque exercice est une vidéo d'un joueur en 3D ou un tableau vu de dessus
? Séries, répétitions et étapes simples

DES SÉANCES POUR VOUS
? Un plan chaque semaine selon votre poste, votre niveau et vos jours libres
? Séances prêtes de technique et de physique

DE VRAIS MATCHS EN 3D
? Les matchs des grands championnats refaits en résumés 3D qui expliquent chaque action

VOTRE PROGRESSION ET VOTRE ÉQUIPE
? Série, niveaux, rangs et widgets
? Créez une équipe ou rejoignez-en une avec un code : chat, série d'équipe et classement

ABONNEMENT
${subsText['fr-FR']}

Conditions d'utilisation : https://soccermax.app/terms/
Politique de confidentialité : https://soccermax.app/privacy/`,
  },
};
// guard the limits + the no-repeat rule inside each locale
for (const [loc, v] of Object.entries(L)) {
  if (v.name.length > 30 || v.subtitle.length > 30 || v.keywords.length > 100 || v.promo.length > 170) throw new Error(`${loc} too long: ${v.name.length}/${v.subtitle.length}/${v.keywords.length}/${v.promo.length}`);
  const words = (v.name + ' ' + v.subtitle).toLowerCase().split(/[^a-zà-ÿ]+/);
  const dup = v.keywords.split(',').filter(k => words.includes(k)); if (dup.length) throw new Error(`${loc} repeats ${dup}`);
  console.log(loc, `name ${v.name.length} · subtitle ${v.subtitle.length} · keywords ${v.keywords.length} · promo ${v.promo.length}`);
}

// app info (name + subtitle + privacy URL) per locale
const infos = await api('GET', `/v1/apps/${APP}/appInfos?include=appInfoLocalizations`);
const info = infos.j.data.find(i => i.attributes.appStoreState !== 'READY_FOR_DISTRIBUTION') || infos.j.data[0];
const ilocs = (infos.j.included || []).filter(l => l.type === 'appInfoLocalizations');
for (const [loc, v] of Object.entries(L)) {
  const attributes = { name: v.name, subtitle: v.subtitle, privacyPolicyUrl: 'https://soccermax.app/privacy/' };
  const have = ilocs.find(l => l.attributes.locale === loc);
  ok(`${loc} name + subtitle`, have
    ? await api('PATCH', `/v1/appInfoLocalizations/${have.id}`, { data: { type: 'appInfoLocalizations', id: have.id, attributes } })
    : await api('POST', '/v1/appInfoLocalizations', { data: { type: 'appInfoLocalizations', attributes: { locale: loc, ...attributes },
        relationships: { appInfo: { data: { type: 'appInfos', id: info.id } } } } }));
}

// version text per locale
const vers = await api('GET', `/v1/apps/${APP}/appStoreVersions?filter%5BversionString%5D=1.0&include=appStoreVersionLocalizations`);
const ver = vers.j.data[0];
const vlocs = vers.j.included || [];
for (const [loc, v] of Object.entries(L)) {
  const attributes = { keywords: v.keywords, promotionalText: v.promo, supportUrl: 'https://soccermax.app/support/', marketingUrl: 'https://soccermax.app/',
    ...(v.description ? { description: v.description } : {}) };
  const have = vlocs.find(l => l.attributes.locale === loc);
  ok(`${loc} keywords + promo`, have
    ? await api('PATCH', `/v1/appStoreVersionLocalizations/${have.id}`, { data: { type: 'appStoreVersionLocalizations', id: have.id, attributes } })
    : await api('POST', '/v1/appStoreVersionLocalizations', { data: { type: 'appStoreVersionLocalizations', attributes: { locale: loc, ...attributes },
        relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: ver.id } } } } }));
}

// screenshots: the same 6.9" set on every locale (Apple shows the primary set when a locale has none, but we upload to be sure)
if (process.env.SHOTS) {
  const dir = new URL('./shots/out/', import.meta.url).pathname;
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.jpg')).sort();
  const fresh = await api('GET', `/v1/apps/${APP}/appStoreVersions?filter%5BversionString%5D=1.0&include=appStoreVersionLocalizations`);
  for (const vl of fresh.j.included) {
    const sets = await api('GET', `/v1/appStoreVersionLocalizations/${vl.id}/appScreenshotSets`);
    for (const s of sets.j.data.filter(s => s.attributes.screenshotDisplayType === 'APP_IPHONE_67')) await api('DELETE', `/v1/appScreenshotSets/${s.id}`);
    const set = await api('POST', '/v1/appScreenshotSets', { data: { type: 'appScreenshotSets', attributes: { screenshotDisplayType: 'APP_IPHONE_67' },
      relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: vl.id } } } } });
    for (const f of files) {
      const bytes = fs.readFileSync(dir + f), md5 = crypto.createHash('md5').update(bytes).digest('hex');
      const r = await api('POST', '/v1/appScreenshots', { data: { type: 'appScreenshots', attributes: { fileName: f, fileSize: bytes.length },
        relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: set.j.data.id } } } } });
      for (const op of r.j.data.attributes.uploadOperations) {
        const headers = Object.fromEntries((op.requestHeaders || []).map(h => [h.name, h.value]));
        const put = await fetch(op.url, { method: op.method, headers, body: bytes.subarray(op.offset, op.offset + op.length) });
        if (!put.ok) console.log('FAIL put', f, put.status);
      }
      ok(`${vl.attributes.locale} ${f}`, await api('PATCH', `/v1/appScreenshots/${r.j.data.id}`, { data: { type: 'appScreenshots', id: r.j.data.id, attributes: { uploaded: true, sourceFileChecksum: md5 } } }));
    }
  }
}
