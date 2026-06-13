//
//  ActasNotifications.swift
//  Transcriber
//
//  Local notifications when a submitted audio reaches a terminal pipeline stage
//  (acta ready / error). This complements the Mac's own brrr push: it fires
//  while the app is active/observing, with no APNs infrastructure needed.
//
//  A lock-screen Live Activity was considered but rejected: the pipeline runs
//  for minutes on the Mac, so without an APNs push server the activity would go
//  stale on the lock screen. A completion notification is more honest and robust.
//

import Foundation
import UserNotifications

enum ActasNotifications {
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    static func notifyDone(name: String) {
        post(id: "actas-done-\(name)",
             title: "Acta lista",
             body: "«\(name)» ya está en Apple Notes.")
    }

    static func notifyError(name: String) {
        post(id: "actas-error-\(name)",
             title: "Error en el acta",
             body: "El pipeline marcó «\(name)» como error. Revisa la app.")
    }

    private static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
