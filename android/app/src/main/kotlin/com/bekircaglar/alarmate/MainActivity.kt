package com.bekircaglar.alarmate

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.gdelataillade.alarm.services.AlarmRingingLiveData
import androidx.lifecycle.Observer

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.bekircaglar.alarmate/app_retain"
    private val TAG = "MainActivity"

    private val ringingObserver = Observer<Boolean> { isRinging ->
        if (isRinging) {
            Log.d(TAG, "AlarmRingingLiveData: alarm is ringing — waking screen")
            wakeUpScreen()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setupWakeLock()

        // AlarmRingingLiveData'yı observe et
        // Bu, alarm çalarken (app ön plandayken bile) ekranı açık tutar
        AlarmRingingLiveData.instance.observe(this, ringingObserver)

        // Eğer alarm ile açıldıysa, ekstra wake-up yap
        if (intent?.getBooleanExtra("from_alarm", false) == true) {
            Log.d(TAG, "Launched from alarm — performing extra wake-up")
            wakeUpScreen()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setupWakeLock()

        if (intent.getBooleanExtra("from_alarm", false)) {
            Log.d(TAG, "onNewIntent from alarm — performing extra wake-up")
            wakeUpScreen()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "bringToFront") {
                bringToFront()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun setupWakeLock() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                or WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.addFlags(WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON)
    }

    private fun wakeUpScreen() {
        // Ekranı zorla aç
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!powerManager.isInteractive) {
            @Suppress("DEPRECATION")
            val wakeLock = powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "alarmate:AlarmScreenWake"
            )
            wakeLock.acquire(10 * 1000L) // 10 saniye
        }

        // Kilit ekranını kaldır
        setupWakeLock()
    }

    private fun bringToFront() {
        val intent = Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        startActivity(intent)
    }
}
