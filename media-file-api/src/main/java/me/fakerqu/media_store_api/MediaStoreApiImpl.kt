package me.fakerqu.media_store_api

import android.app.RecoverableSecurityException
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.graphics.Bitmap
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import android.util.Size
import android.webkit.MimeTypeMap
import androidx.core.database.getBlobOrNull
import androidx.core.database.getFloatOrNull
import androidx.core.database.getIntOrNull
import androidx.core.database.getStringOrNull
import java.io.InputStream

class MediaStoreApiImpl(private val context: Context) : IMediaStoreApi {
    override fun getMedia(
        mediaType: IMediaStoreApi.MediaType,
        volumeType: IMediaStoreApi.VolumeType,
        projection: Array<String>
    ): List<List<IMediaStoreApi.MediaColumnItem>> {
        val uri = resolveCollectionUri(mediaType,volumeType)

        return context.contentResolver.query(uri, projection, null, null, null, null)?.use {
            it.moveToPosition(-1)
            val resultList = mutableListOf<List<IMediaStoreApi.MediaColumnItem>>()
            while (it.moveToNext()) {
                resultList.add(it.mapToColumnListRow())
            }
            resultList
        } ?: emptyList()
    }

    override fun loadThumbnail(uri: Uri, size: Size): Bitmap? {
        return try {
            context.contentResolver.loadThumbnail(uri, size, null)
        } catch (e: Exception) {
            null
        }
    }

    override fun readMedia(uri: Uri): InputStream? {
        return context.contentResolver.openInputStream(uri)
    }

    override fun writeMedia(uri: Uri, content: ByteArray): Boolean {
        return try {
            context.contentResolver.openOutputStream(uri)?.use {
                it.write(content)
                it.flush()
                true
            } ?: false
        } catch (e: Exception) {
            false
        }
    }

    override fun createMedia(
        mediaType: IMediaStoreApi.MediaType,
        volumeType: IMediaStoreApi.VolumeType,
        fileName: String,
        content: ByteArray
    ): Uri? {
        if (fileName.isBlank() || content.isEmpty()) return null
        val collectionUri = resolveCollectionUri(mediaType, volumeType)
        val mimeType = guessMimeType(fileName, mediaType)
        val pendingValues = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, resolveRelativePath(mediaType))
            put(MediaStore.MediaColumns.IS_PENDING, 1)
            if (mediaType == IMediaStoreApi.MediaType.FILE) {
                put(
                    MediaStore.Files.FileColumns.MEDIA_TYPE,
                    MediaStore.Files.FileColumns.MEDIA_TYPE_NONE
                )
            }
        }
        val uri = try {
            context.contentResolver.insert(collectionUri, pendingValues)
        } catch (_: Exception) {
            null
        } ?: return null
        val written = try {
            context.contentResolver.openOutputStream(uri)?.use { stream ->
                stream.write(content)
                stream.flush()
                true
            } ?: false
        } catch (_: Exception) {
            false
        }
        if (!written) {
            try {
                context.contentResolver.delete(uri, null, null)
            } catch (_: Exception) {
            }
            return null
        }
        val publishedValues = ContentValues().apply {
            put(MediaStore.MediaColumns.IS_PENDING, 0)
            put(MediaStore.MediaColumns.SIZE, content.size.toLong())
        }
        return try {
            context.contentResolver.update(uri, publishedValues, null, null)
            uri
        } catch (_: Exception) {
            try {
                context.contentResolver.delete(uri, null, null)
            } catch (_: Exception) {
            }
            null
        }
    }

    private fun resolveCollectionUri(
        mediaType: IMediaStoreApi.MediaType,
        volumeType: IMediaStoreApi.VolumeType
    ): Uri = when (mediaType) {
        IMediaStoreApi.MediaType.IMAGE -> when (volumeType) {
            IMediaStoreApi.VolumeType.EXTERNAL -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            IMediaStoreApi.VolumeType.INTERNAL -> MediaStore.Images.Media.INTERNAL_CONTENT_URI
        }

        IMediaStoreApi.MediaType.AUDIO -> when (volumeType) {
            IMediaStoreApi.VolumeType.EXTERNAL -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            IMediaStoreApi.VolumeType.INTERNAL -> MediaStore.Audio.Media.INTERNAL_CONTENT_URI
        }

        IMediaStoreApi.MediaType.VIDEO -> when (volumeType) {
            IMediaStoreApi.VolumeType.EXTERNAL -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            IMediaStoreApi.VolumeType.INTERNAL -> MediaStore.Video.Media.INTERNAL_CONTENT_URI
        }

        IMediaStoreApi.MediaType.FILE -> when (volumeType) {
            IMediaStoreApi.VolumeType.EXTERNAL ->
                MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)

            IMediaStoreApi.VolumeType.INTERNAL ->
                MediaStore.Files.getContentUri(MediaStore.VOLUME_INTERNAL)
        }

        IMediaStoreApi.MediaType.DOWNLOAD -> when (volumeType) {
            IMediaStoreApi.VolumeType.EXTERNAL -> MediaStore.Downloads.EXTERNAL_CONTENT_URI
            IMediaStoreApi.VolumeType.INTERNAL -> MediaStore.Downloads.INTERNAL_CONTENT_URI
        }
    }

    private fun resolveRelativePath(mediaType: IMediaStoreApi.MediaType): String =
        when (mediaType) {
            IMediaStoreApi.MediaType.IMAGE -> "${Environment.DIRECTORY_PICTURES}/"
            IMediaStoreApi.MediaType.VIDEO -> "${Environment.DIRECTORY_MOVIES}/"
            IMediaStoreApi.MediaType.AUDIO -> "${Environment.DIRECTORY_MUSIC}/"
            IMediaStoreApi.MediaType.FILE -> "${Environment.DIRECTORY_DOCUMENTS}/"
            IMediaStoreApi.MediaType.DOWNLOAD -> "${Environment.DIRECTORY_DOWNLOADS}/"
        }

    private fun guessMimeType(fileName: String, mediaType: IMediaStoreApi.MediaType): String {
        val extension = fileName.substringAfterLast('.', "").lowercase()
        if (extension.isNotEmpty()) {
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)?.let { return it }
        }
        return when (mediaType) {
            IMediaStoreApi.MediaType.IMAGE -> "image/jpeg"
            IMediaStoreApi.MediaType.VIDEO -> "video/mp4"
            IMediaStoreApi.MediaType.AUDIO -> "audio/mpeg"
            IMediaStoreApi.MediaType.FILE -> "application/octet-stream"
            IMediaStoreApi.MediaType.DOWNLOAD -> "application/octet-stream"
        }
    }

    override fun deleteMedia(uri: Uri): Boolean {
        if (uri == Uri.EMPTY) return false
        return try {
            context.contentResolver.delete(uri, null, null) > 0
        } catch (_: RecoverableSecurityException) {
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun Cursor.mapToColumnListRow(): List<IMediaStoreApi.MediaColumnItem> {
        return columnNames.mapIndexedNotNull { index, string ->
            when (getType(index)) {
                Cursor.FIELD_TYPE_BLOB -> IMediaStoreApi.MediaColumnItem(
                    string,
                    getBlobOrNull(index),
                    IMediaStoreApi.ColumnType.BLOB
                )

                Cursor.FIELD_TYPE_FLOAT -> IMediaStoreApi.MediaColumnItem(
                    string,
                    getFloatOrNull(index),
                    IMediaStoreApi.ColumnType.FLOAT
                )

                Cursor.FIELD_TYPE_STRING -> IMediaStoreApi.MediaColumnItem(
                    string,
                    getStringOrNull(index),
                    IMediaStoreApi.ColumnType.STRING
                )

                Cursor.FIELD_TYPE_INTEGER -> IMediaStoreApi.MediaColumnItem(
                    string,
                    getIntOrNull(index),
                    IMediaStoreApi.ColumnType.INT
                )

                Cursor.FIELD_TYPE_NULL -> IMediaStoreApi.MediaColumnItem(
                    string,
                    null,
                    IMediaStoreApi.ColumnType.NULL
                )

                else -> null
            }
        }
    }
}