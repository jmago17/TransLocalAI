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
}
