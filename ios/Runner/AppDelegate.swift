import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ShareGifWhatsApp") else { return }
    let channel = FlutterMethodChannel(name: "sharegif/whatsapp", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "addPack" else { result(FlutterMethodNotImplemented); return }
      guard let args = call.arguments as? [String: Any],
            let id = args["id"] as? String, let name = args["name"] as? String,
            let tray = args["tray"] as? String, let paths = args["stickers"] as? [String],
            (3...30).contains(paths.count), !name.isEmpty, name.count <= 128 else {
        result(FlutterError(code: "invalid", message: "El paquete está incompleto.", details: nil)); return
      }
      let url = URL(string: "whatsapp://stickerPack")!
      guard UIApplication.shared.canOpenURL(url) else {
        result(FlutterError(code: "missing", message: "Instala WhatsApp para añadir tus stickers.", details: nil)); return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          func readLocal(_ path: String, limit: Int) throws -> Data {
            let file = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            guard file.path.hasPrefix(NSHomeDirectory() + "/") else { throw CocoaError(.fileReadNoPermission) }
            let data = try Data(contentsOf: file)
            guard !data.isEmpty && data.count <= limit else { throw CocoaError(.fileReadCorruptFile) }
            return data
          }
          let trayData = try readLocal(tray, limit: 50 * 1024)
          let stickers: [[String: Any]] = try paths.map { path in
            ["image_data": try readLocal(path, limit: 500 * 1024).base64EncodedString(), "emojis": [] as [String]]
          }
          let payload: [String: Any] = ["identifier": id, "name": name, "publisher": "ShareGIF", "animated_sticker_pack": true, "tray_image": trayData.base64EncodedString(), "stickers": stickers]
          let data = try JSONSerialization.data(withJSONObject: payload)
          DispatchQueue.main.async {
            UIPasteboard.general.setItems([["net.whatsapp.third-party.sticker-pack": data]], options: [.localOnly: true, .expirationDate: Date(timeIntervalSinceNow: 60)])
            UIApplication.shared.open(url, options: [:]) { opened in
              if opened { result(nil) }
              else { result(FlutterError(code: "open", message: "No pudimos abrir WhatsApp.", details: nil)) }
            }
          }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "files", message: "No pudimos leer los archivos del paquete.", details: nil)) }
        }
      }
    }
  }
}
