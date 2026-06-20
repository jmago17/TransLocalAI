//
//  MacViewsStubs.swift
//  TranscriberMac
//
//  Placeholder views for the menu bar popover, main window, and settings.
//  Fleshed out in the UI phase.
//

import SwiftUI

struct MenuBarContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TransLocalAI").font(.headline)
            Text("Inactivo").font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("Abrir ventana") {}
            Button("Salir") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 280)
    }
}

struct MacMainView: View {
    var body: some View {
        Text("Panel")
            .frame(minWidth: 640, minHeight: 460)
    }
}

struct MacSettingsView: View {
    var body: some View {
        Text("Ajustes")
            .frame(width: 480, height: 320)
            .padding()
    }
}
