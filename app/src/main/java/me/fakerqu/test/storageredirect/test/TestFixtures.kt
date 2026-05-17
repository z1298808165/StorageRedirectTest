package me.fakerqu.test.storageredirect.test

import android.provider.MediaStore
import me.fakerqu.media_store_api.IMediaStoreApi

object TestFixtures {
    private const val PAYLOAD_PREFIX = "storage-redirect-test:"

    fun projection(mediaType: IMediaStoreApi.MediaType): Array<String> = when (mediaType) {
        IMediaStoreApi.MediaType.IMAGE ->
            arrayOf(
                MediaStore.Images.ImageColumns._ID,
                MediaStore.Images.ImageColumns.RELATIVE_PATH,
                MediaStore.Images.ImageColumns.TITLE,
                MediaStore.Images.ImageColumns.DATA,
            )

        IMediaStoreApi.MediaType.VIDEO ->
            arrayOf(
                MediaStore.Video.VideoColumns._ID,
                MediaStore.Video.VideoColumns.RELATIVE_PATH,
                MediaStore.Video.VideoColumns.TITLE,
                MediaStore.Video.VideoColumns.DATA,
            )

        IMediaStoreApi.MediaType.AUDIO ->
            arrayOf(
                MediaStore.Audio.AudioColumns._ID,
                MediaStore.Audio.AudioColumns.RELATIVE_PATH,
                MediaStore.Audio.AudioColumns.TITLE,
                MediaStore.Audio.AudioColumns.DATA,
            )

        IMediaStoreApi.MediaType.FILE ->
            arrayOf(
                MediaStore.Files.FileColumns._ID,
                MediaStore.Files.FileColumns.RELATIVE_PATH,
                MediaStore.Files.FileColumns.TITLE,
                MediaStore.Files.FileColumns.DATA,
            )

        IMediaStoreApi.MediaType.DOWNLOAD ->
            arrayOf(
                MediaStore.Downloads._ID,
                MediaStore.Downloads.RELATIVE_PATH,
                MediaStore.Downloads.TITLE,
                MediaStore.Downloads.DATA,
            )
    }

    fun fileName(mediaType: IMediaStoreApi.MediaType): String =
        "srt_${mediaType.name.lowercase()}_${System.currentTimeMillis()}${extension(mediaType)}"

    fun initialPayload(mediaType: IMediaStoreApi.MediaType): ByteArray =
        "$PAYLOAD_PREFIX${mediaType.name}:initial".toByteArray()

    fun updatedPayload(mediaType: IMediaStoreApi.MediaType): ByteArray =
        "$PAYLOAD_PREFIX${mediaType.name}:updated".toByteArray()

    fun filePayload(tag: String): ByteArray =
        "$PAYLOAD_PREFIX:file:$tag".toByteArray()

    private fun extension(mediaType: IMediaStoreApi.MediaType): String = when (mediaType) {
        IMediaStoreApi.MediaType.IMAGE -> ".jpg"
        IMediaStoreApi.MediaType.VIDEO -> ".mp4"
        IMediaStoreApi.MediaType.AUDIO -> ".mp3"
        IMediaStoreApi.MediaType.FILE -> ".txt"
        IMediaStoreApi.MediaType.DOWNLOAD -> ".bin"
    }
}
