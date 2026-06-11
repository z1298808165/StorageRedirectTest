package me.fakerqu.media_store_api

import java.io.File
import java.io.InputStream
import java.io.OutputStream

interface IFileApi {
    fun getDirFilesRecursive(dir: String): List<File>

    fun readFile(file: String): InputStream

    fun writeFile(file: String): OutputStream

    fun createFile(path: String): File

    fun deleteFile(path: String): Boolean

    fun mkdir(path: String): Boolean

    fun renameFile(fromPath: String, toPath: String): Boolean
}
