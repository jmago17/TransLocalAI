import SwiftUI

/// Shared translucent canvas used by every screen in the app.
struct LiquidCrystalBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.purple.opacity(0.32), .clear, Color.orange.opacity(0.18)]
                    : [Color.purple.opacity(0.14), .clear, Color.orange.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.10 : 0.58), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    func liquidCrystalScreen() -> some View {
        background(LiquidCrystalBackground())
    }
}
