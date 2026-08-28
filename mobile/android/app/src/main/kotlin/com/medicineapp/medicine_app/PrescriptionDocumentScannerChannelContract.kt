package com.medicineapp.medicine_app

import java.io.InputStream
import java.io.OutputStream
import java.io.File
import java.io.IOException

internal object PrescriptionDocumentScannerChannelContract {
    const val CHANNEL_NAME = "com.medicineapp.medicine_app/prescription_document_scanner"
    const val METHOD_SCAN = "scanPrescriptionDocument"
    const val METHOD_RELEASE = "releasePrescriptionDocument"
    const val ARG_ALLOW_GALLERY_IMPORT = "allow_gallery_import"
    const val ARG_CACHE_PATH = "cache_path"
    const val ACTIVITY_REQUEST_CODE = 0x4D50

    const val PAGE_LIMIT = 1
    const val SCANNER_MODE = "full"
    const val SCANNER_VERSION = "16.0.0"
    const val MIME_TYPE = "image/jpeg"
    const val MAX_FILE_BYTES = 10L * 1024L * 1024L

    const val KEY_STATUS = "status"
    const val KEY_CODE = "code"
    const val KEY_MESSAGE = "message"
    const val KEY_CACHE_PATH = "cache_path"
    const val KEY_FILENAME = "filename"
    const val KEY_MIME_TYPE = "mime_type"
    const val KEY_WIDTH = "width"
    const val KEY_HEIGHT = "height"
    const val KEY_BYTE_SIZE = "byte_size"
    const val KEY_SCANNER_MODE = "scanner_mode"
    const val KEY_SCANNER_VERSION = "scanner_version"
    const val KEY_ELAPSED_MILLISECONDS = "elapsed_milliseconds"

    const val CODE_UNSUPPORTED_DEVICE = "unsupported_device"
    const val CODE_GOOGLE_PLAY_SERVICES_UNAVAILABLE = "google_play_services_unavailable"
    const val CODE_PERMISSION_DENIED = "permission_denied"
    const val CODE_ACQUISITION_IN_PROGRESS = "acquisition_in_progress"
    const val CODE_INVALID_RESULT = "invalid_result"
    const val CODE_CACHE_FILE_UNAVAILABLE = "cache_file_unavailable"
    const val CODE_FILE_TOO_LARGE = "file_too_large"
    const val CODE_UNKNOWN = "unknown"

    data class Request(val allowGalleryImport: Boolean)

    enum class ScannerUnavailableReason {
        UNSUPPORTED,
        UNAVAILABLE,
    }

    fun parseRequest(arguments: Any?): Request? {
        val values = arguments as? Map<*, *> ?: return null
        val allowGalleryImport = values[ARG_ALLOW_GALLERY_IMPORT] as? Boolean ?: return null
        return Request(allowGalleryImport)
    }

    fun parseReleasePath(arguments: Any?): String? {
        val values = arguments as? Map<*, *> ?: return null
        return (values[ARG_CACHE_PATH] as? String)?.takeIf(String::isNotEmpty)
    }

    fun unsupportedCode(reason: ScannerUnavailableReason): String = when (reason) {
        ScannerUnavailableReason.UNSUPPORTED -> CODE_UNSUPPORTED_DEVICE
        ScannerUnavailableReason.UNAVAILABLE -> CODE_GOOGLE_PLAY_SERVICES_UNAVAILABLE
    }

    fun success(
        cachePath: String,
        width: Int,
        height: Int,
        byteSize: Long,
        elapsedMilliseconds: Long,
    ): Map<String, Any> = linkedMapOf(
        KEY_STATUS to "success",
        KEY_CACHE_PATH to cachePath,
        KEY_FILENAME to "prescription.jpg",
        KEY_MIME_TYPE to MIME_TYPE,
        KEY_WIDTH to width,
        KEY_HEIGHT to height,
        KEY_BYTE_SIZE to byteSize,
        KEY_SCANNER_MODE to SCANNER_MODE,
        KEY_SCANNER_VERSION to SCANNER_VERSION,
        KEY_ELAPSED_MILLISECONDS to elapsedMilliseconds,
    )

    fun cancelled(): Map<String, Any> = mapOf(KEY_STATUS to "cancelled")

    fun unsupported(code: String): Map<String, Any> = mapOf(
        KEY_STATUS to "unsupported",
        KEY_CODE to code,
        KEY_MESSAGE to unavailableMessage(code),
    )

    fun failure(code: String): Map<String, Any> = mapOf(
        KEY_STATUS to "failure",
        KEY_CODE to code,
        KEY_MESSAGE to failureMessage(code),
    )

    private fun unavailableMessage(code: String): String = when (code) {
        CODE_GOOGLE_PLAY_SERVICES_UNAVAILABLE -> "Google Play services cannot provide the document scanner."
        else -> "The document scanner is unsupported on this device."
    }

    private fun failureMessage(code: String): String = when (code) {
        CODE_PERMISSION_DENIED -> "Document scanner permission was denied."
        CODE_ACQUISITION_IN_PROGRESS -> "A prescription scan is already in progress."
        CODE_INVALID_RESULT -> "The document scanner returned an invalid result."
        CODE_CACHE_FILE_UNAVAILABLE -> "Scanner output could not be cached."
        CODE_FILE_TOO_LARGE -> "The scanned prescription exceeds the 10 MB limit."
        else -> "Prescription document scanning failed."
    }
}

internal object PrescriptionDocumentScannerCachePolicy {
    const val DIRECTORY_NAME = "prescription_scans"
    const val FILE_PREFIX = "prescription_scan_"
    const val FILE_SUFFIX = ".jpg"
    const val STALE_CACHE_AGE_MILLISECONDS = 24L * 60L * 60L * 1000L

    fun directory(appCacheDirectory: File): File = File(appCacheDirectory, DIRECTORY_NAME)

    fun isOwned(appCacheDirectory: File, candidate: File): Boolean {
        return try {
            val canonicalDirectory = directory(appCacheDirectory).canonicalFile
            val canonicalCandidate = candidate.canonicalFile
            canonicalCandidate.parentFile == canonicalDirectory &&
                canonicalCandidate.name.startsWith(FILE_PREFIX) &&
                canonicalCandidate.name.endsWith(FILE_SUFFIX)
        } catch (_: IOException) {
            false
        }
    }

    fun staleFiles(
        appCacheDirectory: File,
        nowMilliseconds: Long,
        protectedCanonicalPaths: Set<String>,
    ): List<File> {
        val files = directory(appCacheDirectory).listFiles() ?: return emptyList()
        return files.mapNotNull { file ->
            val canonicalFile = try {
                file.canonicalFile
            } catch (_: IOException) {
                return@mapNotNull null
            }
            canonicalFile.takeIf {
                it.isFile &&
                    isOwned(appCacheDirectory, it) &&
                    it.canonicalPath !in protectedCanonicalPaths &&
                    nowMilliseconds - it.lastModified() >= STALE_CACHE_AGE_MILLISECONDS
            }
        }.sortedBy { it.name }
    }

    fun renewDetachedLeaseGrace(
        appCacheDirectory: File,
        canonicalPaths: Set<String>,
        nowMilliseconds: Long,
    ) {
        canonicalPaths.forEach { path ->
            val file = File(path)
            if (isOwned(appCacheDirectory, file) && file.isFile) {
                file.setLastModified(nowMilliseconds)
            }
        }
    }

    fun expiredDetachedLeaseFiles(
        appCacheDirectory: File,
        canonicalPaths: Set<String>,
        detachedAtMilliseconds: Long,
        nowMilliseconds: Long,
    ): List<File> {
        if (nowMilliseconds - detachedAtMilliseconds < STALE_CACHE_AGE_MILLISECONDS) {
            return emptyList()
        }
        return canonicalPaths.mapNotNull { path ->
            val file = try {
                File(path).canonicalFile
            } catch (_: IOException) {
                return@mapNotNull null
            }
            file.takeIf {
                isOwned(appCacheDirectory, it) &&
                    it.isFile &&
                    it.lastModified() <= detachedAtMilliseconds
            }
        }
    }
}

internal object PrescriptionDocumentScannerCacheCopier {
    data class Result(val byteSize: Long, val exceededLimit: Boolean)

    fun copy(
        input: InputStream,
        output: OutputStream,
        maxBytes: Long = PrescriptionDocumentScannerChannelContract.MAX_FILE_BYTES,
    ): Result {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        while (true) {
            val count = input.read(buffer)
            if (count < 0) return Result(total, exceededLimit = false)
            total += count
            if (total > maxBytes) return Result(total, exceededLimit = true)
            output.write(buffer, 0, count)
        }
    }
}
