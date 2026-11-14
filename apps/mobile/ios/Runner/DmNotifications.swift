import Flutter
import UIKit
import UserNotifications

/// Local reminders for messages already durably received by Dart; no APNs.
final class DmNotifications {
    private let center = UNUserNotificationCenter.current()
    private let prefix = "speechful.dm."
    private let key = "speechful.dm.notificationTargets.v1"
    private var channel: FlutterMethodChannel?
    private var scope: String?
    private var bound = false
    private var revision = 0
    private var listening = false
    private var pending: [String: String]?
    private var language = "zh-Hans"
    // Only opaque routing metadata, never text, names or tokens.
    private var targets: [String: [String: String]] = [:]

    init() {
        if let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: String]] {
            targets = saved.filter { $0.key.hasPrefix(prefix) && Self.valid($0.value) }
        }
    }
    func register(_ messenger: FlutterBinaryMessenger) {
        let next = FlutterMethodChannel(name: "hnuhole/dm_notifications", binaryMessenger: messenger)
        channel = next
        next.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(false); return }
            self.handle(call, result: result)
        }
    }
    static func valid(_ target: [String: String]) -> Bool {
        guard Set(target.keys) == ["scope", "identityId", "conversationId"],
              let scope = target["scope"], let identity = target["identityId"],
              let conversation = target["conversationId"] else { return false }
        let uuid = "^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$"
        return scope.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil &&
            identity.range(of: uuid, options: .regularExpression) != nil &&
            conversation.range(of: uuid, options: .regularExpression) != nil
    }
    private func persist() { UserDefaults.standard.set(targets, forKey: key) }
    private func remove(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        ids.forEach { targets.removeValue(forKey: $0) }
        persist()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
    private func clear() {
        revision += 1
        remove(Array(targets.keys))
        // A crash can leave a delivered request whose metadata was not flushed.
        // Sweep only this channel's orphaned IDs; a newer registered request is
        // preserved even if these asynchronous enumerations complete later.
        center.getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                self.remove(requests.map { $0.identifier }.filter {
                    $0.hasPrefix(self.prefix) && self.targets[$0] == nil
                })
            }
        }
        center.getDeliveredNotifications { notifications in
            DispatchQueue.main.async {
                self.remove(notifications.map { $0.request.identifier }.filter {
                    $0.hasPrefix(self.prefix) && self.targets[$0] == nil
                })
            }
        }
    }
    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.handle(call, result: result) }; return }
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "setLanguage":
            guard let next = args["language"] as? String, ["zh-Hans", "zh-Hant", "en", "ja"].contains(next) else {
                result(Self.error); return
            }
            language = next
            result(nil)
        case "bind":
            let next = args["scope"] as? String
            if let next = next, next.range(of: "^[0-9a-f]{64}$", options: .regularExpression) == nil {
                result(Self.error); return
            }
            if !bound || scope != next { clear() }
            bound = true
            scope = next
            if let target = pending, let next = next, target["scope"] != next { pending = nil }
            result(nil)
        case "takeTap":
            listening = true
            let value = pending
            pending = nil
            result(value)
        case "permission":
            center.getNotificationSettings { settings in
                DispatchQueue.main.async { result(Self.allowed(settings)) }
            }
        case "requestPermission":
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                self.center.getNotificationSettings { settings in
                    DispatchQueue.main.async { result(Self.allowed(settings)) }
                }
            }
        case "clear": clear(); pending = nil; result(nil)
        case "retain":
            guard let owner = args["scope"] as? String, owner == scope,
                  let retained = args["targets"] as? [String] else { result(nil); return }
            let keep = Set(retained)
            remove(targets.filter { !keep.contains(Self.tag($0.value)) }.map { $0.key })
            result(nil)
        case "show": show(args, result: result)
        default: result(FlutterMethodNotImplemented)
        }
    }
    private static var error: FlutterError {
        FlutterError(code: "DM_NOTIFICATION_FAILED", message: "Notification unavailable", details: nil)
    }
    private static func tag(_ target: [String: String]) -> String {
        ["scope", "identityId", "conversationId"].map { target[$0] ?? "" }.joined(separator: ":")
    }
    private static func allowed(_ settings: UNNotificationSettings) -> Bool {
        let statuses: [UNAuthorizationStatus] = [.authorized, .provisional, .ephemeral]
        return statuses.contains(settings.authorizationStatus) && settings.alertSetting == .enabled
    }
    private var privateMessage: String {
        switch language {
        case "zh-Hant": return "你有一條新私信"
        case "en": return "You have a new direct message"
        case "ja": return "新しいダイレクトメッセージがあります"
        default: return "你有一条新私信"
        }
    }
    private func show(_ args: [String: Any], result: @escaping FlutterResult) {
        let target = args.compactMapValues { $0 as? String }.filter { ["scope", "identityId", "conversationId"].contains($0.key) }
        guard Self.valid(target), scope == target["scope"] else { result(false); return }
        let epoch = revision
        let tag = Self.tag(target)
        remove(targets.filter { Self.tag($0.value) == tag }.map { $0.key })
        if targets.count >= 256 { remove(Array(targets.keys.prefix(targets.count - 255))) }
        // Register before the first async boundary so retain/clear can invalidate
        // a permission lookup that is still in flight (mute/read/account change).
        let id = prefix + UUID().uuidString
        targets[id] = target
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                guard Self.allowed(settings), self.revision == epoch, self.scope == target["scope"], self.targets[id] != nil else {
                    self.remove([id])
                    result(false); return
                }
                // A late completion can remove only its own request, never a
                // newer notification for the same conversation after logout.
                self.persist()
                let content = UNMutableNotificationContent()
                let preview = args["preview"] as? Bool == true
                content.title = preview ? String((args["sender"] as? String ?? "SpeechFUL").prefix(80)) : "SpeechFUL"
                content.body = preview ? String(((args["text"] as? String ?? "").components(separatedBy: .newlines).first ?? "").prefix(160)) : self.privateMessage
                content.sound = .default
                content.threadIdentifier = tag
                content.userInfo = ["notificationId": id]
                self.center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
                    DispatchQueue.main.async {
                        let current = self.revision == epoch && self.scope == target["scope"] && self.targets[id] != nil
                        if error != nil || !current { self.remove([id]) }
                        result(error == nil && current)
                    }
                }
            }
        }
    }
    func owns(_ notification: UNNotification) -> Bool { notification.request.identifier.hasPrefix(prefix) }
    func presentation(_ notification: UNNotification) -> UNNotificationPresentationOptions {
        guard let target = targets[notification.request.identifier], target["scope"] == scope else { return [] }
        return [.banner, .list, .sound]
    }
    func receive(_ response: UNNotificationResponse) {
        let id = response.notification.request.identifier
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              response.notification.request.content.userInfo["notificationId"] as? String == id,
              let target = targets[id], Self.valid(target) else { return }
        remove([id])
        if bound, let scope = scope, target["scope"] != scope { return }
        if listening { channel?.invokeMethod("tap", arguments: target) }
        else { pending = target }
    }
}
