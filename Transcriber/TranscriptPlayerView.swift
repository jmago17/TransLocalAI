import SwiftUI
import AVFoundation
import Combine

/// Follow-along view: the transcript as timestamped blocks, with the audio
/// playing alongside. The block under the playhead is highlighted and kept
/// in view; tapping a block seeks the audio there. Also works without audio
/// as a "jump to position" reader (e.g. from Suspicious Words).
struct TranscriptPlayerView: View {

    struct Block: Identifiable {
        let id: Int
        let time: TimeInterval?
        let timestampLabel: String?
        let text: String
    }

    let title: String
    let blocks: [Block]
    let audioURL: URL?
    /// Word/phrase to locate on appear (scrolls to and marks its block).
    var locateText: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var rate: Float = 1.0
    @State private var followPlayback = true
    @State private var locatedBlockID: Int?
    @State private var isScrubbing = false

    init(title: String, transcriptText: String, audioURL: URL?, locateText: String? = nil) {
        self.title = title
        self.blocks = Self.parseBlocks(from: transcriptText)
        self.audioURL = audioURL
        self.locateText = locateText
    }

    private var currentBlockID: Int? {
        guard player != nil else { return nil }
        return blocks.last(where: { ($0.time ?? 0) <= currentTime + 0.05 })?.id ?? blocks.first?.id
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(blocks) { block in
                            blockRow(block)
                                .id(block.id)
                        }
                    }
                    .padding()
                    .padding(.bottom, audioURL != nil ? 120 : 0)
                }
                .onChange(of: currentBlockID) { _, newValue in
                    guard followPlayback, isPlaying, let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .onAppear {
                    setUpPlayer()
                    locateIfNeeded(proxy: proxy)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if audioURL != nil {
                    playerBar
                }
            }
            .liquidCrystalScreen()
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if audioURL != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            followPlayback.toggle()
                        } label: {
                            Label(
                                followPlayback ? "Following" : "Follow off",
                                systemImage: followPlayback ? "text.line.first.and.arrowtriangle.forward" : "text.justify"
                            )
                        }
                        .tint(followPlayback ? .accentColor : .secondary)
                    }
                }
            }
            .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
                guard let player, isPlaying, !isScrubbing else { return }
                currentTime = player.currentTime
                if !player.isPlaying {  // reached the end
                    isPlaying = false
                }
            }
            .onDisappear {
                player?.stop()
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func blockRow(_ block: Block) -> some View {
        let isCurrent = block.id == currentBlockID && isPlaying
        let isLocated = block.id == locatedBlockID

        Button {
            if let time = block.time, let player {
                player.currentTime = time
                currentTime = time
                if !isPlaying { togglePlayback() }
            }
            locatedBlockID = nil
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let label = block.timestampLabel {
                    Text(label)
                        .font(.caption.monospacedDigit().weight(isCurrent ? .bold : .regular))
                        .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                        .frame(minWidth: 44, alignment: .trailing)
                }
                Text(block.text)
                    .font(.body)
                    .foregroundStyle(isCurrent ? .primary : (isPlaying ? .secondary : .primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isCurrent
                          ? Color.accentColor.opacity(0.18)
                          : isLocated ? Color.orange.opacity(0.22) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Player bar

    private var playerBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text(Self.format(currentTime))
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
                Text(Self.format(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 28) {
                Menu {
                    ForEach([Float(1.0), 1.25, 1.5, 2.0], id: \.self) { value in
                        Button {
                            rate = value
                            if isPlaying { player?.rate = value }
                        } label: {
                            if rate == value {
                                Label(Self.rateLabel(value), systemImage: "checkmark")
                            } else {
                                Text(Self.rateLabel(value))
                            }
                        }
                    }
                } label: {
                    Text(Self.rateLabel(rate))
                        .font(.footnote.weight(.semibold))
                        .frame(minWidth: 44)
                }

                Button {
                    skip(-15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }

                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                }

                Button {
                    skip(15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }

                // Balances the rate menu so the play button stays centered.
                Color.clear.frame(minWidth: 44, maxWidth: 44, maxHeight: 1)
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    // MARK: - Playback

    private func setUpPlayer() {
        guard player == nil, let audioURL else { return }
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
        } catch {
            player = nil
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

    private func locateIfNeeded(proxy: ScrollViewProxy) {
        guard let locateText, !locateText.isEmpty else { return }
        let needle = locateText.lowercased()
        guard let match = blocks.first(where: { $0.text.lowercased().contains(needle) }) else { return }
        locatedBlockID = match.id
        if let time = match.time, let player {
            player.currentTime = time
            currentTime = time
        }
        // Give the LazyVStack a beat to lay out before jumping.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo(match.id, anchor: .center)
            }
        }
    }

    // MARK: - Parsing

    /// Splits "[mm:ss] text" / "[h:mm:ss] text" transcript lines into blocks.
    /// Untimestamped lines are carried as their own blocks (no seek target).
    static func parseBlocks(from text: String) -> [Block] {
        let pattern = #/^\[(?:(\d+):)?(\d{1,2}):(\d{2})\]\s*(.*)$/#
        var blocks: [Block] = []
        for (index, line) in text.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let match = trimmed.firstMatch(of: pattern) {
                let hours = match.1.flatMap { Double($0) } ?? 0
                let minutes = Double(match.2) ?? 0
                let seconds = Double(match.3) ?? 0
                let time = hours * 3600 + minutes * 60 + seconds
                blocks.append(Block(
                    id: index,
                    time: time,
                    timestampLabel: Self.format(time),
                    text: String(match.4)
                ))
            } else {
                blocks.append(Block(id: index, time: nil, timestampLabel: nil, text: trimmed))
            }
        }
        return blocks
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    static func rateLabel(_ value: Float) -> String {
        value == value.rounded() ? String(format: "%.0f×", value) : String(format: "%.2g×", value)
    }
}
