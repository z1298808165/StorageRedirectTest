package me.fakerqu.media_store_api

import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream

class FileApiImpl : IFileApi {
    override fun getDirFilesRecursive(dir: String): List<File> {
        val dirFile = File(dir)
        return if (dirFile.exists() && dirFile.isDirectory) {
            dirFile.walk().map {
                it
            }.toList()
        } else {
            emptyList()
        }
    }

    override fun readFile(file: String): InputStream = FileInputStream(file)

    override fun writeFile(file: String): OutputStream = FileOutputStream(file)

    override fun createFile(path: String): File {
        if (path.endsWith("/")) {
            File(path).mkdirs()
        } else {
            File(path).createNewFile()
        }
        return File(path)
    }

    override fun deleteFile(path: String): Boolean {
        val file = File(path)
        return if (file.isFile) {
            file.delete()
        } else {
            file.deleteRecursively()
        }
    }
}