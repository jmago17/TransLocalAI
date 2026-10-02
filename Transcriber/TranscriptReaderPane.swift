import SwiftUI
import AVFoundation
import Combine
#if os(iOS)
import UIKit
#endif

enum TranscriptReader {
    /// Comfortable measure for body text; the rest of the width stays margin.
    /// Shared by the reading column and the floating player so they line up.
    static let readingWidth: CGFloat = 760
}

/// The iPad reading surface for a transcript: the text is the page, and the
/// player floats over the bottom edge so it survives scrolling.
///
/// Blocks, timestamp labels and speed labels come from `TranscriptPlayerView`,
/// which is the one place that knows how `[mm:ss]` marks are written. That also
/// means the timestamp column, the playhead highlight and tap-to-seek only
/// appear for transcripts that actually carry those marks — with a plain
/// transcript this degrades to a single readable column.
struct TranscriptReaderPane<Header: View>: View {
    private let blocks: [TranscriptPlayerView.Block]
    private let audioURL: URL?
    private let onReplaceAndSave: (String) -> Void
    private let header: Header

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var rate: Float = 1.0
    @State private var isScrubbing = false

    init(
        text: String,
        audioURL: URL?,
        onReplaceAndSave: @escaping (String) -> Void,
        @ViewBuilder header: () -> Header
    ) {
        self.blocks = TranscriptPlayerView.parseBlocks(from: text)
        self.audioURL = audioURL
        self.onReplaceAndSave = onReplaceAndSave
        self.header = header()
    }

    private var hasTimings: Bool { blocks.contains { $0.time != nil } }

    /// `nil` unless there is a real playhead to point at: highlighting a block
    /// without loaded audio or without timings would be made up.
    private var currentBlockID: Int? {
        guard player != nil, hasTimings else { return nil }
        return blocks.last(where: { ($0.time ?? 0) <= currentTime + 0.05 })?.id ?? blocks.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if blocks.isEmpty {
                        Text("No transcript yet")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(blocks) { block in
                                blockRow(block).id(block.id)
                            }
                        }
                    }
                }
                .frame(maxWidth: TranscriptReader.readingWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
            .onChange(of: currentBlockID) { _, newValue in
                guard isPlaying, !isScrubbing, let newValue else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            // On the ScrollView itself, not on the reader: only there does the
            // inset become scroll content inset, so the last block clears the
            // player instead of hiding under it.
            .safeAreaInset(edge: .bottom) {
                if audioURL != nil {
                    playerBar
                }
            }
        }
        .onAppear { setUpPlayer() }
        .onDisappear { player?.stop() }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            guard let player, isPlaying, !isScrubbing else { return }
            currentTime = player.currentTime
            if !player.isPlaying {  // reached the end
                isPlaying = false
            }
        }
    }

    // MARK: - Blocks

    @ViewBuilder
    private func blockRow(_ block: TranscriptPlayerView.Block) -> some View {
        let isCurrent = block.id == currentBlockID && isPlaying

        HStack(alignment: .top, spacing: 12) {
            if let label = block.timestampLabel {
                timestampButton(label: label, time: block.time, isCurrent: isCurrent)
            }
            blockText(block.text)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: LiquidCrystal.Radius.control, style: .continuous)
                    .fill(Color.accentColor.opacity(LiquidCrystal.toneFillOpacity))
            }
        }
        .overlay(alignment: .leading) {
            // Playhead marker: an accent bar sliding block to block makes the
            // progression readable at a glance, as in the player sheet.
            if isCurrent {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isCurrent)
    }

    private func timestampButton(label: String, time: TimeInterval?, isCurrent: Bool) -> some View {
        Button {
            seek(to: time)
        } label: {
            Text(label)
                .font(.caption2.monospacedDigit().weight(isCurrent ? .bold : .regular))
                .foregroundStyle(isCurrent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background {
                    if isCurrent {
                        Capsule().fill(Color.accentColor.opacity(LiquidCrystal.toneFillOpacity))
                    } else {
                        Capsule().fill(.quaternary)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(time == nil || player == nil)
        .accessibilityLabel(Text("Jump to \(label)"))
    }

    @ViewBuilder
    private func blockText(_ text: String) -> some View {
        #if os(iOS)
        // Keeps the "Replace & Save" selection menu the phone layout offers.
        SelectableTranscriptView(text: text, onReplaceAndSave: onReplaceAndSave)
            .frame(maxWidth: .infinity, alignment: .leading)
        #else
        Text(text)
            .textSelection(.enabled)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    // MARK: - Player

    private var playerBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                scrubber
                transportControls
            }
            VStack(spacing: 8) {
                scrubber
                transportControls
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background {
            Capsule(style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(LiquidCrystal.cardHighlight, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
        .frame(maxWidth: TranscriptReader.readingWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var scrubber: some View {
        HStack(spacing: 10) {
            Text(TranscriptPlayerView.format(currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { currentTime },
                    set: { newValue in
                        currentTime = newValue
                        player?.currentTime = newValue
                    }
                ),
                in: 0...max(duration, 1)
            ) { editing in
                isScrubbing = editing
            }
            .accessibilityLabel("Playback position")
            Text(TranscriptPlayerView.format(duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 18) {
            Button {
                skip(-15)
            } label: {
                Image(systemName: "gobackward.15").font(.title3)
            }
            .accessibilityLabel("Skip back 15 seconds")

            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 38))
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button {
                skip(15)
            } label: {
                Image(systemName: "goforward.15").font(.title3)
            }
            .accessibilityLabel("Skip forward 15 seconds")

            Menu {
                ForEach([Float(1.0), 1.25, 1.5, 2.0], id: \.self) { value in
                    Button {
                        rate = value
                        if isPlaying { player?.rate = value }
                    } label: {
                        if rate == value {
                            Label(TranscriptPlayerView.rateLabel(value), systemImage: "checkmark")
                        } else {
                            Text(TranscriptPlayerView.rateLabel(value))
                        }
                    }
                }
            } label: {
                Text(TranscriptPlayerView.rateLabel(rate))
                    .font(.footnote.weight(.semibold))
                    .frame(minWidth: 36)
            }
            .accessibilityLabel("Playback speed")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    @discardableResult
    private func setUpPlayer() -> AVAudioPlayer? {
        if let player { return player }
        guard let audioURL else { return nil }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let newPlayer = try AVAudioPlayer(contentsOf: audioURL)
            newPlayer.enableRate = true
            newPlayer.prepareToPlay()
            player = newPlayer
            duration = newPlayer.duration
            return newPlayer
        } catch {
            player = nil
            return nil
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.rate = rate
            player.play()
            isPlaying = true
        }
    }

    private func skip(_ seconds: TimeInterval) {
        guard let player else { return }
        let target = min(max(0, player.currentTime + seconds), duration)
        player.currentTime = target
        currentTime = target
    }

    private func seek(to time: TimeInterval?) {
        guard let time, let player else { return }
        let target = min(max(0, time), player.duration)
        player.currentTime = target
        currentTime = target
        if !isPlaying { togglePlayback() }
    }
}
