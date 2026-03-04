const { onValueCreated, onValueWritten } = require("firebase-functions/v2/database");
const { initializeApp } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

/**
 * pendingUpdates/{uid}/{alarmId} üzerinde bir işlem yapıldığında tetiklenir.
 */
exports.sendAlarmUpdateNotification = onValueWritten(
    {
        ref: "/pendingUpdates/{uid}/{alarmId}",
        region: "europe-west1",
    },
    async (event) => {
        if (!event.data.after.exists()) return null;

        const uid = event.params.uid;
        const alarmId = event.params.alarmId;
        const updateData = event.data.after.val();

        console.log(`Alarm güncelleme tetiklendi: uid=${uid}, alarmId=${alarmId}`, updateData);

        const db = getDatabase();

        // Temizlik yapalım
        await db.ref(`pendingUpdates/${uid}/${alarmId}`).remove();

        const tokenSnap = await db.ref(`users/${uid}/fcmToken`).get();

        if (!tokenSnap.exists()) {
            console.log(`Kullanıcı ${uid} için FCM token bulunamadı.`);
            return null;
        }

        const fcmToken = tokenSnap.val();
        const updatedBy = updateData.updatedBy || "BİRİ";
        const groupName = updateData.groupName || "BİR GRUP";
        const oldTime = updateData.oldTime || "";
        const newTime = updateData.newTime || "";

        const message = {
            token: fcmToken,
            data: {
                type: "alarm_update",
                alarmId: alarmId,
                updatedBy: updatedBy,
                groupName: groupName,
                oldTime: oldTime,
                newTime: newTime,
                title: "⏰ ALARM GÜNCELLENDİ!",
                body: `${updatedBy}, ${groupName} alarmını değiştirdi: ${oldTime} → ${newTime}`,
            },
            android: {
                priority: "high",
            },
            apns: {
                payload: {
                    aps: {
                        contentAvailable: true,
                    },
                },
            },
        };

        try {
            const response = await getMessaging().send(message);
            console.log("FCM Update Başarılı:", response);
            return response;
        } catch (error) {
            console.error("FCM Update Hatası:", error);
            if (error.code === 'messaging/registration-token-not-registered') {
                await db.ref(`users/${uid}/fcmToken`).remove();
            }
            return null;
        }
    }
);

/**
 * nudges/{uid}/{alarmId} üzerinde bir işlem yapıldığında tetiklenir.
 */
exports.sendAlarmNudgeNotification = onValueWritten(
    {
        ref: "/nudges/{uid}/{alarmId}",
        region: "europe-west1",
    },
    async (event) => {
        if (!event.data.after.exists()) return null;

        const uid = event.params.uid;
        const alarmId = event.params.alarmId;
        const nudgeData = event.data.after.val();

        console.log(`Dürtme tetiklendi: uid=${uid}, alarmId=${alarmId}`, nudgeData);

        const db = getDatabase();
        await db.ref(`nudges/${uid}/${alarmId}`).remove();

        const tokenSnap = await db.ref(`users/${uid}/fcmToken`).get();

        if (!tokenSnap.exists()) {
            console.warn(`Kullanıcı ${uid} için FCM token bulunamadı!`);
            return null;
        }

        const fcmToken = tokenSnap.val();
        const nudgedBy = nudgeData.nudgedBy || "Yönetici";
        const groupName = nudgeData.groupName || "Oda";

        console.log(`Dürtme gönderiliyor. Hedef: ${fcmToken.substring(0, 10)}...`);

        const message = {
            token: fcmToken,
            data: {
                type: "alarm_nudge",
                alarmId: alarmId,
                nudgedBy: nudgedBy,
                groupName: groupName,
                title: "💨 ALARMINI AÇ!",
                body: `${nudgedBy}, "${groupName}" odasındaki alarmını açman için seni dürttü!`,
            },
            android: {
                priority: "high",
            },
            apns: {
                payload: {
                    aps: {
                        contentAvailable: true,
                    },
                },
            },
        };

        try {
            const response = await getMessaging().send(message);
            console.log("FCM Nudge Başarılı:", response);
            return response;
        } catch (error) {
            console.error("FCM Nudge Hatası:", error);
            if (error.code === 'messaging/registration-token-not-registered') {
                await db.ref(`users/${uid}/fcmToken`).remove();
            }
            return null;
        }
    }
);
