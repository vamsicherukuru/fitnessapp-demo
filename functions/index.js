/* eslint-disable */
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

exports.sendMessageNotification = onDocumentCreated(
    "chats/{chatId}/messages/{messageId}",
    async (event) => {
      if (!event.data) return;
      const message = event.data.data();

      const receiverId = message.receiverId;
      const text = message.text || "You received a new message!";

      const userDoc = await db.collection("users").doc(receiverId).get();
      const userData = userDoc.data();

      if (!userData || !userData.fcmTokens || !Array.isArray(userData.fcmTokens)) return;
      const fcmTokens = userData.fcmTokens;

      const payload = {
        notification: {
          title: "New Message",
          body: text,
        },
        data: {
          chatId: event.params.chatId,
          senderId: message.senderId,
        },
      };

      for (const token of fcmTokens) {
        await getMessaging().send({...payload, token});
      }
    },
);
