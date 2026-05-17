package me.fakerqu.test.storageredirect

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import me.fakerqu.test.storageredirect.receiver.TestCaseReceiver
import me.fakerqu.test.storageredirect.test.StorageRedirectTestRunner
import me.fakerqu.test.storageredirect.test.TestCase
import me.fakerqu.test.storageredirect.test.TestCaseArgs
import java.io.File
import java.util.concurrent.Executors

class TestService : Service() {

    private val executor = Executors.newSingleThreadExecutor()
    private val receiver = TestCaseReceiver()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        registerReceiver(receiver, IntentFilter(TestCaseReceiver.ACTION_TEST_CASE))
        super.onCreate()
    }


    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        promoteToForeground()

        if (intent?.action == TestCaseReceiver.ACTION_TEST_CASE) {
            val testCase = TestCase.fromId(intent?.getStringExtra(TestCaseReceiver.EXTRA_TEST_CASE))
            val args = TestCaseArgs.fromIntent(intent)
            executor.execute {
                try {
                    val results = StorageRedirectTestRunner(applicationContext).run(testCase, args)
                    val failed = results.count { !it.passed }
                    val resultDir = getExternalFilesDir("test_case_result")
                    resultDir?.let {
                        it.mkdirs()
                        val resultFile = File(it, "result_${System.currentTimeMillis()}.txt")
                        resultFile.bufferedWriter().use { writer ->
                            results.forEach { result ->
                                writer.write(result.toLogLine())
                                writer.write("\n")
                            }
                            writer.flush()
                        }
                    }

                    if (failed > 0) {
                        android.util.Log.w(
                            "StorageRedirectTest",
                            "completed with $failed failure(s) out of ${results.size}"
                        )
                    }
                } finally {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        stopForeground(STOP_FOREGROUND_REMOVE)
                    } else {
                        @Suppress("DEPRECATION")
                        stopForeground(true)
                    }
                    stopSelfResult(startId)
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        unregisterReceiver(receiver)
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun promoteToForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                createNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
            )
        } else {
            startForeground(NOTIFICATION_ID, createNotification())
        }
    }

    private fun createNotification(): Notification {
        ensureNotificationChannel()
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.test_service_notification_title))
            .setContentText(getString(R.string.test_service_notification_text))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .build()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.test_service_channel_name),
            NotificationManager.IMPORTANCE_LOW
        )
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "storage_redirect_test"
        private const val NOTIFICATION_ID = 10_000

        fun createIntent(context: Context, broadcast: Intent): Intent =
            Intent(context, TestService::class.java).apply {
                action = TestCaseReceiver.ACTION_TEST_CASE
                TestCaseArgs.copyExtras(broadcast, this)
            }
    }
}
