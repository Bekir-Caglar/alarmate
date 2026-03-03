package com.bekircaglar.alarmate

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.lifecycle.Observer
import com.gdelataillade.alarm.services.AlarmRingingLiveData
import io.flutter.app.FlutterApplication

/**
 * Custom Application class.
 * AlarmRingingLiveData'yı process seviyesinde observeForever ile gözlemler.
 * Alarm çaldığında — app terminated olsa bile — MainActivity'yi zorla başlatır.
 *
 * NEDEN ÇALIŞIYOR:
 * - App terminated iken alarm service başladığında, Android aynı process'te Application'ı da başlatır
 * - Application.onCreate çağrılır → observer kayıt edilir
 * - AlarmService.onStartCommand → AlarmRingingLiveData.update(true) → observer tetiklenir
 * - Observer, MainActivity'yi FLAG_ACTIVITY_NEW_TASK ile başlatır
 * - MainActivity başlayınca Flutter engine init → main() çalışır → ringStream dinlenir
 */
class AlarmateApplication : FlutterApplication() {
    companion object {
        private const val TAG = "AlarmateApplication"
    }

    private val ringingObserver = Observer<Boolean> { isRinging ->
        if (isRinging) {
            Log.d(TAG, "AlarmRingingLiveData = TRUE — forcing MainActivity to front")
            launchMainActivity()
        }
    }

    override fun onCreate() {
        super.onCreate()

        // FCM bildirim kanalı oluştur (Android 8+)
        createNotificationChannels()

        // observeForever — lifecycle owner gerekmez, process yaşadığı sürece aktif kalır
        // Ana thread'te çalışmalı (LiveData requirement)
        Handler(Looper.getMainLooper()).post {
            AlarmRingingLiveData.instance.observeForever(ringingObserver)
        }

        Log.d(TAG, "AlarmateApplication initialized — ringing observer registered")
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "alarm_updates",
                "Alarm Güncellemeleri",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alarm saati veya ayarları değiştirildiğinde bildirim alın"
                enableVibration(true)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun launchMainActivity() {
        // Ekranı zorla uyandır
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        if (!powerManager.isInteractive) {
            @Suppress("DEPRECATION")
            val wakeLock = powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "alarmate:AppWakeLock"
            )
            wakeLock.acquire(10 * 1000L) // 10 saniye
        }

        // MainActivity'yi başlat — app terminated olsa bile çalışır
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            putExtra("from_alarm", true)
        }

        startActivity(intent)
        Log.d(TAG, "MainActivity launch intent sent")
    }
}
