package me.fakerqu.test.storageredirect.test

import android.content.Intent
import android.net.Uri

/**
 * 测试用例运行时参数。MediaStore 操作用 [mediaUri]；File 操作用 [filePath] / [fileDir]。
 */
data class TestCaseArgs(
    val mediaUri: Uri? = null,
    val filePath: String? = null,
    val fileDir: String? = null,
    val fileName: String? = null,
    val payload: ByteArray? = null,
    val expectedPayload: ByteArray? = null,
) {
    fun payloadOr(default: ByteArray): ByteArray = payload ?: default

    fun expectedOr(default: ByteArray): ByteArray = expectedPayload ?: default

    companion object {
        const val EXTRA_MEDIA_URI = "media_uri"
        const val EXTRA_FILE_PATH = "file_path"
        const val EXTRA_FILE_DIR = "file_dir"
        const val EXTRA_FILE_NAME = "file_name"
        const val EXTRA_PAYLOAD = "payload"
        const val EXTRA_EXPECTED_PAYLOAD = "expected_payload"

        fun fromIntent(intent: Intent?): TestCaseArgs {
            if (intent == null) return TestCaseArgs()
            return TestCaseArgs(
                mediaUri = intent.getStringExtra(EXTRA_MEDIA_URI)?.let(Uri::parse),
                filePath = intent.getStringExtra(EXTRA_FILE_PATH),
                fileDir = intent.getStringExtra(EXTRA_FILE_DIR),
                fileName = intent.getStringExtra(EXTRA_FILE_NAME),
                payload = intent.getStringExtra(EXTRA_PAYLOAD)?.toByteArray(Charsets.UTF_8),
                expectedPayload = intent.getStringExtra(EXTRA_EXPECTED_PAYLOAD)
                    ?.toByteArray(Charsets.UTF_8),
            )
        }

        fun copyExtras(from: Intent?, to: Intent) {
            if (from == null) return
            listOf(
                EXTRA_MEDIA_URI,
                EXTRA_FILE_PATH,
                EXTRA_FILE_DIR,
                EXTRA_FILE_NAME,
                EXTRA_PAYLOAD,
                EXTRA_EXPECTED_PAYLOAD,
                me.fakerqu.test.storageredirect.receiver.TestCaseReceiver.EXTRA_TEST_CASE,
            ).forEach { key ->
                from.getStringExtra(key)?.let { to.putExtra(key, it) }
            }
        }
    }
}
