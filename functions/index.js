/**
 * Finders Keepers — Cloud Functions (2nd gen).
 *
 *  onItemCreated   push "possible match" alerts to owners of similar
 *                  opposite-type items (text + category + location + photo hash)
 *  onClaimCreated  alert the finder; flag claimants who claim too often
 *  onClaimUpdated  alert the claimant when their claim is decided/completed
 *
 * Deploy:  cd functions && npm install && firebase deploy --only functions
 * (Cloud Functions require the Blaze plan.)
 */
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

const MATCH_THRESHOLD = 0.45;
const MAX_CLAIMS_PER_DAY = 5;

// ---- Matching (mirror of lib/services/matching.dart) -----------------------

function hamming(a, b) {
  if (!a || !b || a.length !== 16 || b.length !== 16) return 64;
  let x = BigInt("0x" + a) ^ BigInt("0x" + b);
  let d = 0;
  while (x > 0n) { d += Number(x & 1n); x >>= 1n; }
  return d;
}

function metres(a, b) {
  const R = 6371000, rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad, dLng = (b.lng - a.lng) * rad;
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

function toDate(v) {
  return v instanceof Timestamp ? v.toDate() : new Date(v ?? Date.now());
}

function scoreMatch(a, b) {
  let score = 0;
  if (a.category === b.category) score += 0.30;
  const ka = new Set(a.keywords || []), kb = new Set(b.keywords || []);
  if (ka.size && kb.size) {
    const inter = [...ka].filter((k) => kb.has(k)).length;
    const union = new Set([...ka, ...kb]).size;
    score += 0.30 * Math.min(1, (inter / union) * 2.5);
  }
  if (a.color && b.color && a.color.trim().toLowerCase() === b.color.trim().toLowerCase()) {
    score += 0.10;
  }
  const m = metres(a, b);
  if (m < 600) score += 0.15 * (1 - m / 600);
  const days = Math.abs(toDate(a.occurredAt) - toDate(b.occurredAt)) / 864e5;
  if (days < 7) score += 0.05 * (1 - days / 7);
  let best = 0;
  for (const ha of a.imageHashes || []) {
    for (const hb of b.imageHashes || []) best = Math.max(best, 1 - hamming(ha, hb) / 64);
  }
  if (best > 0.6) score += 0.25 * ((best - 0.6) / 0.4);
  return Math.min(1, score);
}

// ---- Notifications ---------------------------------------------------------

async function notify(uid, title, body, data = {}) {
  const userRef = db.collection("users").doc(uid);
  await userRef.collection("notifications").add({
    title, body, data, read: false, createdAt: FieldValue.serverTimestamp(),
  });
  const user = await userRef.get();
  const tokens = user.get("fcmTokens") || [];
  if (!tokens.length) return;
  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data,
    android: { priority: "high", notification: { channelId: "matches" } },
  });
  const stale = tokens.filter((_, i) => {
    const code = res.responses[i].error?.code;
    return code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token";
  });
  if (stale.length) await userRef.update({ fcmTokens: FieldValue.arrayRemove(...stale) });
}

// ---- Triggers --------------------------------------------------------------

exports.onItemCreated = onDocumentCreated("items/{itemId}", async (event) => {
  const item = event.data?.data();
  if (!item) return;
  const opposite = item.type === "lost" ? "found" : "lost";
  const since = Timestamp.fromMillis(Date.now() - 30 * 864e5);
  const snap = await db.collection("items")
    .where("type", "==", opposite)
    .where("category", "==", item.category)
    .where("createdAt", ">=", since)
    .orderBy("createdAt", "desc")
    .limit(100)
    .get();

  const matches = snap.docs
    .map((d) => d.data())
    .filter((c) => ["lost", "found"].includes(c.status) && c.reporterId !== item.reporterId)
    .map((c) => ({ c, score: scoreMatch(item, c) }))
    .filter((m) => m.score >= MATCH_THRESHOLD)
    .sort((x, y) => y.score - x.score)
    .slice(0, 5);

  logger.info(`item ${item.id}: ${matches.length} potential matches`);
  await Promise.all(matches.map(({ c, score }) =>
    notify(
      c.reporterId,
      `Possible match for "${c.title}"`,
      `${item.type === "found" ? "Found" : "Lost"}: ${item.title} near ${item.locationName} ` +
        `(${Math.round(score * 100)}% match)`,
      { itemId: item.id },
    )));
  if (matches.length) {
    await notify(
      item.reporterId,
      "We found possible matches",
      `${matches.length} report(s) look similar to "${item.title}". Open the item to check.`,
      { itemId: item.id },
    );
  }
});

exports.onClaimCreated = onDocumentCreated("claims/{claimId}", async (event) => {
  const claim = event.data?.data();
  if (!claim) return;

  // Anti-fraud: flag users who fire off many claims in a short time.
  const dayAgo = Timestamp.fromMillis(Date.now() - 864e5);
  const recent = await db.collection("claims")
    .where("claimantId", "==", claim.claimantId)
    .where("createdAt", ">=", dayAgo)
    .count()
    .get();
  const n = recent.data().count;
  if (n > MAX_CLAIMS_PER_DAY) {
    await event.data.ref.update({
      flagReason: `This user submitted ${n} claims in the last 24 hours.`,
    });
  }

  await notify(
    claim.itemReporterId,
    "New ownership claim",
    `${claim.claimantAlias} claims "${claim.itemTitle}". Review their answers.`,
    { claimId: claim.id },
  );
});

exports.onClaimUpdated = onDocumentUpdated("claims/{claimId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.status === after.status) return;
  const messages = {
    approved: "Your claim was approved! Open the app to see your handover code.",
    rejected: `Your claim was not approved: ${after.rejectionReason || ""}`,
    completed: "Handover complete — enjoy having your item back!",
  };
  if (messages[after.status]) {
    await notify(after.claimantId, `Claim update: ${after.itemTitle}`,
      messages[after.status], { claimId: after.id });
  }
});
