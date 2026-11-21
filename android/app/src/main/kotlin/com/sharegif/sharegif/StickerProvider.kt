package com.sharegif.sharegif

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import java.security.MessageDigest

/** Immutable asset snapshots and an atomic manifest keep provider reads consistent. */
internal object StickerStore {
    fun root(context: Context) = File(context.filesDir, "whatsapp_packs").apply { mkdirs() }
    @Synchronized fun read(context: Context): JSONObject {
        val file = AtomicFile(File(root(context), "packs.json"))
        return try { JSONObject(file.openRead().bufferedReader().use { it.readText() }) }
        catch (_: FileNotFoundException) { JSONObject() }
    }

    @Synchronized fun publish(context: Context, id: String, name: String, tray: String, stickers: List<String>, version: String, animated: Boolean) {
        require(id.matches(Regex("[a-zA-Z0-9_]+")) && id.length <= 128)
        require(name.isNotBlank() && name.length <= 128 && stickers.size in 3..30)
        val digest = MessageDigest.getInstance("SHA-256").digest("$version:$animated".toByteArray()).take(12).joinToString("") { "%02x".format(it) }
        val directory = File(root(context), "${id}_$digest").apply { mkdirs() }
        fun checkedSource(path: String): File {
            val file = File(path).canonicalFile
            require(file.path.startsWith(File(context.applicationInfo.dataDir).canonicalPath + File.separator))
            require(file.isFile)
            return file
        }
        val icon = checkedSource(tray)
        require(icon.length() in 1..(50 * 1024L))
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(icon.path, bounds)
        require(bounds.outWidth == 96 && bounds.outHeight == 96)
        val iconTarget = File(directory, "tray.png")
        if (!iconTarget.exists()) icon.copyTo(iconTarget)
        val entries = JSONArray()
        stickers.forEachIndexed { index, path ->
            val source = checkedSource(path)
            require(source.length() in 1..((if (animated) 500 else 100) * 1024L))
            val filename = "$index.webp"
            val target = File(directory, filename)
            if (!target.exists()) source.copyTo(target)
            entries.put(filename)
        }
        val manifest = read(context)
        manifest.put(id, JSONObject().put("name", name).put("directory", directory.name).put("animated", animated).put("version", digest).put("stickers", entries))
        val atomic = AtomicFile(File(root(context), "packs.json"))
        val output = atomic.startWrite()
        try { output.write(manifest.toString().toByteArray()); atomic.finishWrite(output) }
        catch (error: Exception) { atomic.failWrite(output); throw error }
        context.contentResolver.notifyChange(Uri.parse("content://${context.packageName}.stickers/metadata"), null)
    }
}

class StickerProvider : ContentProvider() {
    override fun onCreate() = true
    private val metadataColumns = arrayOf("sticker_pack_identifier", "sticker_pack_name", "sticker_pack_publisher", "sticker_pack_icon", "android_play_store_link", "ios_app_download_link", "sticker_pack_publisher_email", "sticker_pack_publisher_website", "sticker_pack_privacy_policy_website", "sticker_pack_license_agreement_website", "image_data_version", "whatsapp_will_not_cache_stickers", "animated_sticker_pack")

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
        val ctx = requireNotNull(context)
        require(uri.authority == "${ctx.packageName}.stickers")
        val segments = uri.pathSegments
        val manifest = StickerStore.read(ctx)
        if (segments.size in 1..2 && segments[0] == "metadata") {
            val cursor = MatrixCursor(metadataColumns)
            for (id in manifest.keys()) {
                if (segments.size == 2 && segments[1] != id) continue
                val pack = manifest.getJSONObject(id)
                cursor.addRow(arrayOf<Any>(id, pack.getString("name"), "ShareGIF", "tray.png", "", "", "", "", "", "", pack.getString("version"), 0, if (pack.optBoolean("animated", true)) 1 else 0))
            }
            cursor.setNotificationUri(ctx.contentResolver, uri)
            return cursor
        }
        if (segments.size == 2 && segments[0] == "stickers") {
            val cursor = MatrixCursor(arrayOf("sticker_file_name", "sticker_emoji", "sticker_accessibility_text"))
            val stickers = manifest.optJSONObject(segments[1])?.getJSONArray("stickers")
            if (stickers != null) for (index in 0 until stickers.length()) cursor.addRow(arrayOf(stickers.getString(index), "", ""))
            cursor.setNotificationUri(ctx.contentResolver, uri)
            return cursor
        }
        throw IllegalArgumentException("Unknown sticker URI")
    }

    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Read only")
        val ctx = requireNotNull(context)
        val parts = uri.pathSegments
        if (uri.authority != "${ctx.packageName}.stickers" || parts.size != 3 || parts[0] != "stickers_asset") throw FileNotFoundException()
        val pack = StickerStore.read(ctx).optJSONObject(parts[1]) ?: throw FileNotFoundException()
        val files = pack.getJSONArray("stickers")
        val allowed = parts[2] == "tray.png" || (0 until files.length()).any { files.getString(it) == parts[2] }
        if (!allowed) throw FileNotFoundException()
        val root = StickerStore.root(ctx).canonicalFile
        val file = File(File(root, pack.getString("directory")), parts[2]).canonicalFile
        if (!file.path.startsWith(root.path + File.separator) || !file.isFile) throw FileNotFoundException()
        return AssetFileDescriptor(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY), 0, file.length())
    }

    override fun getType(uri: Uri): String {
        val parts = uri.pathSegments
        return when {
            parts.size == 3 && parts[0] == "stickers_asset" -> if (parts[2] == "tray.png") "image/png" else "image/webp"
            parts.size == 1 && parts[0] == "metadata" -> "vnd.android.cursor.dir/vnd.${uri.authority}.metadata"
            parts.size == 2 && parts[0] == "metadata" -> "vnd.android.cursor.item/vnd.${uri.authority}.metadata"
            parts.size == 2 && parts[0] == "stickers" -> "vnd.android.cursor.dir/vnd.${uri.authority}.stickers"
            else -> throw IllegalArgumentException("Unknown sticker URI")
        }
    }
    override fun insert(uri: Uri, values: ContentValues?): Uri = throw UnsupportedOperationException("Read only")
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException("Read only")
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException("Read only")
}
