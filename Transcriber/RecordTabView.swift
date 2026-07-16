//
//  RecordTabView.swift
//  Transcriber
//
//  Landing screen for the Record tab.
//

import SwiftUI

struct RecordTabView: View {
    @State private var showingRecorder = false
    private var recorder: AudioRecorderManager { AudioRecorderManager.shared }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.red.gradient)
                Text("Record a meeting")
                    .font(.title2.bold())
                Text("Capture the conversation, then transcribe it privately on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button {
                    showingRecorder = true
                } label: {
                    Label(recorder.isRecording ? "Open Recording" : "Start Recording",
                          systemImage: "record.circle")
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                Spacer()
            }
            .liquidCrystalScreen()
            .navigationTitle("Record")
            .sheet(isPresented: $showingRecorder) {
                RecordingView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}
