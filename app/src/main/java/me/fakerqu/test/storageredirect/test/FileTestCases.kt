package me.fakerqu.test.storageredirect.test

import android.content.Context
import me.fakerqu.media_store_api.FileApiImpl
import java.io.File

class FileTestCases(private val context: Context) {

    private val api = FileApiImpl()
    private val defaultRoot: File
        get() = File(
            context.getExternalFilesDir("srt_file_tests")
                ?: error("external files dir unavailable"),
            "workspace",
        )

    fun listDir(args: TestCaseArgs): TestResult = TestCase.FILE_LIST_DIR.measure {
        val dirPath = args.fileDir ?: args.filePath
        if (dirPath.isNullOrBlank()) {
            return@measure TestCase.FILE_LIST_DIR.fail(
                message = "missing required parameter: ${TestCaseArgs.EXTRA_FILE_DIR} or ${TestCaseArgs.EXTRA_FILE_PATH}",
            )
        }
        val dir = File(dirPath)
        if (!dir.isDirectory) {
            return@measure TestCase.FILE_LIST_DIR.fail(
                message = "path is not a directory",
                metadata = mapOf("path" to dirPath),
            )
        }
        val listed = api.getDirFilesRecursive(dir.absolutePath)
        val entries = listed
            .map { file -> file.relativeTo(dir).path.ifBlank { "." } }
            .sorted()
            .take(MAX_LISTED_ENTRIES)
        TestCase.FILE_LIST_DIR.pass(
            message = "list completed",
            metadata = mapOf(
                "path" to dirPath,
                "listedCount" to listed.size.toString(),
                "entries" to entries.joinToString("|"),
            ),
        )
    }

    fun create(args: TestCaseArgs): TestResult = TestCase.FILE_CREATE.measure {
        val targetPath = args.requireFilePath(TestCase.FILE_CREATE)
            ?: return@measure args.missingPathResult(TestCase.FILE_CREATE)
        val created = api.createFile(targetPath)
        if (!created.exists()) {
            return@measure TestCase.FILE_CREATE.fail(
                message = "createFile failed",
                metadata = mapOf("path" to targetPath),
            )
        }
        args.payload?.let { payload ->
            created.writeBytes(payload)
        }
        TestCase.FILE_CREATE.pass(
            message = "file created",
            metadata = mapOf("path" to targetPath),
        )
    }

    fun read(args: TestCaseArgs): TestResult = TestCase.FILE_READ.measure {
        val targetPath = args.requireFilePath(TestCase.FILE_READ)
            ?: return@measure args.missingPathResult(TestCase.FILE_READ)
        val target = File(targetPath)
        if (!target.isFile) {
            return@measure TestCase.FILE_READ.fail(
                message = "file does not exist",
                metadata = mapOf("path" to targetPath),
            )
        }
        val readBack = api.readFile(targetPath).use { it.readBytes() }
        val expected = args.expectedPayload
        if (expected != null && !readBack.contentEquals(expected)) {
            return@measure TestCase.FILE_READ.fail(
                message = "read content mismatch",
                metadata = pathMetadata(targetPath),
            )
        }
        TestCase.FILE_READ.pass(
            message = if (expected != null) "read matched expected payload" else "read completed",
            metadata = pathMetadata(targetPath) + mapOf("bytesRead" to readBack.size.toString()),
        )
    }

    fun write(args: TestCaseArgs): TestResult = TestCase.FILE_WRITE.measure {
        val targetPath = args.requireFilePath(TestCase.FILE_WRITE)
            ?: return@measure args.missingPathResult(TestCase.FILE_WRITE)
        val target = File(targetPath)
        if (!target.exists()) {
            api.createFile(targetPath)
        }
        val payload = args.payloadOr(TestFixtures.filePayload("write"))
        api.writeFile(targetPath).use {
            it.write(payload)
            it.flush()
        }
        if (args.expectedPayload != null) {
            val readBack = target.readBytes()
            if (!readBack.contentEquals(args.expectedPayload)) {
                return@measure TestCase.FILE_WRITE.fail(
                    message = "read after write did not match expected_payload",
                    metadata = pathMetadata(targetPath),
                )
            }
        }
        TestCase.FILE_WRITE.pass(
            message = "write succeeded",
            metadata = pathMetadata(targetPath) + mapOf("bytesWritten" to payload.size.toString()),
        )
    }

    fun delete(args: TestCaseArgs): TestResult = TestCase.FILE_DELETE.measure {
        val targetPath = args.requireFilePath(TestCase.FILE_DELETE)
            ?: return@measure args.missingPathResult(TestCase.FILE_DELETE)
        val target = File(targetPath)
        if (!target.exists()) {
            return@measure TestCase.FILE_DELETE.fail(
                message = "path does not exist",
                metadata = pathMetadata(targetPath),
            )
        }
        val deleted = api.deleteFile(targetPath)
        if (!deleted || target.exists()) {
            return@measure TestCase.FILE_DELETE.fail(
                message = "deleteFile failed",
                metadata = pathMetadata(targetPath),
            )
        }
        TestCase.FILE_DELETE.pass(message = "delete succeeded", metadata = pathMetadata(targetPath))
    }

    fun prepareBootstrapDir(caseId: String): File {
        val dir = File(defaultRoot, caseId)
        if (dir.exists()) dir.deleteRecursively()
        dir.mkdirs()
        return dir
    }

    private fun pathMetadata(path: String): Map<String, String> = mapOf("path" to path)

    companion object {
        private const val MAX_LISTED_ENTRIES = 40
    }
}

private fun TestCaseArgs.requireFilePath(testCase: TestCase): String? = filePath

private fun TestCaseArgs.missingPathResult(testCase: TestCase): TestResult =
    testCase.fail(
        message = "missing required parameter: ${TestCaseArgs.EXTRA_FILE_PATH}",
        metadata = mapOf("hint" to "pass absolute path via --es ${TestCaseArgs.EXTRA_FILE_PATH}"),
    )
