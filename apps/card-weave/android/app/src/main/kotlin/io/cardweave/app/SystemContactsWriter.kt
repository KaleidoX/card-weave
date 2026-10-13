package io.cardweave.app

import android.app.Activity
import android.content.ContentProviderOperation as Op
import android.content.ContentUris
import android.os.Build
import android.provider.ContactsContract as C
import org.json.JSONObject

/** Device-local associations are never part of the replicated address book. */
class SystemContactsWriter(private val activity: Activity) {
    private val resolver get() = activity.contentResolver
    private val links = activity.getSharedPreferences("system_contact_links_v1", 0)

    fun link(key: String): String? = links.getString(key, null)
    fun saveLink(key: String, value: String?) {
        require(key.length <= 256)
        val edit = links.edit()
        if (value == null) edit.remove(key) else {
            require(value.length <= 1048576)
            JSONObject(value)
            edit.putString(key, value)
        }
        check(edit.commit())
    }

    fun accounts(): List<Map<String, String?>> {
        val result = mutableListOf<Map<String, String?>>(mapOf(
            "name" to if (Build.VERSION.SDK_INT >= 30) C.RawContacts.getLocalAccountName(activity) else null,
            "type" to if (Build.VERSION.SDK_INT >= 30) C.RawContacts.getLocalAccountType(activity) else null))
        resolver.query(C.RawContacts.CONTENT_URI, arrayOf(C.RawContacts.ACCOUNT_NAME, C.RawContacts.ACCOUNT_TYPE),
            "${C.RawContacts.DELETED}=0 AND ${C.RawContacts.RAW_CONTACT_IS_READ_ONLY}=0", null, null)?.use { c ->
            while (c.moveToNext()) {
                val item = mapOf("name" to c.getString(0), "type" to c.getString(1))
                if (item !in result) result.add(item)
            }
        }
        return result
    }

    fun targets(contactId: String): List<Map<String, Any?>> {
        val ids = mutableListOf<String>()
        resolver.query(C.RawContacts.CONTENT_URI, arrayOf(C.RawContacts._ID),
            "${C.RawContacts.CONTACT_ID}=? AND ${C.RawContacts.DELETED}=0", arrayOf(contactId), null)?.use { c ->
            while (c.moveToNext()) ids.add(c.getString(0))
        }
        return ids.map { snapshot(it) }
    }

    fun snapshot(rawId: String): Map<String, Any?> {
        val raw = mutableMapOf<String, Any?>()
        resolver.query(C.RawContacts.CONTENT_URI, arrayOf(C.RawContacts._ID, C.RawContacts.CONTACT_ID,
            C.RawContacts.VERSION, C.RawContacts.ACCOUNT_NAME, C.RawContacts.ACCOUNT_TYPE),
            "${C.RawContacts._ID}=? AND ${C.RawContacts.DELETED}=0", arrayOf(rawId), null)?.use { c ->
            if (c.moveToFirst()) {
                raw["rawId"] = c.getString(0); raw["contactId"] = c.getString(1)
                raw["version"] = c.getString(2); raw["accountName"] = c.getString(3)
                raw["accountType"] = c.getString(4)
                raw["writable"] = false
            }
        }
        check(raw.isNotEmpty()) { "missing" }
        // Older providers allow read-only predicates but reject these columns in projections.
        resolver.query(C.RawContacts.CONTENT_URI, arrayOf(C.RawContacts._ID),
            "${C.RawContacts._ID}=? AND ${C.RawContacts.RAW_CONTACT_IS_READ_ONLY}=0",
            arrayOf(rawId), null)?.use { raw["writable"] = it.moveToFirst() }
        val writableData = mutableSetOf<String>()
        resolver.query(C.Data.CONTENT_URI, arrayOf(C.Data._ID),
            "${C.Data.RAW_CONTACT_ID}=? AND ${C.Data.IS_READ_ONLY}=0",
            arrayOf(rawId), null)?.use { c -> while(c.moveToNext()) writableData.add(c.getString(0)) }

        resolver.query(C.Contacts.CONTENT_URI, arrayOf(C.Contacts.LOOKUP_KEY),
            "${C.Contacts._ID}=?", arrayOf(raw["contactId"].toString()), null)?.use { c ->
            check(c.moveToFirst()); raw["lookup"] = c.getString(0)
        }
        val rows = mutableListOf<Map<String, Any?>>()
        val columns = arrayOf(C.Data._ID, C.Data.MIMETYPE, *(1..15).map { "data$it" }.toTypedArray())
        var bytes = 0
        resolver.query(C.Data.CONTENT_URI, columns, "${C.Data.RAW_CONTACT_ID}=?", arrayOf(rawId),
            "${C.Data._ID} ASC")?.use { c ->
            while (c.moveToNext()) {
                val row = mutableMapOf<String, Any?>("id" to c.getString(0), "mime" to c.getString(1), "readonly" to (c.getString(0) !in writableData))
                row["opaque"] = !c.isNull(16) || (2 until 16).any {
                    c.getType(it) == android.database.Cursor.FIELD_TYPE_BLOB
                }
                // Unknown and binary rows remain in the provider; patches never replace them.
                for (i in 2 until 16) if (!c.isNull(i) && c.getType(i) != android.database.Cursor.FIELD_TYPE_BLOB) {
                    val value = c.getString(i)
                    bytes += value.toByteArray().size
                    check(bytes <= 262144 && rows.size < 512) { "oversized" }
                    row[columns[i]] = value
                }
                rows.add(row)
            }
        }
        raw["rows"] = rows
        return raw
    }

    fun recover(token: String): Map<String, Any?>? {
        resolver.query(C.Data.CONTENT_URI, arrayOf(C.Data.RAW_CONTACT_ID),
            "${C.Data.MIMETYPE}=? AND ${C.Data.DATA1}=?", arrayOf(MARKER, token), null)?.use { c ->
            if (c.moveToFirst()) return snapshot(c.getString(0))
        }
        return null
    }

    fun write(request: Map<String, Any?>): Map<String, Any?> {
        val token = request["token"] as String
        require(token.matches(Regex("[a-zA-Z0-9-]{16,80}")))
        recover(token)?.let { return it }
        val rawId = request["rawId"] as String?
        val ops = arrayListOf<Op>()
        if (rawId != null) {
            val current = snapshot(rawId)
            check(current["writable"] == true) { "readonly" }
            check(current["lookup"] == request["lookup"] &&
                current["accountName"] == request["accountName"] &&
                current["accountType"] == request["accountType"]) { "identity_changed" }
            ops.add(Op.newAssertQuery(C.RawContacts.CONTENT_URI)
                .withSelection("${C.RawContacts._ID}=? AND ${C.RawContacts.VERSION}=? AND ${C.RawContacts.DELETED}=0 AND ${C.RawContacts.RAW_CONTACT_IS_READ_ONLY}=0",
                    arrayOf(rawId, request["version"].toString())).withExpectedCount(1).build())
        } else {
            val account = mapOf("name" to request["accountName"], "type" to request["accountType"])
            require(accounts().any { it["name"] == account["name"] && it["type"] == account["type"] })
            ops.add(Op.newInsert(C.RawContacts.CONTENT_URI)
                .withValue(C.RawContacts.ACCOUNT_NAME, account["name"])
                .withValue(C.RawContacts.ACCOUNT_TYPE, account["type"]).build())
        }
        @Suppress("UNCHECKED_CAST")
        val patches = request["patches"] as List<Map<String, Any?>>
        require(patches.size <= 256)
        for (patch in patches) {
            val id = patch["id"] as String?
            val mime = patch["mime"] as String
            require(mime in WRITABLE)
            val delete = patch["delete"] == true
            require(rawId != null || (id == null && !delete))
            val builder = if (id != null) {
                (if (delete) Op.newDelete(C.Data.CONTENT_URI) else Op.newUpdate(C.Data.CONTENT_URI))
                    .withSelection("${C.Data._ID}=? AND ${C.Data.RAW_CONTACT_ID}=? AND ${C.Data.MIMETYPE}=? AND ${C.Data.IS_READ_ONLY}=0",
                        arrayOf(id, rawId, mime)).withExpectedCount(1)
            } else {
                require(!delete)
                Op.newInsert(C.Data.CONTENT_URI).withValue(C.Data.MIMETYPE, mime).apply {
                    if (rawId == null) withValueBackReference(C.Data.RAW_CONTACT_ID, 0)
                    else withValue(C.Data.RAW_CONTACT_ID, rawId)
                }
            }
            if (!delete) {
                @Suppress("UNCHECKED_CAST")
                val values = patch["values"] as Map<String, Any?>
                require(values.keys.all { it.matches(Regex("data([1-9]|1[0-4])")) })
                for ((key, value) in values) builder.withValue(key, value)
            }
            ops.add(builder.build())
        }
        val marker = Op.newInsert(C.Data.CONTENT_URI).withValue(C.Data.MIMETYPE, MARKER).withValue(C.Data.DATA1, token)
        if (rawId == null) marker.withValueBackReference(C.Data.RAW_CONTACT_ID, 0)
        else {
            ops.add(Op.newDelete(C.Data.CONTENT_URI).withSelection(
                "${C.Data.RAW_CONTACT_ID}=? AND ${C.Data.MIMETYPE}=?", arrayOf(rawId, MARKER)).build())
            marker.withValue(C.Data.RAW_CONTACT_ID, rawId)
        }
        ops.add(marker.build())
        val result = resolver.applyBatch(C.AUTHORITY, ops)
        return snapshot(rawId ?: ContentUris.parseId(result[0].uri!!).toString())
    }

    companion object {
        const val MARKER = "vnd.io.cardweave.write-token"
        val WRITABLE = setOf("name", "nickname", "phone_v2", "email_v2", "organization",
            "postal-address_v2", "im", "website", "note", "relation", "contact_event")
            .map { "vnd.android.cursor.item/$it" }.toSet()
    }
}
