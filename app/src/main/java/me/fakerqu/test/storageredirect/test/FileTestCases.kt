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
        val listed = dir.listFiles()?.toList().orEmpty()
        val entries = listed
            .map { file -> file.name.ifBlank { "." } }
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
        if (!created.existsEventually()) {
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

    fun writeDenied(args: TestCaseArgs): TestResult = TestCase.FILE_WRITE_DENIED.measure {
        val targetPath = args.requireFilePath(TestCase.FILE_WRITE_DENIED)
            ?: return@measure args.missingPathResult(TestCase.FILE_WRITE_DENIED)
        val target = File(targetPath)
        val parent = target.parentFile
        if (parent != null && !parent.isDirectory) {
            return@measure TestCase.FILE_WRITE_DENIED.fail(
                message = "parent directory does not exist before write",
                metadata = pathMetadata(targetPath),
            )
        }
        val payload = args.payloadOr(TestFixtures.filePayload("write-denied"))
        try {
            api.writeFile(targetPath).use {
                it.write(payload)
                it.flush()
            }
        } catch (e: Exception) {
            return@measure TestCase.FILE_WRITE_DENIED.pass(
                message = "write denied as expected",
                metadata = pathMetadata(targetPath) + exceptionMetadata(e),
            )
        }
        TestCase.FILE_WRITE_DENIED.fail(
            message = "write unexpectedly succeeded",
            metadata = pathMetadata(targetPath),
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

    fun deleteDenied(args: TestCaseArgs): TestResult = TestCase.FILE_DELETE_DENIED.measure {
        val targetPath = args.requireFilePath(TestCase.FILE_DELETE_DENIED)
            ?: return@measure args.missingPathResult(TestCase.FILE_DELETE_DENIED)
        val target = File(targetPath)
        if (!target.exists()) {
            return@measure TestCase.FILE_DELETE_DENIED.fail(
                message = "path does not exist before delete",
                metadata = pathMetadata(targetPath),
            )
        }
        try {
            val deleted = api.deleteFile(targetPath)
            if (deleted || !target.exists()) {
                return@measure TestCase.FILE_DELETE_DENIED.fail(
                    message = "delete unexpectedly succeeded",
                    metadata = pathMetadata(targetPath),
                )
            }
        } catch (e: Exception) {
            return@measure TestCase.FILE_DELETE_DENIED.pass(
                message = "delete denied as expected",
                metadata = pathMetadata(targetPath) + exceptionMetadata(e),
            )
        }
        TestCase.FILE_DELETE_DENIED.pass(
            message = "delete denied as expected",
            metadata = pathMetadata(targetPath),
        )
    }

    fun mkdir(args: TestCaseArgs): TestResult = TestCase.FILE_MKDIR.measure {
        val dirPath = args.requireFileDirOrPath(TestCase.FILE_MKDIR)
            ?: return@measure args.missingDirOrPathResult(TestCase.FILE_MKDIR)
        val dir = File(dirPath)
        val created = api.mkdir(dirPath)
        if (!created || !dir.isDirectory) {
            return@measure TestCase.FILE_MKDIR.fail(
                message = "mkdir failed",
                metadata = pathMetadata(dirPath),
            )
        }
        TestCase.FILE_MKDIR.pass(
            message = "directory created",
            metadata = pathMetadata(dirPath),
        )
    }

    fun mkdirDenied(args: TestCaseArgs): TestResult = TestCase.FILE_MKDIR_DENIED.measure {
        val dirPath = args.requireFileDirOrPath(TestCase.FILE_MKDIR_DENIED)
            ?: return@measure args.missingDirOrPathResult(TestCase.FILE_MKDIR_DENIED)
        val dir = File(dirPath)
        val parent = dir.parentFile
        if (parent != null && !parent.isDirectory) {
            return@measure TestCase.FILE_MKDIR_DENIED.fail(
                message = "parent directory does not exist before mkdir",
                metadata = pathMetadata(dirPath),
            )
        }
        if (dir.exists()) {
            return@measure TestCase.FILE_MKDIR_DENIED.fail(
                message = "directory already exists before mkdir",
                metadata = pathMetadata(dirPath),
            )
        }
        try {
            val created = api.mkdir(dirPath)
            if (created || dir.exists()) {
                return@measure TestCase.FILE_MKDIR_DENIED.fail(
                    message = "mkdir unexpectedly succeeded",
                    metadata = pathMetadata(dirPath),
                )
            }
        } catch (e: Exception) {
            return@measure TestCase.FILE_MKDIR_DENIED.pass(
                message = "mkdir denied as expected",
                metadata = pathMetadata(dirPath) + exceptionMetadata(e),
            )
        }
        TestCase.FILE_MKDIR_DENIED.pass(
            message = "mkdir denied as expected",
            metadata = pathMetadata(dirPath),
        )
    }

    fun rename(args: TestCaseArgs): TestResult = TestCase.FILE_RENAME.measure {
        val fromPath = args.requireFilePath(TestCase.FILE_RENAME)
            ?: return@measure args.missingPathResult(TestCase.FILE_RENAME)
        val toPath = args.requireTargetFilePath(TestCase.FILE_RENAME)
            ?: return@measure args.missingTargetPathResult(TestCase.FILE_RENAME)
        val source = File(fromPath)
        val target = File(toPath)
        if (!source.exists()) {
            return@measure TestCase.FILE_RENAME.fail(
                message = "source does not exist",
                metadata = renameMetadata(fromPath, toPath),
            )
        }
        target.parentFile?.mkdirs()
        if (target.exists()) target.deleteRecursively()
        val renamed = api.renameFile(fromPath, toPath)
        if (!renamed || source.exists() || !target.exists()) {
            return@measure TestCase.FILE_RENAME.fail(
                message = "rename failed",
                metadata = renameMetadata(fromPath, toPath),
            )
        }
        TestCase.FILE_RENAME.pass(
            message = "rename succeeded",
            metadata = renameMetadata(fromPath, toPath),
        )
    }

    fun renameDenied(args: TestCaseArgs): TestResult = TestCase.FILE_RENAME_DENIED.measure {
        val fromPath = args.requireFilePath(TestCase.FILE_RENAME_DENIED)
            ?: return@measure args.missingPathResult(TestCase.FILE_RENAME_DENIED)
        val toPath = args.requireTargetFilePath(TestCase.FILE_RENAME_DENIED)
            ?: return@measure args.missingTargetPathResult(TestCase.FILE_RENAME_DENIED)
        val source = File(fromPath)
        val target = File(toPath)
        if (!source.exists()) {
            return@measure TestCase.FILE_RENAME_DENIED.fail(
                message = "source does not exist before rename",
                metadata = renameMetadata(fromPath, toPath),
            )
        }
        val targetParent = target.parentFile
        if (targetParent != null && !targetParent.isDirectory) {
            return@measure TestCase.FILE_RENAME_DENIED.fail(
                message = "target parent directory does not exist before rename",
                metadata = renameMetadata(fromPath, toPath),
            )
        }
        if (target.exists()) {
            return@measure TestCase.FILE_RENAME_DENIED.fail(
                message = "target already exists before rename",
                metadata = renameMetadata(fromPath, toPath),
            )
        }
        try {
            val renamed = api.renameFile(fromPath, toPath)
            if (renamed || !source.exists() || target.exists()) {
                return@measure TestCase.FILE_RENAME_DENIED.fail(
                    message = "rename unexpectedly succeeded",
                    metadata = renameMetadata(fromPath, toPath),
                )
            }
        } catch (e: Exception) {
            return@measure TestCase.FILE_RENAME_DENIED.pass(
                message = "rename denied as expected",
                metadata = renameMetadata(fromPath, toPath) + exceptionMetadata(e),
            )
        }
        TestCase.FILE_RENAME_DENIED.pass(
            message = "rename denied as expected",
            metadata = renameMetadata(fromPath, toPath),
        )
    }

    fun prepareBootstrapDir(caseId: String): File {
        val dir = File(defaultRoot, caseId)
        if (dir.exists()) dir.deleteRecursively()
        dir.mkdirs()
        return dir
    }

    private fun pathMetadata(path: String): Map<String, String> = mapOf("path" to path)

    private fun renameMetadata(fromPath: String, toPath: String): Map<String, String> =
        mapOf("from" to fromPath, "to" to toPath)

    private fun exceptionMetadata(e: Exception): Map<String, String> =
        mapOf("exception" to e.javaClass.simpleName, "error" to (e.message ?: ""))

    private fun File.existsEventually(): Boolean {
        repeat(EXISTS_RETRY_COUNT) { index ->
            if (exists()) return true
            if (index < EXISTS_RETRY_COUNT - 1) {
                Thread.sleep(EXISTS_RETRY_DELAY_MS)
            }
        }
        return exists()
    }

    companion object {
        private const val MAX_LISTED_ENTRIES = 40
        private const val EXISTS_RETRY_COUNT = 10
        private const val EXISTS_RETRY_DELAY_MS = 100L
    }
}

private fun TestCaseArgs.requireFilePath(testCase: TestCase): String? = filePath

private fun TestCaseArgs.requireTargetFilePath(testCase: TestCase): String? = targetFilePath

private fun TestCaseArgs.requireFileDirOrPath(testCase: TestCase): String? = fileDir ?: filePath

private fun TestCaseArgs.missingPathResult(testCase: TestCase): TestResult =
    testCase.fail(
        message = "missing required parameter: ${TestCaseArgs.EXTRA_FILE_PATH}",
        metadata = mapOf("hint" to "pass absolute path via --es ${TestCaseArgs.EXTRA_FILE_PATH}"),
    )

private fun TestCaseArgs.missingTargetPathResult(testCase: TestCase): TestResult =
    testCase.fail(
        message = "missing required parameter: ${TestCaseArgs.EXTRA_TARGET_FILE_PATH}",
        metadata = mapOf("hint" to "pass target path via --es ${TestCaseArgs.EXTRA_TARGET_FILE_PATH}"),
    )

private fun TestCaseArgs.missingDirOrPathResult(testCase: TestCase): TestResult =
    testCase.fail(
        message = "missing required parameter: ${TestCaseArgs.EXTRA_FILE_DIR} or ${TestCaseArgs.EXTRA_FILE_PATH}",
        metadata = mapOf("hint" to "pass directory path via --es ${TestCaseArgs.EXTRA_FILE_DIR}"),
    )
