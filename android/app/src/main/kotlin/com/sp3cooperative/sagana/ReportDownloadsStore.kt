package com.sp3cooperative.sagana

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException

/** Copies bytes without changing the report, and never overwrites an earlier download. */
class ReportDownloadsStore(private val context: Context) {
    fun save(source: File): String {
        val file = source.canonicalFile
        val privateRoot = File(context.applicationInfo.dataDir).canonicalPath + File.separator
        require(file.path.startsWith(privateRoot)) { "Report must be app-owned." }
        if (!file.isFile) throw FileNotFoundException("Report no longer exists.")
        require(file.length() > 0) { "Report is empty." }
        val mimeType = when (file.extension.lowercase()) {
            "pdf" -> "application/pdf"
            "csv" -> "text/csv"
            else -> throw IllegalArgumentException("Unsupported report format.")
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveMediaStore(file, mimeType)
        } else {
            saveLegacy(file, mimeType)
        }
    }

    @android.annotation.TargetApi(Build.VERSION_CODES.Q)
    private fun saveMediaStore(source: File, mimeType: String): String {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, source.name)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        // A fresh insert lets Android allocate a unique name when one already exists.
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("Downloads is unavailable.")
        try {
            val output = resolver.openOutputStream(uri, "w")
                ?: throw IOException("Cannot open the download.")
            output.use { sink ->
                source.inputStream().use { input ->
                    check(input.copyTo(sink) == source.length()) { "Incomplete download." }
                }
            }
            // Only publish a complete, closed file to other apps.
            val published = resolver.update(uri, ContentValues().apply {
                put(MediaStore.Downloads.IS_PENDING, 0)
            }, null, null)
            check(published == 1) { "Cannot publish the download." }
            return resolver.query(uri, arrayOf(MediaStore.Downloads.DISPLAY_NAME), null, null, null)
                ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
                ?: source.name
        } catch (error: Exception) {
            // Do not leave a corrupt PDF or a permanently pending row on failure.
            runCatching { resolver.delete(uri, null, null) }
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(source: File, mimeType: String): String {
        check(Environment.getExternalStorageState() == Environment.MEDIA_MOUNTED) {
            "External storage is unavailable."
        }
        val directory = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        check(directory.isDirectory || directory.mkdirs()) { "Cannot create Downloads." }
        var destination = File(directory, source.name)
        var suffix = 1
        // Atomic reservation protects existing files, including those made by other apps.
        while (!destination.createNewFile()) {
            destination = File(directory, "${source.nameWithoutExtension} (${suffix++}).${source.extension}")
        }
        try {
            destination.outputStream().use { sink ->
                source.inputStream().use { input ->
                    check(input.copyTo(sink) == source.length()) { "Incomplete download." }
                }
            }
            MediaScannerConnection.scanFile(context, arrayOf(destination.path), arrayOf(mimeType), null)
            return destination.name
        } catch (error: Exception) {
            destination.delete()
            throw error
        }
    }
}
