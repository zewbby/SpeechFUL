import Flutter
import Photos
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// PHPicker supplies only explicitly selected assets. Never decode through
/// UIImage: doing so would rewrite GIF timing, EXIF and the original digest.
public final class NativeMediaPlugin: NSObject, FlutterPlugin, PHPickerViewControllerDelegate {
    private let registrar: FlutterPluginRegistrar
    private var selection: FlutterResult?
    private var picker: PHPickerViewController?
    private var files: [String: URL] = [:]
    private var lengths: [String: Int] = [:]
    private var generation = UUID()
    private let io = DispatchQueue(label: "speechful.media.io")
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("speechful-media-" + UUID().uuidString)

    private init(_ registrar: FlutterPluginRegistrar) { self.registrar = registrar; super.init() }
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "speechful/native_media", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(NativeMediaPlugin(registrar), channel: channel)
    }
    private static func error(_ code: String) -> FlutterError {
        FlutterError(code: code, message: "Photo operation unavailable or incomplete", details: nil)
    }
    private var presenter: UIViewController? {
        var view = registrar.viewController ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
        while let next = view?.presentedViewController { view = next }
        return view
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.handle(call, result: result) }; return }
        switch call.method {
        case "pick":
            guard selection == nil else { result(Self.error("MEDIA_BUSY")); return }
            guard let args = call.arguments as? [String: Any], let limit = args["limit"] as? Int,
                  (1...9).contains(limit), let view = presenter, view.viewIfLoaded?.window != nil else {
                result(Self.error("MEDIA_UNAVAILABLE")); return
            }
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = limit
            config.selection = .ordered
            config.preferredAssetRepresentationMode = .current
            let controller = PHPickerViewController(configuration: config)
            controller.delegate = self
            selection = result
            picker = controller
            view.present(controller, animated: true)
        case "read":
            guard let id = call.arguments as? String, let file = files.removeValue(forKey: id),
                  let length = lengths.removeValue(forKey: id) else { result(Self.error("MEDIA_EXPIRED")); return }
            io.async {
                defer { try? FileManager.default.removeItem(at: file) }
                do {
                    let bytes = try Data(contentsOf: file)
                    guard bytes.count == length, bytes.count <= 10 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
                    DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: bytes)) }
                } catch { DispatchQueue.main.async { result(Self.error("MEDIA_READ_FAILED")) } }
            }
        case "release":
            if let id = call.arguments as? String { release(id) }
            result(nil)
        case "hasAccess": result(Self.hasAccess)
        case "requestAccess":
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                DispatchQueue.main.async { result(status == .authorized || status == .limited) }
            }
        case "putImage": save(call.arguments, result: result)
        default: result(FlutterMethodNotImplemented)
        }
    }
    private static var hasAccess: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        return status == .authorized || status == .limited
    }
    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard picker === self.picker, let completion = selection else { return }
        self.picker = nil
        let lease = generation
        picker.dismiss(animated: true) {
            // An unavailable iCloud download must not permanently lock picking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
                guard let self = self, self.generation == lease, self.selection != nil else { return }
                self.generation = UUID()
                self.selection = nil
                Array(self.files.keys).forEach(self.release)
                completion(Self.error("MEDIA_READ_FAILED"))
            }
            self.load(results, at: 0, selected: [], lease: lease, completion: completion)
        }
    }
    // Sequential file copying bounds peak memory and retains selection order.
    private func load(_ results: [PHPickerResult], at index: Int, selected: [[String: Any]],
                      lease: UUID, completion: @escaping FlutterResult) {
        guard generation == lease else { return }
        guard index < results.count else { selection = nil; generation = UUID(); completion(selected); return }
        let provider = results[index].itemProvider
        guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
            load(results, at: index + 1, selected: selected + [["id": UUID().uuidString, "length": 0]],
                 lease: lease, completion: completion); return
        }
        let id = UUID().uuidString
        let destination = root.appendingPathComponent(id)
        // Copy inside this callback: the provider removes its file on return.
        provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
            var count: Int?
            do {
                guard error == nil, let url = url else { throw CocoaError(.fileReadUnknown) }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                if (1...(10 * 1024 * 1024)).contains(size) {
                    try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: destination)
                }
                count = size
            } catch { try? FileManager.default.removeItem(at: destination) }
            let size = count
            DispatchQueue.main.async {
                guard self.generation == lease else { try? FileManager.default.removeItem(at: destination); return }
                let length = size ?? 0
                if (1...(10 * 1024 * 1024)).contains(length) {
                    self.files[id] = destination
                    self.lengths[id] = length
                }
                // Abandoned selections (logout, navigation, rejected size) are
                // never restored into another account and cannot accumulate.
                DispatchQueue.main.asyncAfter(deadline: .now() + 600) { [weak self] in self?.release(id) }
                self.load(results, at: index + 1, selected: selected + [["id": id, "length": length]],
                          lease: lease, completion: completion)
            }
        }
    }
    private func release(_ id: String) {
        lengths.removeValue(forKey: id)
        if let file = files.removeValue(forKey: id) { io.async { try? FileManager.default.removeItem(at: file) } }
    }
    private func save(_ argument: Any?, result: @escaping FlutterResult) {
        guard Self.hasAccess else { result(Self.error("MEDIA_ACCESS_DENIED")); return }
        guard let path = argument as? String, path.hasPrefix("/"),
              ["png", "jpg", "jpeg", "gif", "webp"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else {
            result(Self.error("MEDIA_UNSUPPORTED")); return
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path + "/"
        guard url.path.hasPrefix(home), let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 16 * 1024 * 1024 else { result(Self.error("MEDIA_INVALID_SOURCE")); return }
        PHPhotoLibrary.shared().performChanges({
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: options)
        }) { success, error in
            DispatchQueue.main.async {
                if success { result(nil) }
                else {
                    let native = error as NSError?
                    let code: String
                    if native?.domain == PHPhotosErrorDomain && native?.code == PHPhotosError.Code.invalidResource.rawValue {
                        code = "MEDIA_UNSUPPORTED"
                    } else if native?.domain == PHPhotosErrorDomain && native?.code == PHPhotosError.Code.notEnoughSpace.rawValue {
                        code = "MEDIA_NO_SPACE"
                    } else { code = "MEDIA_SAVE_UNKNOWN" }
                    result(Self.error(code))
                }
            }
        }
    }
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        generation = UUID()
        picker?.dismiss(animated: false)
        picker = nil
        selection?(Self.error("MEDIA_UNAVAILABLE"))
        selection = nil
        Array(files.keys).forEach(release)
        let directory = root
        io.async { try? FileManager.default.removeItem(at: directory) }
    }
}
