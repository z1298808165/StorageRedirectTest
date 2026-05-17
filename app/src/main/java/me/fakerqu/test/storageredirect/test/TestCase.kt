package me.fakerqu.test.storageredirect.test

import android.content.Context
import me.fakerqu.media_store_api.IMediaStoreApi

/**
 * 每个枚举值对应一个独立操作，可通过广播传入 [id] 及 [TestCaseArgs] 中的参数。
 */
enum class TestCase(val id: String) {
    ALL_EXCEPT_DELETE("all"),

    MEDIASTORE_QUERY_IMAGE("mediastore_query_image"),
    MEDIASTORE_QUERY_VIDEO("mediastore_query_video"),
    MEDIASTORE_QUERY_AUDIO("mediastore_query_audio"),
    MEDIASTORE_QUERY_FILE("mediastore_query_file"),
    MEDIASTORE_QUERY_DOWNLOAD("mediastore_query_download"),

    MEDIASTORE_CREATE_IMAGE("mediastore_create_image"),
    MEDIASTORE_CREATE_VIDEO("mediastore_create_video"),
    MEDIASTORE_CREATE_AUDIO("mediastore_create_audio"),
    MEDIASTORE_CREATE_FILE("mediastore_create_file"),
    MEDIASTORE_CREATE_DOWNLOAD("mediastore_create_download"),

    MEDIASTORE_READ_IMAGE("mediastore_read_image"),
    MEDIASTORE_READ_VIDEO("mediastore_read_video"),
    MEDIASTORE_READ_AUDIO("mediastore_read_audio"),
    MEDIASTORE_READ_FILE("mediastore_read_file"),
    MEDIASTORE_READ_DOWNLOAD("mediastore_read_download"),

    MEDIASTORE_WRITE_IMAGE("mediastore_write_image"),
    MEDIASTORE_WRITE_VIDEO("mediastore_write_video"),
    MEDIASTORE_WRITE_AUDIO("mediastore_write_audio"),
    MEDIASTORE_WRITE_FILE("mediastore_write_file"),
    MEDIASTORE_WRITE_DOWNLOAD("mediastore_write_download"),

    MEDIASTORE_DELETE_IMAGE("mediastore_delete_image"),
    MEDIASTORE_DELETE_VIDEO("mediastore_delete_video"),
    MEDIASTORE_DELETE_AUDIO("mediastore_delete_audio"),
    MEDIASTORE_DELETE_FILE("mediastore_delete_file"),
    MEDIASTORE_DELETE_DOWNLOAD("mediastore_delete_download"),

    MEDIASTORE_THUMBNAIL_IMAGE("mediastore_thumbnail_image"),
    MEDIASTORE_THUMBNAIL_VIDEO("mediastore_thumbnail_video"),

    FILE_LIST_DIR("file_list_dir"),
    FILE_CREATE("file_create"),
    FILE_READ("file_read"),
    FILE_WRITE("file_write"),
    FILE_DELETE("file_delete");

    fun getMediaType(): IMediaStoreApi.MediaType? = when (this) {
        MEDIASTORE_QUERY_IMAGE, MEDIASTORE_CREATE_IMAGE, MEDIASTORE_READ_IMAGE,
        MEDIASTORE_WRITE_IMAGE, MEDIASTORE_DELETE_IMAGE, MEDIASTORE_THUMBNAIL_IMAGE ->
            IMediaStoreApi.MediaType.IMAGE

        MEDIASTORE_QUERY_VIDEO, MEDIASTORE_CREATE_VIDEO, MEDIASTORE_READ_VIDEO,
        MEDIASTORE_WRITE_VIDEO, MEDIASTORE_DELETE_VIDEO, MEDIASTORE_THUMBNAIL_VIDEO ->
            IMediaStoreApi.MediaType.VIDEO

        MEDIASTORE_QUERY_AUDIO, MEDIASTORE_CREATE_AUDIO, MEDIASTORE_READ_AUDIO,
        MEDIASTORE_WRITE_AUDIO, MEDIASTORE_DELETE_AUDIO ->
            IMediaStoreApi.MediaType.AUDIO

        MEDIASTORE_QUERY_FILE, MEDIASTORE_CREATE_FILE, MEDIASTORE_READ_FILE,
        MEDIASTORE_WRITE_FILE, MEDIASTORE_DELETE_FILE ->
            IMediaStoreApi.MediaType.FILE

        MEDIASTORE_QUERY_DOWNLOAD, MEDIASTORE_CREATE_DOWNLOAD, MEDIASTORE_READ_DOWNLOAD,
        MEDIASTORE_WRITE_DOWNLOAD, MEDIASTORE_DELETE_DOWNLOAD ->
            IMediaStoreApi.MediaType.DOWNLOAD

        else -> null
    }

    fun requiresMediaUri(): Boolean = when (this) {
        MEDIASTORE_READ_IMAGE, MEDIASTORE_READ_VIDEO, MEDIASTORE_READ_AUDIO,
        MEDIASTORE_READ_FILE, MEDIASTORE_READ_DOWNLOAD,
        MEDIASTORE_WRITE_IMAGE, MEDIASTORE_WRITE_VIDEO, MEDIASTORE_WRITE_AUDIO,
        MEDIASTORE_WRITE_FILE, MEDIASTORE_WRITE_DOWNLOAD,
        MEDIASTORE_DELETE_IMAGE, MEDIASTORE_DELETE_VIDEO, MEDIASTORE_DELETE_AUDIO,
        MEDIASTORE_DELETE_FILE, MEDIASTORE_DELETE_DOWNLOAD,
        MEDIASTORE_THUMBNAIL_IMAGE, MEDIASTORE_THUMBNAIL_VIDEO -> true

        else -> false
    }

    fun requiresFilePath(): Boolean = this in setOf(
        FILE_READ, FILE_WRITE, FILE_DELETE, FILE_CREATE,
    )

    fun requiresFileDir(): Boolean = this == FILE_LIST_DIR

    fun run(context: Context, args: TestCaseArgs = TestCaseArgs()): TestResult {
        val mediaStore = MediaStoreTestCases(context)
        val file = FileTestCases(context)
        return when (this) {
            ALL_EXCEPT_DELETE -> error("ALL must be handled by StorageRedirectTestRunner")

            MEDIASTORE_QUERY_IMAGE -> mediaStore.queryImage()
            MEDIASTORE_QUERY_VIDEO -> mediaStore.queryVideo()
            MEDIASTORE_QUERY_AUDIO -> mediaStore.queryAudio()
            MEDIASTORE_QUERY_FILE -> mediaStore.queryFile()
            MEDIASTORE_QUERY_DOWNLOAD -> mediaStore.queryDownload()

            MEDIASTORE_CREATE_IMAGE -> mediaStore.createImage(args)
            MEDIASTORE_CREATE_VIDEO -> mediaStore.createVideo(args)
            MEDIASTORE_CREATE_AUDIO -> mediaStore.createAudio(args)
            MEDIASTORE_CREATE_FILE -> mediaStore.createFile(args)
            MEDIASTORE_CREATE_DOWNLOAD -> mediaStore.createDownload(args)

            MEDIASTORE_READ_IMAGE -> mediaStore.readImage(args)
            MEDIASTORE_READ_VIDEO -> mediaStore.readVideo(args)
            MEDIASTORE_READ_AUDIO -> mediaStore.readAudio(args)
            MEDIASTORE_READ_FILE -> mediaStore.readFile(args)
            MEDIASTORE_READ_DOWNLOAD -> mediaStore.readDownload(args)

            MEDIASTORE_WRITE_IMAGE -> mediaStore.writeImage(args)
            MEDIASTORE_WRITE_VIDEO -> mediaStore.writeVideo(args)
            MEDIASTORE_WRITE_AUDIO -> mediaStore.writeAudio(args)
            MEDIASTORE_WRITE_FILE -> mediaStore.writeFile(args)
            MEDIASTORE_WRITE_DOWNLOAD -> mediaStore.writeDownload(args)

            MEDIASTORE_DELETE_IMAGE -> mediaStore.deleteImage(args)
            MEDIASTORE_DELETE_VIDEO -> mediaStore.deleteVideo(args)
            MEDIASTORE_DELETE_AUDIO -> mediaStore.deleteAudio(args)
            MEDIASTORE_DELETE_FILE -> mediaStore.deleteFile(args)
            MEDIASTORE_DELETE_DOWNLOAD -> mediaStore.deleteDownload(args)

            MEDIASTORE_THUMBNAIL_IMAGE -> mediaStore.thumbnailImage(args)
            MEDIASTORE_THUMBNAIL_VIDEO -> mediaStore.thumbnailVideo(args)

            FILE_LIST_DIR -> file.listDir(args)
            FILE_CREATE -> file.create(args)
            FILE_READ -> file.read(args)
            FILE_WRITE -> file.write(args)
            FILE_DELETE -> file.delete(args)
        }
    }

    companion object {
        fun fromId(id: String?): TestCase = entries.firstOrNull { it.id == id } ?: ALL_EXCEPT_DELETE

        val executableCases: List<TestCase> = entries.filter { it != ALL_EXCEPT_DELETE }
    }
}
