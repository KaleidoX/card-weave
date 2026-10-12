package io.cardweave.app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract as C
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Read-only, user-triggered access. Never writes contacts or logs their contents. */
class SystemContacts(private val activity: Activity, private val channel: MethodChannel) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var permissionResult: MethodChannel.Result? = null
    private var closed = false
    private val preferences = activity.getSharedPreferences("contacts_permission", 0)

    init { channel.setMethodCallHandler(::handle) }

    private fun granted() = activity.checkSelfPermission(Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED
    private fun permissionState(): String = when {
        granted() -> "granted"
        preferences.getBoolean("asked", false) && !activity.shouldShowRequestPermissionRationale(Manifest.permission.READ_CONTACTS) -> "blocked"
        else -> "denied"
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "manufacturer" -> result.success(android.os.Build.MANUFACTURER)
            "permission" -> result.success(permissionState())
            "requestPermission" -> {
                if (granted()) result.success("granted")
                else if (permissionResult != null) result.error("busy", "Permission request pending", null)
                else {
                    permissionResult = result
                    preferences.edit().putBoolean("asked", true).apply()
                    activity.requestPermissions(arrayOf(Manifest.permission.READ_CONTACTS), REQUEST)
                }
            }
            "openSettings" -> {
                activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")))
                result.success(null)
            }
            "page" -> query(result) { page(call.argument<String>("after")?.toLongOrNull() ?: 0L) }
            "detail" -> query(result) {
                val id = call.argument<String>("id")?.toLongOrNull() ?: throw IllegalArgumentException()
                val additional = call.argument<List<String>>("additionalMimeTypes") ?: emptyList()
                require(additional.size <= 64 && additional.all { it.length <= 256 && it.startsWith("vnd.") })
                detail(id, additional.toSet())
            }
            else -> result.notImplemented()
        }
    }

    fun onPermissionResult(request: Int): Boolean {
        if (request != REQUEST) return false
        permissionResult?.success(permissionState())
        permissionResult = null
        return true
    }

    private fun query(result: MethodChannel.Result, block: () -> Any) {
        worker.execute {
            try {
                if (!granted()) throw SecurityException()
                val value = block()
                main.post { if (!closed) result.success(value) }
            } catch (_: SecurityException) {
                main.post { if (!closed) result.error("permission", "Contacts permission required", null) }
            } catch (_: Exception) {
                main.post { if (!closed) result.error("read_failed", "Unable to read contacts", null) }
            }
        }
    }

    private fun page(after: Long): List<Map<String, String>> {
        val rows = mutableListOf<Map<String, String>>()
        activity.contentResolver.query(
            C.Contacts.CONTENT_URI, arrayOf(C.Contacts._ID, C.Contacts.DISPLAY_NAME_PRIMARY),
            "${C.Contacts._ID} > ?", arrayOf(after.toString()), "${C.Contacts._ID} ASC"
        )?.use { cursor ->
            while (rows.size < 50 && cursor.moveToNext()) {
                rows.add(mapOf("id" to cursor.getString(0), "name" to (cursor.getString(1) ?: "")))
            }
        } ?: throw IllegalStateException()
        return rows
    }

    private fun detail(id: Long, additionalMimeTypes: Set<String>): Map<String, Any> {
        val rows = mutableListOf<Map<String, String>>()
        var bytes = 0
        var oversized = false
        val projection = arrayOf(C.Data.MIMETYPE, C.Data.DATA1, C.Data.DATA2, C.Data.DATA3, C.Data.DATA4,
            C.Data.DATA5, C.Data.DATA6, C.Data.DATA7, C.Data.DATA8, C.Data.DATA9, C.Data.DATA10, C.Data.DATA11, C.Data.DATA12, C.Data.DATA13, C.Data.DATA14)
        activity.contentResolver.query(C.Data.CONTENT_URI, projection, "${C.Data.CONTACT_ID} = ?",
            arrayOf(id.toString()), "${C.Data.IS_SUPER_PRIMARY} DESC, ${C.Data.IS_PRIMARY} DESC, ${C.Data._ID} ASC")?.use { cursor ->
            while (cursor.moveToNext()) {
                val mime = cursor.getString(0) ?: continue
                // Photos are binary; unsupported MIME rows are reported without transferring payloads.
                val row = mutableMapOf("mime" to mime)
                if (mime in SUPPORTED || (mime in additionalMimeTypes && mime != C.CommonDataKinds.Photo.CONTENT_ITEM_TYPE)) {
                    for (i in 1..14) {
                        if (cursor.getType(i) == android.database.Cursor.FIELD_TYPE_BLOB) continue
                        val value = cursor.getString(i) ?: continue
                        bytes += value.toByteArray(Charsets.UTF_8).size
                        if (bytes > 131072) { oversized = true; break }
                        row["data$i"] = value
                    }
                    row["label"] = label(mime, row["data2"]?.toIntOrNull() ?: 0, row["data3"])
                }
                if (oversized || rows.size >= 256) { oversized = true; break }
                rows.add(row)
            }
        } ?: throw IllegalStateException()
        return mapOf("rows" to rows, "oversized" to oversized, "missing" to (rows.isEmpty() && !oversized))
    }

    private fun label(mime: String, type: Int, custom: String?): String {
        val r = activity.resources
        return when (mime) {
            C.CommonDataKinds.Phone.CONTENT_ITEM_TYPE -> C.CommonDataKinds.Phone.getTypeLabel(r, type, custom)
            C.CommonDataKinds.Email.CONTENT_ITEM_TYPE -> C.CommonDataKinds.Email.getTypeLabel(r, type, custom)
            C.CommonDataKinds.StructuredPostal.CONTENT_ITEM_TYPE -> C.CommonDataKinds.StructuredPostal.getTypeLabel(r, type, custom)
            C.CommonDataKinds.Relation.CONTENT_ITEM_TYPE -> C.CommonDataKinds.Relation.getTypeLabel(r, type, custom)
            C.CommonDataKinds.Event.CONTENT_ITEM_TYPE -> C.CommonDataKinds.Event.getTypeLabel(r, type, custom)
            else -> custom ?: "其他"
        }.toString()
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        permissionResult?.error("cancelled", "Activity closed", null)
        permissionResult = null
        worker.shutdownNow()
    }

    companion object {
        const val REQUEST = 4701
        private val SUPPORTED = setOf(
            C.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE, C.CommonDataKinds.Nickname.CONTENT_ITEM_TYPE,
            C.CommonDataKinds.Phone.CONTENT_ITEM_TYPE, C.CommonDataKinds.Email.CONTENT_ITEM_TYPE,
            C.CommonDataKinds.Organization.CONTENT_ITEM_TYPE, C.CommonDataKinds.StructuredPostal.CONTENT_ITEM_TYPE,
            C.CommonDataKinds.Im.CONTENT_ITEM_TYPE, C.CommonDataKinds.Website.CONTENT_ITEM_TYPE,
            C.CommonDataKinds.Note.CONTENT_ITEM_TYPE, C.CommonDataKinds.Relation.CONTENT_ITEM_TYPE,
            C.CommonDataKinds.Event.CONTENT_ITEM_TYPE)
    }
}
