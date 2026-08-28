package com.medicineapp.medicine_app

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PrescriptionDocumentScannerChannelContractTest {
    @Test
    fun `scanner configuration is locked to one full-mode JPEG page`() {
        assertEquals(0x4D50, PrescriptionDocumentScannerChannelContract.ACTIVITY_REQUEST_CODE)
        assertEquals(1, PrescriptionDocumentScannerChannelContract.PAGE_LIMIT)
        assertEquals("full", PrescriptionDocumentScannerChannelContract.SCANNER_MODE)
        assertEquals("16.0.0", PrescriptionDocumentScannerChannelContract.SCANNER_VERSION)
        assertEquals("image/jpeg", PrescriptionDocumentScannerChannelContract.MIME_TYPE)
        assertEquals(10L * 1024L * 1024L, PrescriptionDocumentScannerChannelContract.MAX_FILE_BYTES)
    }

    @Test
    fun `release request accepts only a non-empty cache path`() {
        assertEquals(
            "/internal/cache/prescription_scans/prescription_scan_1.jpg",
            PrescriptionDocumentScannerChannelContract.parseReleasePath(
                mapOf(
                    PrescriptionDocumentScannerChannelContract.ARG_CACHE_PATH to
                        "/internal/cache/prescription_scans/prescription_scan_1.jpg",
                ),
            ),
        )
        assertNull(
            PrescriptionDocumentScannerChannelContract.parseReleasePath(
                mapOf(PrescriptionDocumentScannerChannelContract.ARG_CACHE_PATH to ""),
            ),
        )
    }

    @Test
    fun `both ML Kit unsupported reasons produce unsupported wire outcomes`() {
        assertEquals(
            PrescriptionDocumentScannerChannelContract.CODE_UNSUPPORTED_DEVICE,
            PrescriptionDocumentScannerChannelContract.unsupportedCode(
                PrescriptionDocumentScannerChannelContract.ScannerUnavailableReason.UNSUPPORTED,
            ),
        )
        assertEquals(
            PrescriptionDocumentScannerChannelContract.CODE_GOOGLE_PLAY_SERVICES_UNAVAILABLE,
            PrescriptionDocumentScannerChannelContract.unsupportedCode(
                PrescriptionDocumentScannerChannelContract.ScannerUnavailableReason.UNAVAILABLE,
            ),
        )
    }

    @Test
    fun `request maps gallery import only from a boolean option`() {
        val enabled = PrescriptionDocumentScannerChannelContract.parseRequest(
            mapOf(PrescriptionDocumentScannerChannelContract.ARG_ALLOW_GALLERY_IMPORT to true),
        )
        val disabled = PrescriptionDocumentScannerChannelContract.parseRequest(
            mapOf(PrescriptionDocumentScannerChannelContract.ARG_ALLOW_GALLERY_IMPORT to false),
        )

        assertTrue(enabled!!.allowGalleryImport)
        assertFalse(disabled!!.allowGalleryImport)
        assertNull(PrescriptionDocumentScannerChannelContract.parseRequest(emptyMap<String, Any>()))
        assertNull(
            PrescriptionDocumentScannerChannelContract.parseRequest(
                mapOf(PrescriptionDocumentScannerChannelContract.ARG_ALLOW_GALLERY_IMPORT to "true"),
            ),
        )
    }

    @Test
    fun `success payload contains sanitized cache metadata and no source URI`() {
        val payload = PrescriptionDocumentScannerChannelContract.success(
            cachePath = "/internal/cache/prescription_scan_1.jpg",
            width = 1200,
            height = 1600,
            byteSize = 4096,
            elapsedMilliseconds = 700,
        )

        assertEquals("success", payload[PrescriptionDocumentScannerChannelContract.KEY_STATUS])
        assertEquals("prescription.jpg", payload[PrescriptionDocumentScannerChannelContract.KEY_FILENAME])
        assertEquals("image/jpeg", payload[PrescriptionDocumentScannerChannelContract.KEY_MIME_TYPE])
        assertFalse(payload.keys.any { it.contains("uri", ignoreCase = true) })
        assertFalse(payload.keys.any { it.contains("original", ignoreCase = true) })
        assertFalse(payload.containsValue("content://scanner/private-document"))
    }

    @Test
    fun `cancel unsupported and failure use stable wire values`() {
        assertEquals(
            "cancelled",
            PrescriptionDocumentScannerChannelContract.cancelled()[PrescriptionDocumentScannerChannelContract.KEY_STATUS],
        )
        assertEquals(
            "google_play_services_unavailable",
            PrescriptionDocumentScannerChannelContract.unsupported(
                PrescriptionDocumentScannerChannelContract.CODE_GOOGLE_PLAY_SERVICES_UNAVAILABLE,
            )[PrescriptionDocumentScannerChannelContract.KEY_CODE],
        )
        assertEquals(
            "file_too_large",
            PrescriptionDocumentScannerChannelContract.failure(
                PrescriptionDocumentScannerChannelContract.CODE_FILE_TOO_LARGE,
            )[PrescriptionDocumentScannerChannelContract.KEY_CODE],
        )
    }

    @Test
    fun `cache copier accepts the limit and stops before writing excess data`() {
        val acceptedOutput = ByteArrayOutputStream()
        val accepted = PrescriptionDocumentScannerCacheCopier.copy(
            input = ByteArrayInputStream(ByteArray(16)),
            output = acceptedOutput,
            maxBytes = 16,
        )
        val rejectedOutput = ByteArrayOutputStream()
        val rejected = PrescriptionDocumentScannerCacheCopier.copy(
            input = ByteArrayInputStream(ByteArray(17)),
            output = rejectedOutput,
            maxBytes = 16,
        )

        assertFalse(accepted.exceededLimit)
        assertEquals(16, accepted.byteSize)
        assertEquals(16, acceptedOutput.size())
        assertTrue(rejected.exceededLimit)
        assertEquals(17, rejected.byteSize)
        assertEquals(0, rejectedOutput.size())
    }

    @Test
    fun `stale cleanup selects only owned unprotected scanner files`() {
        val appCache = Files.createTempDirectory("scanner-cache-policy").toFile()
        val scannerCache = PrescriptionDocumentScannerCachePolicy.directory(appCache)
        assertTrue(scannerCache.mkdirs())
        val now = 2L * PrescriptionDocumentScannerCachePolicy.STALE_CACHE_AGE_MILLISECONDS
        val stale = java.io.File(scannerCache, "prescription_scan_stale.jpg").apply {
            writeBytes(byteArrayOf(1))
            setLastModified(1L)
        }
        val protected = java.io.File(scannerCache, "prescription_scan_in_use.jpg").apply {
            writeBytes(byteArrayOf(1))
            setLastModified(1L)
        }
        val recent = java.io.File(scannerCache, "prescription_scan_recent.jpg").apply {
            writeBytes(byteArrayOf(1))
            setLastModified(now)
        }
        val unrelated = java.io.File(scannerCache, "other.jpg").apply {
            writeBytes(byteArrayOf(1))
            setLastModified(1L)
        }

        val selected = PrescriptionDocumentScannerCachePolicy.staleFiles(
            appCacheDirectory = appCache,
            nowMilliseconds = now,
            protectedCanonicalPaths = setOf(protected.canonicalPath),
        )

        assertEquals(listOf(stale.canonicalFile), selected)
        assertFalse(selected.contains(protected.canonicalFile))
        assertFalse(selected.contains(recent.canonicalFile))
        assertFalse(selected.contains(unrelated.canonicalFile))
        appCache.deleteRecursively()
    }

    @Test
    fun `ownership rejects files outside the scanner cache and wrong names`() {
        val appCache = Files.createTempDirectory("scanner-cache-ownership").toFile()
        val scannerCache = PrescriptionDocumentScannerCachePolicy.directory(appCache)
        assertTrue(scannerCache.mkdirs())
        val owned = java.io.File(scannerCache, "prescription_scan_owned.jpg")
        val wrongName = java.io.File(scannerCache, "other.jpg")
        val outside = java.io.File(appCache, "prescription_scan_outside.jpg")

        assertTrue(PrescriptionDocumentScannerCachePolicy.isOwned(appCache, owned))
        assertFalse(PrescriptionDocumentScannerCachePolicy.isOwned(appCache, wrongName))
        assertFalse(PrescriptionDocumentScannerCachePolicy.isOwned(appCache, outside))
        appCache.deleteRecursively()
    }

    @Test
    fun `detached lease gets finite grace before stale cleanup can collect it`() {
        val appCache = Files.createTempDirectory("scanner-cache-detach").toFile()
        val scannerCache = PrescriptionDocumentScannerCachePolicy.directory(appCache)
        assertTrue(scannerCache.mkdirs())
        val leased = java.io.File(scannerCache, "prescription_scan_leased.jpg").apply {
            writeBytes(byteArrayOf(1))
            setLastModified(1L)
        }
        val detachedAt = 5L * PrescriptionDocumentScannerCachePolicy.STALE_CACHE_AGE_MILLISECONDS

        PrescriptionDocumentScannerCachePolicy.renewDetachedLeaseGrace(
            appCacheDirectory = appCache,
            canonicalPaths = setOf(leased.canonicalPath),
            nowMilliseconds = detachedAt,
        )

        assertTrue(
            PrescriptionDocumentScannerCachePolicy.staleFiles(
                appCacheDirectory = appCache,
                nowMilliseconds = detachedAt,
                protectedCanonicalPaths = emptySet(),
            ).isEmpty(),
        )
        assertTrue(
            PrescriptionDocumentScannerCachePolicy.expiredDetachedLeaseFiles(
                appCacheDirectory = appCache,
                canonicalPaths = setOf(leased.canonicalPath),
                detachedAtMilliseconds = detachedAt,
                nowMilliseconds = detachedAt,
            ).isEmpty(),
        )
        assertEquals(
            listOf(leased.canonicalFile),
            PrescriptionDocumentScannerCachePolicy.staleFiles(
                appCacheDirectory = appCache,
                nowMilliseconds = detachedAt +
                    PrescriptionDocumentScannerCachePolicy.STALE_CACHE_AGE_MILLISECONDS,
                protectedCanonicalPaths = emptySet(),
            ),
        )
        assertEquals(
            listOf(leased.canonicalFile),
            PrescriptionDocumentScannerCachePolicy.expiredDetachedLeaseFiles(
                appCacheDirectory = appCache,
                canonicalPaths = setOf(leased.canonicalPath),
                detachedAtMilliseconds = detachedAt,
                nowMilliseconds = detachedAt +
                    PrescriptionDocumentScannerCachePolicy.STALE_CACHE_AGE_MILLISECONDS,
            ),
        )
        appCache.deleteRecursively()
    }
}
