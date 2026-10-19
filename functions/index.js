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