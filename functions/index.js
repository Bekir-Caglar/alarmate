const { onValueCreated } = require("firebase-functions/v2/database");
const { initializeApp } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

/**
 * pendingUpdates/{uid}/{alarmId} yaratıldığında tetiklenir.
 * İlgili kullanıcının FCM token'ını alır ve push notification gönderir.
 */
exports.sendAlarmUpdateNotification = onValueCreated(
    {
        ref: "/pendingUpdates/{uid}/{alarmId}",
        region: "europe-west1",
    },
    async (event) => {
        const uid = event.params.uid;
        const alarmId = event.params.alarmId;
        const updateData = event.data.val();

        console.log(`Yeni alarm güncellemesi: uid=${uid}, alarmId=${alarmId}`, updateData);

        // Kullanıcının FCM token'ını al
        const db = getDatabase();
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

        // Push notification gönder
        const message = {
            token: fcmToken,
            notification: {
                title: "⏰ ALARM GÜNCELLENDİ!",
                body: `${updatedBy}, ${groupName} alarmını değiştirdi: ${oldTime} → ${newTime}`,
            },
            data: {
                type: "alarm_update",
                alarmId: alarmId,
                updatedBy: updatedBy,
                groupName: groupName,
                oldTime: oldTime,
                newTime: newTime,
            },
            android: {
                priority: "high",
                notification: {
                    channelId: "alarm_updates",
                    priority: "high",
                    defaultSound: true,
                    defaultVibrateTimings: true,
                },
            },
            apns: {
                payload: {
                    aps: {
                        alert: {
                            title: "⏰ ALARM GÜNCELLENDİ!",
                            body: `${updatedBy}, ${groupName} alarmını değiştirdi: ${oldTime} → ${newTime}`,
                        },
                        sound: "default",
                        badge: 1,
                    },
                },
            },
        };

        try {
            const response = await getMessaging().send(message);
            console.log("Bildirim gönderildi:", response);
            return response;
        } catch (error) {
            console.error("Bildirim gönderilemedi:", error);
            // Token geçersizse temizle
            if (
                error.code === "messaging/registration-token-not-registered" ||
                error.code === "messaging/invalid-registration-token"
            ) {
                console.log(`Geçersiz token temizleniyor: uid=${uid}`);
                await db.ref(`users/${uid}/fcmToken`).remove();
            }
            return null;
        }
    }
);
