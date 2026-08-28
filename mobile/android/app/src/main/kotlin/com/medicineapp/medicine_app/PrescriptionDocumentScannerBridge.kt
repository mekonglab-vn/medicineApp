package com.medicineapp.medicine_app

import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.google.android.gms.common.api.ApiException
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap

internal class PrescriptionDocumentScannerBridge(
    private val activity: FlutterActivity,
    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor(),
) {
    private var channel: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null
    private var startedAtMilliseconds = 0L
    private val leasedCachePaths = ConcurrentHashMap.newKeySet<String>()
    private var activeCacheFile: File? = null
    @Volatile
    private var disposed = false

    private companion object {
        fun scheduleDetachedLeaseCleanup(
            appCacheDirectory: File,
            canonicalPaths: Set<String>,
            detachedAtMilliseconds: Long,
        ) {
            if (canonicalPaths.isEmpty()) return
            Handler(Looper.getMainLooper()).postDelayed(
                {
                    PrescriptionDocumentScannerCachePolicy.expiredDetachedLeaseFiles(
                        appCacheDirectory = appCacheDirectory,
                        canonicalPaths = canonicalPaths,
                        detachedAtMilliseconds = detachedAtMilliseconds,
                        nowMilliseconds = System.currentTimeMillis(),
                    ).forEach(File::delete)
                },
                PrescriptionDocumentScannerCachePolicy.STALE_CACHE_AGE_MILLISECONDS,
            )
        }
    }

    init {
        ioExecutor.execute(::deleteStaleCacheFiles)
    }

    fun register(messenger: BinaryMessenger) {
        check(channel == null)
        channel = MethodChannel(
            messenger,
            PrescriptionDocumentScannerChannelContract.CHANNEL_NAME,
        ).also { methodChannel ->
            methodChannel.setMethodCallHandler(::handleMethodCall)
        }
    }

    fun dispose() {
        disposed = true
        channel?.setMethodCallHandler(null)
        channel = null
        pendingResult?.success(
            PrescriptionDocumentScannerChannelContract.failure(
                PrescriptionDocumentScannerChannelContract.CODE_UNKNOWN,
            ),
        )
        pendingResult = null
        val detachedAtMilliseconds = System.currentTimeMillis()
        val detachedLeasePaths = leasedCachePaths.toSet()
        PrescriptionDocumentScannerCachePolicy.renewDetachedLeaseGrace(
            appCacheDirectory = activity.cacheDir,
            canonicalPaths = detachedLeasePaths,
            nowMilliseconds = detachedAtMilliseconds,
        )
        scheduleDetachedLeaseCleanup(
            appCacheDirectory = activity.cacheDir,
            canonicalPaths = detachedLeasePaths,
            detachedAtMilliseconds = detachedAtMilliseconds,
        )
        leasedCachePaths.clear()
        ioExecutor.execute {
            activeCacheFile?.delete()
            activeCacheFile = null
        }
        ioExecutor.shutdown()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            PrescriptionDocumentScannerChannelContract.METHOD_SCAN -> handleScan(call, result)
            PrescriptionDocumentScannerChannelContract.METHOD_RELEASE -> handleRelease(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleScan(call: MethodCall, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.success(
                PrescriptionDocumentScannerChannelContract.failure(
                    PrescriptionDocumentScannerChannelContract.CODE_ACQUISITION_IN_PROGRESS,
                ),
            )
            return
        }

        val request = PrescriptionDocumentScannerChannelContract.parseRequest(call.arguments)
        if (request == null) {
            result.success(
                PrescriptionDocumentScannerChannelContract.failure(
                    PrescriptionDocumentScannerChannelContract.CODE_INVALID_RESULT,
                ),
            )
            return
        }

        pendingResult = result
        startedAtMilliseconds = SystemClock.elapsedRealtime()
        ioExecutor.execute(::deleteStaleCacheFiles)
        launchScanner(request)
    }

    private fun handleRelease(call: MethodCall, result: MethodChannel.Result) {
        val cachePath = PrescriptionDocumentScannerChannelContract.parseReleasePath(call.arguments)
        if (cachePath == null) {
            result.success(false)
            return
        }

        ioExecutor.execute {
            val released = releaseCacheFile(cachePath)
            activity.runOnUiThread {
                if (!disposed) result.success(released)
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PrescriptionDocumentScannerChannelContract.ACTIVITY_REQUEST_CODE ||
            pendingResult == null
        ) {
            return false
        }
        handleScannerResult(resultCode, data)
        return true
    }

    private fun launchScanner(request: PrescriptionDocumentScannerChannelContract.Request) {
        try {
            val options = GmsDocumentScannerOptions.Builder()
                .setGalleryImportAllowed(request.allowGalleryImport)
                .setPageLimit(PrescriptionDocumentScannerChannelContract.PAGE_LIMIT)
                .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
                .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
                .build()

            GmsDocumentScanning.getClient(options)
                .getStartScanIntent(activity)
                .addOnSuccessListener { intentSender ->
                    try {
                        activity.startIntentSenderForResult(
                            intentSender,
                            PrescriptionDocumentScannerChannelContract.ACTIVITY_REQUEST_CODE,
                            null,
                            0,
                            0,
                            0,
                        )
                    } catch (error: Exception) {
                        completeLaunchFailure(error)
                    }
                }
                .addOnFailureListener(::completeLaunchFailure)
        } catch (error: RuntimeException) {
            completeLaunchFailure(error)
        }
    }

    private fun handleScannerResult(resultCode: Int, data: Intent?) {
        if (pendingResult == null) return
        if (resultCode == Activity.RESULT_CANCELED) {
            complete(PrescriptionDocumentScannerChannelContract.cancelled())
            return
        }
        if (resultCode != Activity.RESULT_OK) {
            complete(
                PrescriptionDocumentScannerChannelContract.failure(
                    PrescriptionDocumentScannerChannelContract.CODE_UNKNOWN,
                ),
            )
            return
        }

        val scanResult = try {
            GmsDocumentScanningResult.fromActivityResultIntent(data)
        } catch (_: RuntimeException) {
            complete(
                PrescriptionDocumentScannerChannelContract.failure(
                    PrescriptionDocumentScannerChannelContract.CODE_INVALID_RESULT,
                ),
            )
            return
        }
        val pages = scanResult?.pages
        if (pages == null || pages.size != PrescriptionDocumentScannerChannelContract.PAGE_LIMIT) {
            complete(
                PrescriptionDocumentScannerChannelContract.failure(
                    PrescriptionDocumentScannerChannelContract.CODE_INVALID_RESULT,
                ),
            )
            return
        }

        val imageUri = pages.single().imageUri
        ioExecutor.execute {
            val payload = try {
                copyScannerJpegToCache(imageUri)
            } catch (_: RuntimeException) {
                deleteActiveCacheFileAndFail(
                    PrescriptionDocumentScannerChannelContract.CODE_UNKNOWN,
                )
            }
            activity.runOnUiThread { complete(payload) }
        }
    }

    private fun copyScannerJpegToCache(imageUri: android.net.Uri): Map<String, Any> {
        val scanCacheDirectory = PrescriptionDocumentScannerCachePolicy.directory(activity.cacheDir)
        if ((!scanCacheDirectory.exists() && !scanCacheDirectory.mkdirs()) ||
            !scanCacheDirectory.isDirectory
        ) {
            return PrescriptionDocumentScannerChannelContract.failure(
                PrescriptionDocumentScannerChannelContract.CODE_CACHE_FILE_UNAVAILABLE,
            )
        }

        val cacheFile = try {
            File.createTempFile(
                PrescriptionDocumentScannerCachePolicy.FILE_PREFIX,
                PrescriptionDocumentScannerCachePolicy.FILE_SUFFIX,
                scanCacheDirectory,
            ).also { activeCacheFile = it.absoluteFile }
        } catch (_: IOException) {
            return PrescriptionDocumentScannerChannelContract.failure(
                PrescriptionDocumentScannerChannelContract.CODE_CACHE_FILE_UNAVAILABLE,
            )
        } catch (_: SecurityException) {
            return PrescriptionDocumentScannerChannelContract.failure(
                PrescriptionDocumentScannerChannelContract.CODE_CACHE_FILE_UNAVAILABLE,
            )
        }

        val byteSize = try {
            activity.contentResolver.openInputStream(imageUri)?.use { input ->
                FileOutputStream(cacheFile).use { output ->
                    PrescriptionDocumentScannerCacheCopier.copy(input, output)
                }
            }
        } catch (_: IOException) {
            null
        } catch (_: SecurityException) {
            return deleteActiveCacheFileAndFail(
                PrescriptionDocumentScannerChannelContract.CODE_PERMISSION_DENIED,
            )
        }

        if (byteSize == null) {
            return deleteActiveCacheFileAndFail(
                PrescriptionDocumentScannerChannelContract.CODE_CACHE_FILE_UNAVAILABLE,
            )
        }
        if (byteSize.exceededLimit) {
            return deleteActiveCacheFileAndFail(
                PrescriptionDocumentScannerChannelContract.CODE_FILE_TOO_LARGE,
            )
        }
        if (!isJpeg(cacheFile)) {
            return deleteActiveCacheFileAndFail(
                PrescriptionDocumentScannerChannelContract.CODE_INVALID_RESULT,
            )
        }

        val bitmapOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(cacheFile.absolutePath, bitmapOptions)
        if (bitmapOptions.outWidth <= 0 || bitmapOptions.outHeight <= 0) {
            return deleteActiveCacheFileAndFail(
                PrescriptionDocumentScannerChannelContract.CODE_INVALID_RESULT,
            )
        }

        val canonicalPath = try {
            cacheFile.canonicalPath
        } catch (_: IOException) {
            return deleteActiveCacheFileAndFail(
                PrescriptionDocumentScannerChannelContract.CODE_CACHE_FILE_UNAVAILABLE,
            )
        }
        activeCacheFile = null
        if (disposed) {
            cacheFile.delete()
            return PrescriptionDocumentScannerChannelContract.failure(
                PrescriptionDocumentScannerChannelContract.CODE_UNKNOWN,
            )
        }
        leasedCachePaths.add(canonicalPath)

        return PrescriptionDocumentScannerChannelContract.success(
            cachePath = canonicalPath,
            width = bitmapOptions.outWidth,
            height = bitmapOptions.outHeight,
            byteSize = byteSize.byteSize,
            elapsedMilliseconds = SystemClock.elapsedRealtime() - startedAtMilliseconds,
        )
    }

    private fun isJpeg(file: File): Boolean {
        if (file.length() < 4) return false
        return try {
            FileInputStream(file).use { input ->
                input.read() == 0xFF && input.read() == 0xD8
            }
        } catch (_: IOException) {
            false
        }
    }

    private fun deleteActiveCacheFileAndFail(code: String): Map<String, Any> {
        activeCacheFile?.delete()
        activeCacheFile = null
        return PrescriptionDocumentScannerChannelContract.failure(code)
    }

    private fun releaseCacheFile(cachePath: String): Boolean {
        val cacheFile = File(cachePath)
        if (!PrescriptionDocumentScannerCachePolicy.isOwned(activity.cacheDir, cacheFile)) {
            return false
        }

        val canonicalFile = try {
            cacheFile.canonicalFile
        } catch (_: IOException) {
            return false
        }
        if (canonicalFile == activeCacheFile) return false

        leasedCachePaths.remove(canonicalFile.path)
        return !canonicalFile.exists() || canonicalFile.delete()
    }

    private fun deleteStaleCacheFiles() {
        val protectedPaths = leasedCachePaths.toMutableSet().apply {
            activeCacheFile?.canonicalPath?.let(::add)
        }
        PrescriptionDocumentScannerCachePolicy.staleFiles(
            appCacheDirectory = activity.cacheDir,
            nowMilliseconds = System.currentTimeMillis(),
            protectedCanonicalPaths = protectedPaths,
        ).forEach(File::delete)
    }

    private fun completeLaunchFailure(error: Exception) {
        when (error) {
            is SecurityException -> complete(
                PrescriptionDocumentScannerChannelContract.failure(
                    PrescriptionDocumentScannerChannelContract.CODE_PERMISSION_DENIED,
                ),
            )
            is MlKitException -> {
                val reason = when (error.errorCode) {
                    MlKitException.UNSUPPORTED ->
                        PrescriptionDocumentScannerChannelContract.ScannerUnavailableReason.UNSUPPORTED
                    MlKitException.UNAVAILABLE ->
                        PrescriptionDocumentScannerChannelContract.ScannerUnavailableReason.UNAVAILABLE
                    else -> null
                }
                val payload = reason?.let {
                    PrescriptionDocumentScannerChannelContract.unsupported(
                        PrescriptionDocumentScannerChannelContract.unsupportedCode(it),
                    )
                } ?: PrescriptionDocumentScannerChannelContract.failure(
                    PrescriptionDocumentScannerChannelContract.CODE_UNKNOWN,
                )
                complete(payload)
            }
            is ApiException -> complete(
                PrescriptionDocumentScannerChannelContract.unsupported(
                    PrescriptionDocumentScannerChannelContract.CODE_GOOGLE_PLAY_SERVICES_UNAVAILABLE,
                ),
            )
            is UnsupportedOperationException -> complete(
                PrescriptionDocumentScannerChannelContract.unsupported(
                    PrescriptionDocumentScannerChannelContract.CODE_UNSUPPORTED_DEVICE,
                ),
            )
            else -> complete(
                PrescriptionDocumentScannerChannelContract.failure(
                    PrescriptionDocumentScannerChannelContract.CODE_UNKNOWN,
                ),
            )
        }
    }

    private fun complete(payload: Map<String, Any>) {
        val result = pendingResult ?: return
        pendingResult = null
        result.success(payload)
    }
}
