package me.fakerqu.test.storageredirect.test

import android.content.Context
import android.net.Uri
import android.util.Size
import me.fakerqu.media_store_api.IMediaStoreApi
import me.fakerqu.media_store_api.MediaStoreApiImpl

class MediaStoreTestCases(context: Context) {

    private val api = MediaStoreApiImpl(context)
    private val volume = IMediaStoreApi.VolumeType.EXTERNAL

    fun queryImage(): TestResult =
        query(TestCase.MEDIASTORE_QUERY_IMAGE, IMediaStoreApi.MediaType.IMAGE)

    fun queryVideo(): TestResult =
        query(TestCase.MEDIASTORE_QUERY_VIDEO, IMediaStoreApi.MediaType.VIDEO)

    fun queryAudio(): TestResult =
        query(TestCase.MEDIASTORE_QUERY_AUDIO, IMediaStoreApi.MediaType.AUDIO)

    fun queryFile(): TestResult =
        query(TestCase.MEDIASTORE_QUERY_FILE, IMediaStoreApi.MediaType.FILE)

    fun queryDownload(): TestResult =
        query(TestCase.MEDIASTORE_QUERY_DOWNLOAD, IMediaStoreApi.MediaType.DOWNLOAD)

    fun createImage(args: TestCaseArgs): TestResult =
        create(TestCase.MEDIASTORE_CREATE_IMAGE, IMediaStoreApi.MediaType.IMAGE, args)

    fun createVideo(args: TestCaseArgs): TestResult =
        create(TestCase.MEDIASTORE_CREATE_VIDEO, IMediaStoreApi.MediaType.VIDEO, args)

    fun createAudio(args: TestCaseArgs): TestResult =
        create(TestCase.MEDIASTORE_CREATE_AUDIO, IMediaStoreApi.MediaType.AUDIO, args)

    fun createFile(args: TestCaseArgs): TestResult =
        create(TestCase.MEDIASTORE_CREATE_FILE, IMediaStoreApi.MediaType.FILE, args)

    fun createDownload(args: TestCaseArgs): TestResult =
        create(TestCase.MEDIASTORE_CREATE_DOWNLOAD, IMediaStoreApi.MediaType.DOWNLOAD, args)

    fun readImage(args: TestCaseArgs): TestResult =
        read(TestCase.MEDIASTORE_READ_IMAGE, IMediaStoreApi.MediaType.IMAGE, args)

    fun readVideo(args: TestCaseArgs): TestResult =
        read(TestCase.MEDIASTORE_READ_VIDEO, IMediaStoreApi.MediaType.VIDEO, args)

    fun readAudio(args: TestCaseArgs): TestResult =
        read(TestCase.MEDIASTORE_READ_AUDIO, IMediaStoreApi.MediaType.AUDIO, args)

    fun readFile(args: TestCaseArgs): TestResult =
        read(TestCase.MEDIASTORE_READ_FILE, IMediaStoreApi.MediaType.FILE, args)

    fun readDownload(args: TestCaseArgs): TestResult =
        read(TestCase.MEDIASTORE_READ_DOWNLOAD, IMediaStoreApi.MediaType.DOWNLOAD, args)

    fun writeImage(args: TestCaseArgs): TestResult =
        write(TestCase.MEDIASTORE_WRITE_IMAGE, IMediaStoreApi.MediaType.IMAGE, args)

    fun writeVideo(args: TestCaseArgs): TestResult =
        write(TestCase.MEDIASTORE_WRITE_VIDEO, IMediaStoreApi.MediaType.VIDEO, args)

    fun writeAudio(args: TestCaseArgs): TestResult =
        write(TestCase.MEDIASTORE_WRITE_AUDIO, IMediaStoreApi.MediaType.AUDIO, args)

    fun writeFile(args: TestCaseArgs): TestResult =
        write(TestCase.MEDIASTORE_WRITE_FILE, IMediaStoreApi.MediaType.FILE, args)

    fun writeDownload(args: TestCaseArgs): TestResult =
        write(TestCase.MEDIASTORE_WRITE_DOWNLOAD, IMediaStoreApi.MediaType.DOWNLOAD, args)

    fun deleteImage(args: TestCaseArgs): TestResult =
        delete(TestCase.MEDIASTORE_DELETE_IMAGE, args)

    fun deleteVideo(args: TestCaseArgs): TestResult =
        delete(TestCase.MEDIASTORE_DELETE_VIDEO, args)

    fun deleteAudio(args: TestCaseArgs): TestResult =
        delete(TestCase.MEDIASTORE_DELETE_AUDIO, args)

    fun deleteFile(args: TestCaseArgs): TestResult =
        delete(TestCase.MEDIASTORE_DELETE_FILE, args)

    fun deleteDownload(args: TestCaseArgs): TestResult =
        delete(TestCase.MEDIASTORE_DELETE_DOWNLOAD, args)

    fun thumbnailImage(args: TestCaseArgs): TestResult =
        thumbnail(TestCase.MEDIASTORE_THUMBNAIL_IMAGE, args)

    fun thumbnailVideo(args: TestCaseArgs): TestResult =
        thumbnail(TestCase.MEDIASTORE_THUMBNAIL_VIDEO, args)

    private fun query(testCase: TestCase, mediaType: IMediaStoreApi.MediaType): TestResult =
        testCase.measure {
            val rows = api.getMedia(mediaType, volume, TestFixtures.projection(mediaType))
            testCase.pass(
                message = "query completed",
                metadata = mapOf(
                    "mediaType" to mediaType.name,
                    "rowCount" to rows.size.toString(),
                    "paths" to rows.map { item -> item.joinToString { it.toString() } }
                        .joinToString(separator = "\n") { it }
                ),
            )
        }

    private fun create(
        testCase: TestCase,
        mediaType: IMediaStoreApi.MediaType,
        args: TestCaseArgs,
    ): TestResult = testCase.measure {
        val payload = args.payloadOr(TestFixtures.initialPayload(mediaType))
        val fileName = args.fileName ?: TestFixtures.fileName(mediaType)
        val uri = api.createMedia(mediaType, volume, fileName, payload)
            ?: return@measure testCase.fail("createMedia returned null")
        testCase.pass(
            message = "create succeeded",
            metadata = mapOf(
                "uri" to uri.toString(),
                "fileName" to fileName,
            ),
        )
    }

    private fun read(
        testCase: TestCase,
        mediaType: IMediaStoreApi.MediaType,
        args: TestCaseArgs,
    ): TestResult = testCase.measure {
        val uri = args.requireMediaUri(testCase) ?: return@measure args.missingUriResult(testCase)
        val expected = args.expectedPayload
        val readBack = api.readMedia(uri)?.use { it.readBytes() }
        if (readBack == null) {
            return@measure testCase.fail(
                message = "readMedia returned null",
                metadata = uriMetadata(uri),
            )
        }
        if (expected != null && !readBack.contentEquals(expected)) {
            return@measure testCase.fail(
                message = "payload mismatch",
                metadata = uriMetadata(uri) + mapOf(
                    "expectedSize" to expected.size.toString(),
                    "actualSize" to readBack.size.toString(),
                ),
            )
        }
        testCase.pass(
            message = if (expected != null) "read matched expected payload" else "read completed",
            metadata = uriMetadata(uri) + mapOf("bytesRead" to readBack.size.toString()),
        )
    }

    private fun write(
        testCase: TestCase,
        mediaType: IMediaStoreApi.MediaType,
        args: TestCaseArgs,
    ): TestResult = testCase.measure {
        val uri = args.requireMediaUri(testCase) ?: return@measure args.missingUriResult(testCase)
        val payload = args.payloadOr(TestFixtures.updatedPayload(mediaType))
        if (!api.writeMedia(uri, payload)) {
            return@measure testCase.fail(
                message = "writeMedia returned false",
                metadata = uriMetadata(uri),
            )
        }
        if (args.expectedPayload != null) {
            val readBack = api.readMedia(uri)?.use { it.readBytes() }
            if (readBack == null || !readBack.contentEquals(args.expectedPayload)) {
                return@measure testCase.fail(
                    message = "read after write did not match expected_payload",
                    metadata = uriMetadata(uri),
                )
            }
        }
        testCase.pass(
            message = "write succeeded",
            metadata = uriMetadata(uri) + mapOf("bytesWritten" to payload.size.toString()),
        )
    }

    private fun delete(testCase: TestCase, args: TestCaseArgs): TestResult = testCase.measure {
        val uri = args.requireMediaUri(testCase) ?: return@measure args.missingUriResult(testCase)
        val deleted = api.deleteMedia(uri)
        if (!deleted) {
            return@measure testCase.fail(
                message = "deleteMedia returned false",
                metadata = uriMetadata(uri),
            )
        }
        testCase.pass(message = "delete succeeded", metadata = uriMetadata(uri))
    }

    private fun thumbnail(testCase: TestCase, args: TestCaseArgs): TestResult = testCase.measure {
        val uri = args.requireMediaUri(testCase) ?: return@measure args.missingUriResult(testCase)
        val bitmap = api.loadThumbnail(uri, Size(200, 200))
        if (bitmap == null) {
            return@measure testCase.fail(
                message = "loadThumbnail returned null",
                metadata = uriMetadata(uri),
            )
        }
        testCase.pass(
            message = "thumbnail loaded",
            metadata = uriMetadata(uri) + mapOf(
                "width" to bitmap.width.toString(),
                "height" to bitmap.height.toString(),
            ),
        )
    }

    private fun uriMetadata(uri: Uri): Map<String, String> = mapOf("uri" to uri.toString())
}

private fun TestCaseArgs.requireMediaUri(testCase: TestCase): Uri? = mediaUri

private fun TestCaseArgs.missingUriResult(testCase: TestCase): TestResult =
    testCase.fail(
        message = "missing required parameter: ${TestCaseArgs.EXTRA_MEDIA_URI}",
        metadata = mapOf("hint" to "pass content URI via broadcast --es ${TestCaseArgs.EXTRA_MEDIA_URI}"),
    )
