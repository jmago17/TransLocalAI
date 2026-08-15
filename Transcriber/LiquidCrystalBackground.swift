import SwiftUI

/// Shared translucent canvas used by every screen in the app.
struct LiquidCrystalBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let diagonal = hypot(proxy.size.width, proxy.size.height)

            ZStack {
                Color(uiColor: .systemGroupedBackground)

                // One continuous 834 × 1194 pt composition on an 11-inch iPad.
                // Normalized centers keep the same balance in either orientation.
                RadialGradient(
                    colors: [
                        Color.purple.opacity(colorScheme == .dark ? 0.34 : 0.15),
                        .clear
                    ],
                    center: UnitPoint(x: 0.08, y: 0.04),
                    startRadius: 0,
                    endRadius: diagonal * 0.68
                )

                RadialGradient(
                    colors: [
                        Color.orange.opacity(colorScheme == .dark ? 0.22 : 0.16),
                        .clear
                    ],
                    center: UnitPoint(x: 0.94, y: 0.96),
                    startRadius: 0,
                    endRadius: diagonal * 0.64
                )

                LinearGradient(
                    colors: [Color.white.opacity(colorScheme == .dark ? 0.06 : 0.34), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Expands to fill the screen first — `background` alone sizes to the
    /// modified view, which left small floating patches behind compact content
    /// (e.g. the analysis spinner) with the rest of the sheet white.
    func liquidCrystalScreen() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LiquidCrystalBackground())
    }

    /// Lifts a list row onto a frosted card floating over the canvas.
    /// Screens get the same rhythm for free: one card per row, an even gap
    /// between them, and no separators fighting the translucency.
    func liquidCrystalRow() -> some View {
        listRowBackground(
            LiquidCrystalCard()
                .padding(.horizontal, LiquidCrystal.Layout.cardInset)
                .padding(.vertical, LiquidCrystal.Layout.cardGap)
        )
        .listRowSeparator(.hidden)
        .listRowInsets(LiquidCrystal.Layout.rowInsets)
    }

    /// Header of a card group: readable sentence case, aligned to the cards.
    func liquidCrystalSectionHeader() -> some View {
        textCase(nil)
            .listRowInsets(LiquidCrystal.Layout.headerInsets)
    }
}

// MARK: - Tokens

/// Every measurement and colour the Liquid Crystal screens share. Views read
/// from here; a literal in a view means a token is missing, not that the view
/// gets to invent one.
enum LiquidCrystal {
    enum Radius {
        /// Cards and list rows floating over the canvas.
        static let card: CGFloat = 20
        /// Inline controls sitting inside a card.
        static let control: CGFloat = 12
        /// Small inline chips, e.g. a term's aliases.
        static let chip: CGFloat = 6
    }

    enum Layout {
        /// Distance from a card's edge to the screen edge.
        static let cardInset: CGFloat = 20
        /// Half the gap between two stacked cards.
        static let cardGap: CGFloat = 4
        /// Distance from a card's edge to its content.
        static let cardPadding: CGFloat = 14
        /// Between the stacked lines of a card (title, snippet, metadata).
        static let lineSpacing: CGFloat = 4
        /// Between badges and other inline metadata.
        static let badgeSpacing: CGFloat = 6

        /// Row insets that leave `cardPadding` inside the card and `cardGap`
        /// outside it — the card background is laid out against the full row.
        static var rowInsets: EdgeInsets {
            EdgeInsets(
                top: cardGap + cardPadding,
                leading: cardInset + cardPadding,
                bottom: cardGap + cardPadding,
                trailing: cardInset + cardPadding
            )
        }

        static var headerInsets: EdgeInsets {
            EdgeInsets(top: 10, leading: cardInset + 6, bottom: 4, trailing: cardInset)
        }
    }

    /// The meaning a badge carries, not the colour it happens to use.
    enum Tone {
        case neutral
        /// Apple's own engine, links, primary affordances.
        case accent
        /// Whisper and other add-on capabilities.
        case feature
        /// Confirmed, trusted, healthy.
        case positive
        /// Needs a look: suggested, approaching a limit.
        case attention

        /// `nil` keeps the badge on the neutral fill hierarchy.
        var tint: Color? {
            switch self {
            case .neutral: return nil
            case .accent: return .accentColor
            case .feature: return .purple
            case .positive: return .green
            case .attention: return .orange
            }
        }
    }

    /// Shared by the in-app recording bar and the recording Live Activity.
    static let recordingAccent = Color.red
    /// How strongly a tone fills the shape behind a badge.
    static let toneFillOpacity: Double = 0.16
    /// Hairline that gives a frosted card its lit top edge.
    static let cardHighlight = Color.white.opacity(0.18)
}

/// The frosted card every list row sits on.
struct LiquidCrystalCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: LiquidCrystal.Radius.card, style: .continuous)
            .fill(.thinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: LiquidCrystal.Radius.card, style: .continuous)
                    .strokeBorder(LiquidCrystal.cardHighlight, lineWidth: 0.5)
            }
    }
}

/// The app's one badge: engine, language, terminology state. It always carries
/// its text — an icon on its own is decoration, and the reader has to guess.
struct CrystalBadge: View {
    let text: String
    var systemImage: String?
    var tone: LiquidCrystal.Tone = .neutral

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tone.tint ?? .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            if let tint = tone.tint {
                Capsule().fill(tint.opacity(LiquidCrystal.toneFillOpacity))
            } else {
                Capsule().fill(.quaternary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
