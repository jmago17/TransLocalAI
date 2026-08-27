//
//  RecordTabView.swift
//  Transcriber
//
//  Record tab — same recording UI as ContentView's "New Recording" sheet,
//  embedded directly instead of behind a landing screen + extra tap.
//

import SwiftUI

struct RecordTabView: View {
    var body: some View {
        RecordingView(embedded: true)
    }
}
