import Flutter
import UIKit
import UniformTypeIdentifiers

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BauSpurOrdner") {
      OrdnerPlugin.register(with: registrar)
    }
  }
}

/// Projektordner (z. B. im OneDrive) einmal wählen und dauerhaft merken
/// (Security-Scoped Bookmark). Lesen und Schreiben über NSFileCoordinator,
/// damit Dateien von OneDrive & Co. bei Bedarf geladen werden.
class OrdnerPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private var wartend: FlutterResult?
  private let schluessel = "bauspurOrdnerLesezeichen"

  static func register(with registrar: FlutterPluginRegistrar) {
    let kanal = FlutterMethodChannel(name: "bauspur/ordner", binaryMessenger: registrar.messenger())
    let instanz = OrdnerPlugin()
    registrar.addMethodCallDelegate(instanz, channel: kanal)
  }

  private func ordner() -> URL? {
    guard let daten = UserDefaults.standard.data(forKey: schluessel) else { return nil }
    var veraltet = false
    guard let url = try? URL(resolvingBookmarkData: daten, options: [], relativeTo: nil, bookmarkDataIsStale: &veraltet) else { return nil }
    if veraltet, url.startAccessingSecurityScopedResource() {
      if let neu = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
        UserDefaults.standard.set(neu, forKey: schluessel)
      }
      url.stopAccessingSecurityScopedResource()
    }
    return url
  }

  private func mitZugriff<T>(_ url: URL, _ arbeit: () -> T) -> T {
    let ok = url.startAccessingSecurityScopedResource()
    defer { if ok { url.stopAccessingSecurityScopedResource() } }
    return arbeit()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "waehlen":
      let auswahl = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
      auswahl.delegate = self
      auswahl.allowsMultipleSelection = false
      wartend = result
      oberstes()?.present(auswahl, animated: true)
    case "name":
      result(ordner()?.lastPathComponent)
    case "lesen":
      guard let basis = ordner(), let pfad = args["pfad"] as? String else { result(nil); return }
      // im Hintergrund, weil das Nachladen aus iCloud einige Sekunden dauern kann
      DispatchQueue.global(qos: .userInitiated).async {
        let daten: Data? = self.mitZugriff(basis) {
          let ziel = basis.appendingPathComponent(pfad)
          self.ausICloudLaden(ziel)
          var aus: Data?
          var fehler: NSError?
          NSFileCoordinator().coordinate(readingItemAt: ziel, options: [], error: &fehler) { url in
            aus = try? Data(contentsOf: url)
          }
          return aus
        }
        DispatchQueue.main.async { result(daten.map { FlutterStandardTypedData(bytes: $0) }) }
      }
    case "schreiben":
      guard let basis = ordner(), let pfad = args["pfad"] as? String, let inhalt = args["daten"] as? FlutterStandardTypedData else {
        result(false); return
      }
      let ok: Bool = mitZugriff(basis) {
        var erfolg = false
        var fehler: NSError?
        let ziel = basis.appendingPathComponent(pfad)
        NSFileCoordinator().coordinate(writingItemAt: ziel, options: .forReplacing, error: &fehler) { url in
          do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try inhalt.data.write(to: url, options: .atomic)
            erfolg = true
          } catch {
            erfolg = false
          }
        }
        return erfolg && fehler == nil
      }
      result(ok)
    case "liste":
      guard let basis = ordner() else { result([String]()); return }
      let pfad = args["pfad"] as? String ?? ""
      let namen: [String] = mitZugriff(basis) {
        (try? FileManager.default.contentsOfDirectory(atPath: basis.appendingPathComponent(pfad).path)) ?? []
      }
      result(namen)
    case "info":
      // Diagnose: was sieht die App im Ordner (inkl. noch nicht geladener iCloud-Platzhalter)?
      guard let basis = ordner() else { result("kein Ordner gewählt"); return }
      let text: String = mitZugriff(basis) {
        let fm = FileManager.default
        var zeilen = ["Ordner: \(basis.path)"]
        for unter in ["", "planstand", "eingang"] {
          let inhalt = (try? fm.contentsOfDirectory(atPath: basis.appendingPathComponent(unter).path)) ?? []
          zeilen.append("\(unter.isEmpty ? "/" : unter): \(inhalt.isEmpty ? "(leer oder nicht lesbar)" : inhalt.joined(separator: ", "))")
        }
        return zeilen.joined(separator: "\n")
      }
      result(text)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { wartend?(nil); wartend = nil; return }
    let ok = url.startAccessingSecurityScopedResource()
    defer { if ok { url.stopAccessingSecurityScopedResource() } }
    if let daten = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
      UserDefaults.standard.set(daten, forKey: schluessel)
      wartend?(url.lastPathComponent)
    } else {
      wartend?(nil)
    }
    wartend = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    wartend?(nil)
    wartend = nil
  }

  /// iCloud legt nicht geladene Dateien als Platzhalter „.name.icloud“ ab:
  /// Laden anstoßen und bis zu 20 s warten, bis die Datei da ist.
  private func ausICloudLaden(_ url: URL) {
    let fm = FileManager.default
    let platzhalter = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
    let istUbiquitaer = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) ?? false
    if fm.fileExists(atPath: url.path) && !istUbiquitaer { return }
    try? fm.startDownloadingUbiquitousItem(at: url)
    for _ in 0..<40 {
      if let s = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus, s == .current {
        return
      }
      if fm.fileExists(atPath: url.path) && !fm.fileExists(atPath: platzhalter.path) && !istUbiquitaer { return }
      Thread.sleep(forTimeInterval: 0.5)
    }
  }

  private func oberstes() -> UIViewController? {
    let fenster = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var vc = fenster?.rootViewController
    while let p = vc?.presentedViewController { vc = p }
    return vc
  }
}
