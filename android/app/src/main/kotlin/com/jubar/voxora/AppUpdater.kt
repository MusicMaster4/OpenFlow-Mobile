package com.jubar.voxora

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.MessageDigest

data class AndroidUpdateManifest(
    val channel: String,
    val versionName: String,
    val versionCode: Long,
    val apkUrl: String,
    val sha256: String,
) {
    fun isNewerThan(installedVersionCode: Long): Boolean = versionCode > installedVersionCode

    fun toMap(): Map<String, Any> = mapOf(
        "channel" to channel,
        "versionName" to versionName,
        "versionCode" to versionCode,
        "apkUrl" to apkUrl,
        "sha256" to sha256,
    )

    fun toJson(): String = JSONObject(toMap()).toString()

    companion object {
        private val versionPattern = Regex("^\\d+\\.\\d+\\.\\d+(?:-testing\\.\\d+)?$")
        private const val releasePath = "/MusicMaster4/OpenFlow-Mobile/releases/download/"

        fun fromJson(raw: String): AndroidUpdateManifest {
            val json = JSONObject(raw)
            return create(
                channel = json.getString("channel"),
                versionName = json.getString("versionName"),
                versionCode = json.getLong("versionCode"),
                apkUrl = json.getString("apkUrl"),
                sha256 = json.getString("sha256"),
            )
        }

        fun fromMap(raw: Map<*, *>): AndroidUpdateManifest = create(
            channel = raw["channel"] as? String ?: error("The update channel is missing."),
            versionName = raw["versionName"] as? String ?: error("The update version is missing."),
            versionCode = (raw["versionCode"] as? Number)?.toLong()
                ?: error("The update version code is missing."),
            apkUrl = raw["apkUrl"] as? String ?: error("The update download is missing."),
            sha256 = raw["sha256"] as? String ?: error("The update checksum is missing."),
        )

        private fun create(
            channel: String,
            versionName: String,
            versionCode: Long,
            apkUrl: String,
            sha256: String,
        ): AndroidUpdateManifest {
            require(channel == "stable" || channel == "testing") { "Unknown update channel." }
            require(versionPattern.matches(versionName)) { "The update version is invalid." }
            require(versionCode > 0) { "The update version code is invalid." }
            val normalizedHash = sha256.lowercase()
            require(normalizedHash.matches(Regex("[a-f0-9]{64}"))) {
                "The update checksum is invalid."
            }
            val uri = URI(apkUrl)
            require(
                uri.scheme == "https" &&
                    uri.host.equals("github.com", ignoreCase = true) &&
                    uri.path.startsWith(releasePath, ignoreCase = true),
            ) { "The update download is not an OpenFlow GitHub release." }
            require(
                (channel == "stable" && versionName.matches(Regex("^\\d+\\.\\d+\\.\\d+$"))) ||
                    (channel == "testing" && versionName.contains("-testing.")),
            ) { "The update version does not belong to its channel." }
            return AndroidUpdateManifest(
                channel = channel,
                versionName = versionName,
                versionCode = versionCode,
                apkUrl = apkUrl,
                sha256 = normalizedHash,
            )
        }
    }
}

object UpdateClient {
    private const val stableManifest =
        "https://github.com/MusicMaster4/OpenFlow-Mobile/releases/latest/download/android-update.json"
    private const val testingManifest =
        "https://github.com/MusicMaster4/OpenFlow-Mobile/releases/download/channel-testing/android-update-beta.json"

    fun manifestUrl(channel: String): String =
        if (channel == "testing") testingManifest else stableManifest

    fun fetch(channel: String): AndroidUpdateManifest {
        val connection = URL(manifestUrl(channel)).openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 12_000
            connection.readTimeout = 12_000
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("User-Agent", "OpenFlow/${BuildConfig.VERSION_NAME}")
            val status = connection.responseCode
            if (status !in 200..299) error("GitHub returned HTTP $status.")
            val raw = connection.inputStream.bufferedReader().use { it.readText() }
            AndroidUpdateManifest.fromJson(raw).also {
                require(it.channel == channel) { "The update belongs to a different channel." }
            }
        } finally {
            connection.disconnect()
        }
    }
}

class AppUpdater(private val context: Context) {
    private val preferences = context.getSharedPreferences("openflow-updater", Context.MODE_PRIVATE)

    fun download(
        manifest: AndroidUpdateManifest,
        onProgress: (received: Long, total: Long) -> Unit,
    ) {
        val target = updateFile()
        val temporary = File(target.parentFile, "${target.name}.part")
        target.delete()
        temporary.delete()

        val connection = URL(manifest.apkUrl).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("Accept", "application/vnd.android.package-archive")
            connection.setRequestProperty("User-Agent", "OpenFlow/${BuildConfig.VERSION_NAME}")
            val status = connection.responseCode
            if (status !in 200..299) error("GitHub returned HTTP $status while downloading.")
            val total = connection.contentLengthLong.coerceAtLeast(0L)
            var received = 0L
            connection.inputStream.use { input ->
                FileOutputStream(temporary).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        received += count
                        onProgress(received, total)
                    }
                    output.fd.sync()
                }
            }
        } catch (error: Throwable) {
            temporary.delete()
            throw error
        } finally {
            connection.disconnect()
        }

        if (!temporary.sha256().equals(manifest.sha256, ignoreCase = true)) {
            temporary.delete()
            error("The downloaded APK failed verification and was removed.")
        }
        if (!temporary.renameTo(target)) {
            temporary.delete()
            error("The verified APK could not be prepared for installation.")
        }
        preferences.edit().putString(KEY_MANIFEST, manifest.toJson()).apply()
    }

    fun pendingManifest(): AndroidUpdateManifest? = preferences.getString(KEY_MANIFEST, null)
        ?.let { runCatching { AndroidUpdateManifest.fromJson(it) }.getOrNull() }

    fun clearIfInstalled(installedVersionCode: Long) {
        val pending = pendingManifest() ?: return
        if (pending.versionCode <= installedVersionCode) {
            updateFile().delete()
            clearPending()
        }
    }

    fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()

    fun requestInstallPermission(): Intent = Intent(
        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
        Uri.parse("package:${context.packageName}"),
    )

    fun installVerified() {
        val manifest = pendingManifest() ?: error("No verified update is ready.")
        val file = updateFile()
        require(file.isFile && file.sha256().equals(manifest.sha256, ignoreCase = true)) {
            "The update needs to be downloaded again."
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        context.startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, APK_MIME)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    }

    fun clearPending() {
        preferences.edit().remove(KEY_MANIFEST).apply()
    }

    private fun updateFile(): File {
        val directory = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: error("External app storage is unavailable.")
        return File(directory, UPDATE_FILE)
    }

    private fun File.sha256(): String {
        val digest = MessageDigest.getInstance("SHA-256")
        inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    companion object {
        private const val APK_MIME = "application/vnd.android.package-archive"
        private const val UPDATE_FILE = "openflow-update.apk"
        private const val KEY_MANIFEST = "manifest"
    }
}
