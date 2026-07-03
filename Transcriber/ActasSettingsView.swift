//
//  ActasSettingsView.swift
//  Transcriber
//
//  Pairing + configuration for the Mac (actas-server): bearer token, host
//  candidates, a connection test, and the iCloud Reuniones folder used as the
//  offline fallback.
//

import SwiftUI
import UniformTypeIdentifiers

struct ActasSettingsView: View {
    @Environment(PipelineController.self) private var controller

    @State private var config = ActasServerStore.load()
    @State private var testing = false
    @State private var testResult: TestResult?
    @State private var showingFolderPicker = false
    @State private var folderConfigured = ICloudInboxBridge.isConfigured
    @State private var route = ActasServerStore.processingRoute
    @AppStorage("liquidGlassTheme") private var liquidGlassTheme = false

    enum TestResult: Equatable {
        case ok(String)      // base URL that answered
        case fail(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                routeSection
                tokenSection
                hostsSection
                testSection
                fallbackSection
                aboutSection
            }
            .navigationTitle("Ajustes")
            .onChange(of: config) { _, newValue in
                ActasServerStore.save(newValue)
            }
            .fileImporter(isPresented: $showingFolderPicker,
                          allowedContentTypes: [.folder],
                          allowsMultipleSelection: false) { result in
                handleFolderPick(result)
            }
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section {
            Toggle(isOn: $liquidGlassTheme) {
                Label("Cristal líquido (iOS 27)", systemImage: "circle.hexagongrid.fill")
            }
        } header: {
            Text("Tema")
        } footer: {
            Text("Aplica el estilo Liquid Glass de iOS 27 al fondo. Desactívalo para el tema clásico.")
        }
    }

    private var routeSection: some View {
        Section {
            Picker("Procesar con", selection: $route) {
                ForEach(ProcessingRoute.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: route) { _, v in ActasServerStore.processingRoute = v }
        } header: {
            Text("Procesamiento")
        } footer: {
            Text(route == .macApp
                 ? "Los audios se sincronizan por iCloud y los procesa la app de Mac (sin servidor ni token)."
                 : "Los audios se suben al servidor del Mac por HTTP (con respaldo iCloud).")
        }
    }

    private var tokenSection: some View {
        Section {
            SecureField("Token del servidor", text: $config.token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let pasted = pasteboardTokenSuggestion {
                Button("Pegar token del portapapeles") { config.token = pasted }
                    .font(.footnote)
            }
        } header: {
            Text("Emparejamiento")
        } footer: {
            Text("El token está en el Mac, en ~/.config/actas-server/token. Cópialo aquí para autorizar la app.")
        }
    }

    private var hostsSection: some View {
        Section("Direcciones del Mac") {
            LabeledContent("Tailscale") {
                TextField("100.x.x.x", text: $config.tailscaleHost).multilineTextAlignment(.trailing)
            }
            LabeledContent("LAN") {
                TextField("192.168.x.x", text: $config.lanHost).multilineTextAlignment(.trailing)
            }
            LabeledContent("mDNS") {
                TextField("Mac.local", text: $config.mdnsHost).multilineTextAlignment(.trailing)
            }
            LabeledContent("Puerto") {
                TextField("8776", value: $config.port, format: .number).multilineTextAlignment(.trailing)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private var testSection: some View {
        Section {
            Button {
                Task { await testConnection() }
            } label: {
                HStack {
                    Text("Probar conexión")
                    Spacer()
                    if testing { ProgressView() }
                }
            }
            .disabled(testing || config.token.isEmpty)

            if let testResult {
                switch testResult {
                case .ok(let url):
                    Label(url, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.footnote)
                case .fail(let msg):
                    Label(msg, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
    }

    private var fallbackSection: some View {
        Section {
            HStack {
                Label("Carpeta Reuniones (iCloud)", systemImage: folderConfigured ? "folder.fill.badge.checkmark" : "folder.badge.questionmark")
                    .foregroundStyle(folderConfigured ? .green : .secondary)
                Spacer()
                Button(folderConfigured ? "Cambiar" : "Elegir") { showingFolderPicker = true }
            }
            if folderConfigured {
                Button("Quitar acceso", role: .destructive) {
                    ICloudInboxBridge.clear()
                    folderConfigured = false
                }
                .font(.footnote)
            }
        } header: {
            Text("Respaldo offline")
        } footer: {
            Text("Si el Mac no responde por HTTP, los audios se dejan en esta carpeta de iCloud y el pipeline los recoge al sincronizar. Elige la carpeta «Reuniones» de tu iCloud Drive.")
        }
    }

    private var aboutSection: some View {
        Section("Estado") {
            LabeledContent("Servidor") {
                Text(controller.isReachable ? "Conectado" : "Sin conexión")
                    .foregroundStyle(controller.isReachable ? .green : .secondary)
            }
        }
    }

    // MARK: - Actions

    private var pasteboardTokenSuggestion: String? {
        #if canImport(UIKit)
        guard let s = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              s.count >= 20, s.count <= 100, !s.contains(" "),
              s != config.token else { return nil }
        return s
        #else
        return nil
        #endif
    }

    private func testConnection() async {
        testing = true
        defer { testing = false }
        ActasServerStore.save(config)
        switch await controller.testReachability() {
        case .reachable(let url): testResult = .ok(url.absoluteString)
        case .unreachable: testResult = .fail("No responde por Tailscale, LAN ni mDNS.")
        }
    }

    private func handleFolderPick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try ICloudInboxBridge.storePickedFolder(url)
                folderConfigured = true
            } catch {
                testResult = .fail("No se pudo guardar el acceso a la carpeta: \(error.localizedDescription)")
            }
        case .failure(let error):
            testResult = .fail(error.localizedDescription)
        }
    }
}
