//
//  RecordTabView.swift
//  Transcriber
//
//  Landing screen for the Grabar tab. Hosts the existing RecordingView as a
//  sheet and surfaces the in-progress recording bar. The "send to Mac after
//  recording" flow is wired in a later phase.
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
                Text("Graba una reunión")
                    .font(.title2.bold())
                Text("Graba aquí y luego transcribe en el dispositivo o envíala al Mac para generar el acta.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button {
                    showingRecorder = true
                } label: {
                    Label(recorder.isRecording ? "Ver grabación" : "Empezar a grabar",
                          systemImage: "record.circle")
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                Spacer()
            }
            .navigationTitle("Grabar")
            .sheet(isPresented: $showingRecorder) {
                RecordingView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}
