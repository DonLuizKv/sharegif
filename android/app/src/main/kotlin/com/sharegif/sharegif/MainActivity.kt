package com.sharegif.sharegif

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private val worker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sharegif/whatsapp")
            .setMethodCallHandler { call, result ->
                if (call.method != "addPack") { result.notImplemented(); return@setMethodCallHandler }
                if (pending != null) { result.error("busy", "Ya hay una importación en curso.", null); return@setMethodCallHandler }
                val id = call.argument<String>("id")
                val name = call.argument<String>("name")
                val tray = call.argument<String>("tray")
                val stickers = call.argument<List<String>>("stickers")
                val version = call.argument<String>("version")
                val animated = call.argument<Boolean>("animated") ?: true
                if (id == null || name == null || tray == null || stickers == null || version == null) {
                    result.error("invalid", "El paquete está incompleto.", null); return@setMethodCallHandler
                }
                val target = listOf("com.whatsapp", "com.whatsapp.w4b").firstOrNull {
                    packageManager.getLaunchIntentForPackage(it) != null
                }
                if (target == null) {
                    result.error("missing", "Instala WhatsApp para añadir tus stickers.", null); return@setMethodCallHandler
                }
                pending = result
                worker.execute {
                    try {
                        StickerStore.publish(applicationContext, id, name, tray, stickers, version, animated)
                        runOnUiThread {
                            try {
                                val intent = Intent("com.whatsapp.intent.action.ENABLE_STICKER_PACK")
                                    .setPackage(target)
                                    .putExtra("sticker_pack_id", id)
                                    .putExtra("sticker_pack_authority", "$packageName.stickers")
                                    .putExtra("sticker_pack_name", name)
                                @Suppress("DEPRECATION")
                                startActivityForResult(intent, 601)
                            } catch (_: Exception) { finishWithError("No pudimos abrir WhatsApp. Comprueba que esté actualizado.") }
                        }
                    } catch (_: Exception) { runOnUiThread { finishWithError("No pudimos preparar el paquete. Comprueba tus archivos y el espacio disponible.") } }
                }
            }
    }

    private fun finishWithError(message: String) {
        pending?.error("export", message, null)
        pending = null
    }

    @Deprecated("Used by WhatsApp's sticker import contract")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 601) return
        if (resultCode == Activity.RESULT_OK) { pending?.success(null); pending = null }
        else finishWithError(data?.getStringExtra("validation_error") ?: "No se añadió el paquete. Puedes volver a intentarlo cuando quieras.")
    }
}
