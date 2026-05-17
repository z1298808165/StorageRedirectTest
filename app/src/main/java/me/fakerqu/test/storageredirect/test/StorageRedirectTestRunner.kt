package me.fakerqu.test.storageredirect.test

import android.content.Context
import android.net.Uri
import android.util.Log
import me.fakerqu.media_store_api.IMediaStoreApi
import java.io.File

class StorageRedirectTestRunner(private val context: Context) {

    fun run(testCase: TestCase, args: TestCaseArgs = TestCaseArgs()): List<TestResult> {
        val results = if (testCase == TestCase.ALL_EXCEPT_DELETE) {
            runAllExceptDelete(args)
        } else {
            listOf(testCase.run(context, args))
        }
        logSummary(results)
        return results
    }

    /**
     * ALL 模式：不依赖外部 URI/路径，先 create 再将其作为参数传给 read/write/thumbnail。
     */
    private fun runAllExceptDelete(overrides: TestCaseArgs): List<TestResult> {
        val results = mutableListOf<TestResult>()
        val mediaStore = MediaStoreTestCases(context)
        val fileCases = FileTestCases(context)

        TestCase.executableCases
            .filter { it.id.startsWith("mediastore_query") }
            .forEach { results += it.run(context, overrides) }

        val mediaTypes = listOf(
            IMediaStoreApi.MediaType.IMAGE to listOf(
                TestCase.MEDIASTORE_CREATE_IMAGE,
                TestCase.MEDIASTORE_READ_IMAGE,
                TestCase.MEDIASTORE_WRITE_IMAGE,
                TestCase.MEDIASTORE_THUMBNAIL_IMAGE,
            ),
            IMediaStoreApi.MediaType.VIDEO to listOf(
                TestCase.MEDIASTORE_CREATE_VIDEO,
                TestCase.MEDIASTORE_READ_VIDEO,
                TestCase.MEDIASTORE_WRITE_VIDEO,
                TestCase.MEDIASTORE_THUMBNAIL_VIDEO,
            ),
            IMediaStoreApi.MediaType.AUDIO to listOf(
                TestCase.MEDIASTORE_CREATE_AUDIO,
                TestCase.MEDIASTORE_READ_AUDIO,
                TestCase.MEDIASTORE_WRITE_AUDIO,
            ),
            IMediaStoreApi.MediaType.FILE to listOf(
                TestCase.MEDIASTORE_CREATE_FILE,
                TestCase.MEDIASTORE_READ_FILE,
                TestCase.MEDIASTORE_WRITE_FILE,
            ),
            IMediaStoreApi.MediaType.DOWNLOAD to listOf(
                TestCase.MEDIASTORE_CREATE_DOWNLOAD,
                TestCase.MEDIASTORE_READ_DOWNLOAD,
                TestCase.MEDIASTORE_WRITE_DOWNLOAD,
            ),
        )

        for ((mediaType, chain) in mediaTypes) {
            val createCase = chain.first()
            val createResult = createCase.run(context, overrides)
            results += createResult
            val uri = createResult.metadata["uri"]?.let(Uri::parse)
            if (uri == null) {
                chain.drop(1).forEach { skipped ->
                    results += skipped.fail("skipped: create did not return uri")
                }
                continue
            }
            val initial = TestFixtures.initialPayload(mediaType)
            val updated = TestFixtures.updatedPayload(mediaType)
            chain.drop(1).forEach { case ->
                val caseArgs = when {
                    case.id.contains("_read_") -> TestCaseArgs(
                        mediaUri = uri,
                        expectedPayload = initial,
                    )

                    case.id.contains("_write_") -> TestCaseArgs(
                        mediaUri = uri,
                        payload = updated,
                        expectedPayload = updated,
                    )

                    case.id.contains("_thumbnail_") -> TestCaseArgs(mediaUri = uri)
                    case.id.contains("_delete_") -> TestCaseArgs(mediaUri = uri)
                    else -> TestCaseArgs(mediaUri = uri)
                }
                results += case.run(context, caseArgs)
            }
        }

        val fileDir = fileCases.prepareBootstrapDir("all_file_list")
        File(fileDir, "a.txt").writeText("a")
        File(fileDir, "nested/b.txt").apply {
            parentFile?.mkdirs()
            writeText("b")
        }
        results += TestCase.FILE_LIST_DIR.run(
            context,
            TestCaseArgs(fileDir = fileDir.absolutePath),
        )

        val filePath = File(fileCases.prepareBootstrapDir("all_file_rw"), "target.txt").absolutePath
        val filePayload = TestFixtures.filePayload("all")
        results += TestCase.FILE_CREATE.run(
            context,
            TestCaseArgs(filePath = filePath, payload = filePayload)
        )
        results += TestCase.FILE_READ.run(
            context,
            TestCaseArgs(filePath = filePath, expectedPayload = filePayload),
        )
        results += TestCase.FILE_WRITE.run(
            context,
            TestCaseArgs(
                filePath = filePath,
                payload = TestFixtures.filePayload("all-updated"),
                expectedPayload = TestFixtures.filePayload("all-updated"),
            ),
        )
        results += TestCase.FILE_DELETE.run(context, TestCaseArgs(filePath = filePath))

        return results
    }

    private fun logSummary(results: List<TestResult>) {
        val passed = results.count { it.passed }
        val failed = results.size - passed
        Log.i(TAG, "summary: total=${results.size} passed=$passed failed=$failed")
        results.forEach { result ->
            if (result.passed) {
                Log.i(TAG, result.toLogLine())
            } else {
                Log.w(TAG, result.toLogLine())
            }
        }
    }

    companion object {
        private const val TAG = "StorageRedirectTest"
    }
}
