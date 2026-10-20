const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.notifyOnMemberAdded = functions.firestore
  .document("groups/{groupId}")
  .onWrite(async (change, context) => {
    const groupId = context.params.groupId;
    const afterData = change.after.exists ? change.after.data() : null;
    const beforeData = change.before.exists ? change.before.data() : null;

    if (!afterData) return null; // Group was deleted

    const beforeUids = beforeData && beforeData.memberUids ? beforeData.memberUids : [];
    const afterUids = afterData.memberUids || [];

    // Identify newly added member UIDs
    const addedUids = afterUids.filter((uid) => !beforeUids.includes(uid));

    // Exclude the user who triggered the addition
    const actorUid = afterData.lastUpdatedBy || afterData.createdBy;
    const targets = addedUids.filter((uid) => uid !== actorUid);

    if (targets.length === 0) return null;

    const groupName = afterData.name || "an expense group";
    const senderName = afterData.lastUpdatedByName || "Someone";

    for (const uid of targets) {
      const userDoc = await admin.firestore().collection("users").doc(uid).get();
      if (!userDoc.exists) continue;

      const fcmTokens = userDoc.data().fcmTokens || [];
      if (fcmTokens.length === 0) continue;

      const messagePayload = {
        tokens: fcmTokens,
        notification: {
          title: "Added to a group! 🎉",
          body: `${senderName} added you to "${groupName}"`,
        },
        data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          type: "group_invite",
          groupId: groupId,
        },
      };

      try {
        const response = await admin.messaging().sendEachForMulticast(messagePayload);
        // Clean up invalid or expired tokens
        if (response.failureCount > 0) {
          const invalidTokens = [];
          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              invalidTokens.push(fcmTokens[idx]);
            }
          });
          if (invalidTokens.length > 0) {
            await admin.firestore().collection("users").doc(uid).update({
              fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
            });
          }
        }
      } catch (err) {
        console.error(`Error sending push notification to UID ${uid}:`, err);
      }
    }

    return null;
  });

function requireAuth(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in is required.");
  }
  return context.auth.uid;
}

function memberUidForName(group, name) {
  const identities = Array.isArray(group.memberIdentities) ? group.memberIdentities : [];
  const matches = identities.filter((identity) => identity.name === name && identity.uid);
  return matches.length === 1 ? matches[0].uid : null;
}

function memberNameForUid(group, uid) {
  const identities = Array.isArray(group.memberIdentities) ? group.memberIdentities : [];
  const matches = identities.filter((identity) => identity.uid === uid);
  return matches.length === 1 ? matches[0].name : "";
}

function canManageSettlement(group, uid, fromUser) {
  if (group.createdBy && group.createdBy === uid) return true;
  return (group.memberUids || []).includes(uid) && memberUidForName(group, fromUser) === uid;
}

exports.migrateGroupMemberIdentities = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const groupRef = admin.firestore().collection("groups").doc(String(data.groupId || ""));
  if (!data.groupId) throw new functions.https.HttpsError("invalid-argument", "A group ID is required.");
  return admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(groupRef);
    if (!snapshot.exists) throw new functions.https.HttpsError("not-found", "Group not found.");
    const group = snapshot.data();
    if (group.createdBy !== uid) throw new functions.https.HttpsError("permission-denied", "Only the group creator may migrate member identities.");
    if (Array.isArray(group.memberIdentities) && group.memberIdentities.length) return { migrated: true };
    const members = Array.isArray(group.members) ? group.members : [];
    const uids = Array.isArray(group.memberUids) ? group.memberUids : [];
    if (!members.length || members.length !== uids.length || members.some((name) => !name) || uids.some((memberUid) => !memberUid) || new Set(members).size !== members.length || new Set(uids).size !== uids.length) {
      return { migrated: false };
    }
    transaction.update(groupRef, { memberIdentities: members.map((name, index) => ({ name, uid: uids[index] })) });
    return { migrated: true };
  });
});

exports.addGroupMember = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const groupId = String(data.groupId || "");
  const displayName = String(data.displayName || "").trim();
  const memberUid = String(data.uid || "").trim();
  if (!groupId || !displayName) throw new functions.https.HttpsError("invalid-argument", "A group and member name are required.");
  const groupRef = admin.firestore().collection("groups").doc(groupId);
  await admin.firestore().runTransaction(async (transaction) => {
    const groupSnapshot = await transaction.get(groupRef);
    if (!groupSnapshot.exists) throw new functions.https.HttpsError("not-found", "Group not found.");
    const group = groupSnapshot.data();
    if (!(group.memberUids || []).includes(uid) && group.createdBy !== uid) throw new functions.https.HttpsError("permission-denied", "Only a group member may add members.");
    const members = group.members || [];
    if (members.some((name) => String(name).toLowerCase() === displayName.toLowerCase())) throw new functions.https.HttpsError("already-exists", "A member with this name already exists.");
    const updates = { members: admin.firestore.FieldValue.arrayUnion(displayName) };
    if (memberUid) {
      const userSnapshot = await transaction.get(admin.firestore().collection("users").doc(memberUid));
      if (!userSnapshot.exists) throw new functions.https.HttpsError("not-found", "Registered member not found.");
      const user = userSnapshot.data();
      const verifiedName = String(user.displayName || user.fullName || user.username || "").trim();
      if (!verifiedName || verifiedName !== displayName) throw new functions.https.HttpsError("invalid-argument", "The member identity does not match the selected account.");
      if ((group.memberUids || []).includes(memberUid)) throw new functions.https.HttpsError("already-exists", "This user is already a group member.");
      updates.memberUids = admin.firestore.FieldValue.arrayUnion(memberUid);
      updates.memberIdentities = admin.firestore.FieldValue.arrayUnion({ name: displayName, uid: memberUid });
      if (data.email) updates.memberEmails = admin.firestore.FieldValue.arrayUnion(String(data.email).toLowerCase());
      if (data.username) updates.memberUsernames = admin.firestore.FieldValue.arrayUnion(String(data.username).toLowerCase());
    }
    transaction.update(groupRef, updates);
  });
  return { success: true };
});

function computePendingSettlements(group) {
  const balances = new Map();
  for (const member of (group.members || [])) balances.set(member, 0);
  for (const expense of (group.expenses || [])) {
    balances.set(expense.paidBy, (balances.get(expense.paidBy) || 0) + Number(expense.amount || 0));
    if (expense.splitType === "custom") {
      for (const [member, amount] of Object.entries(expense.customSplits || {})) {
        balances.set(member, (balances.get(member) || 0) - Number(amount || 0));
      }
    } else {
      const splitBetween = expense.splitBetween || [];
      const share = splitBetween.length ? Number(expense.amount || 0) / splitBetween.length : 0;
      for (const member of splitBetween) balances.set(member, (balances.get(member) || 0) - share);
    }
  }
  for (const settlement of (group.recordedSettlements || [])) {
    if (settlement.isSettled) {
      balances.set(settlement.fromUser, (balances.get(settlement.fromUser) || 0) + Number(settlement.amount || 0));
      balances.set(settlement.toUser, (balances.get(settlement.toUser) || 0) - Number(settlement.amount || 0));
    }
  }
  const debtors = [];
  const creditors = [];
  for (const [member, balance] of balances.entries()) {
    if (balance > 0.01) creditors.push({ member, amount: balance });
    else if (balance < -0.01) debtors.push({ member, amount: -balance });
  }
  const pending = [];
  let i = 0;
  let j = 0;
  while (i < debtors.length && j < creditors.length) {
    const amount = Math.min(debtors[i].amount, creditors[j].amount);
    pending.push({ fromUser: debtors[i].member, toUser: creditors[j].member, amount });
    debtors[i].amount -= amount;
    creditors[j].amount -= amount;
    if (debtors[i].amount <= 0.01) i++;
    if (creditors[j].amount <= 0.01) j++;
  }
  return pending;
}

exports.manageSettlement = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const groupId = String(data.groupId || "");
  const action = String(data.action || "");
  if (!groupId || !["settle", "undo"].includes(action)) {
    throw new functions.https.HttpsError("invalid-argument", "A group and valid settlement action are required.");
  }
  const groupRef = admin.firestore().collection("groups").doc(groupId);
  const activityRef = groupRef.collection("activities").doc();
  await admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(groupRef);
    if (!snapshot.exists) throw new functions.https.HttpsError("not-found", "Group not found.");
    const group = snapshot.data();
    const fromUser = String(data.fromUser || "");
    const toUser = String(data.toUser || "");
    const amount = Number(data.amount);
    if (!fromUser || !toUser || !Number.isFinite(amount) || amount <= 0) {
      throw new functions.https.HttpsError("invalid-argument", "Invalid settlement details.");
    }
    if (!canManageSettlement(group, uid, fromUser)) {
      throw new functions.https.HttpsError("permission-denied", "Only the settlement payer or group creator may perform this action.");
    }
    const recorded = Array.isArray(group.recordedSettlements) ? [...group.recordedSettlements] : [];
    let historyType;
    if (action === "settle") {
      const pending = computePendingSettlements(group).some((item) =>
        item.fromUser === fromUser && item.toUser === toUser && Math.abs(item.amount - amount) < 0.011);
      if (!pending) throw new functions.https.HttpsError("failed-precondition", "This settlement is no longer pending.");
      recorded.push({
        id: activityRef.id,
        fromUser,
        toUser,
        amount,
        isSettled: true,
        settledAt: new Date().toISOString(),
      });
      historyType = "settlement_recorded";
    } else {
      const matches = recorded.map((settlement, index) => ({ settlement, index })).filter(({ settlement }) =>
        settlement.fromUser === fromUser && settlement.toUser === toUser &&
        Number(settlement.amount) === amount && settlement.isSettled &&
        (!settlement.id || settlement.id === data.settlementId));
      if (matches.length !== 1) throw new functions.https.HttpsError("failed-precondition", "Settled record not found or is ambiguous.");
      const index = matches[0].index;
      recorded.splice(index, 1);
      historyType = "settlement_undone";
    }
    transaction.update(groupRef, {
      recordedSettlements: recorded,
      lastUpdatedBy: uid,
    });
    transaction.set(activityRef, {
      id: activityRef.id,
      groupId,
      type: historyType,
      performedByUid: uid,
      performedByName: memberNameForUid(group, uid),
      message: action === "settle"
        ? `Settlement: ${fromUser} paid ₹${amount.toFixed(0)} to ${toUser}`
        : `Undid settlement: restored balance of ₹${amount.toFixed(0)} between ${fromUser} and ${toUser}`,
      metadata: { fromUser, toUser, amount },
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return { success: true };
});

exports.deleteGroup = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const groupId = String(data.groupId || "");
  if (!groupId) throw new functions.https.HttpsError("invalid-argument", "A group ID is required.");
  const groupRef = admin.firestore().collection("groups").doc(groupId);
  const snapshot = await groupRef.get();
  if (!snapshot.exists) throw new functions.https.HttpsError("not-found", "Group not found.");
  if (!snapshot.get("createdBy") || snapshot.get("createdBy") !== uid) {
    throw new functions.https.HttpsError("permission-denied", "Only the group creator may delete this group.");
  }
  // Expenses and settlements are embedded in the group document; activities are
  // its only group-owned subcollection. recursiveDelete removes those records too.
  await admin.firestore().recursiveDelete(groupRef);
  return { success: true };
});
