//
//  NotesLinker.swift
//  Transcriber
//
//  Best-effort jump to Apple Notes, where the finished acta lives. iOS doesn't
//  expose deep links to a specific note, so we open the Notes app and copy the
//  title to the clipboard so the user can paste it into Notes' search.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum NotesLinker {
    static func open(noteTitled title: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = title
        if let url = URL(string: "mobilenotes://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
