import SwiftUI

// MARK: - Color palette

extension Color {
    /// Near-black window background
    static let cratesBg       = Color(hex: "#0A0A0A")
    /// Primary surface (sidebar, panels)
    static let cratesSurface  = Color(hex: "#111111")
    /// Elevated surface (cards, popups)
    static let cratesElevated = Color(hex: "#1C1C1C")
    /// Dividers and borders
    static let cratesBorder   = Color(hex: "#222222")
    /// Warm orange accent — stage lighting
    static let cratesAccent   = Color(hex: "#FF6500")
    /// Primary text
    static let cratesPrimary  = Color(hex: "#E8E8E8")
    /// Secondary / dim text
    static let cratesDim      = Color(hex: "#5A5A5A")
    /// Ghost text / disabled
    static let cratesGhost    = Color(hex: "#2A2A2A")
    /// Live / playing green
    static let cratesLive     = Color(hex: "#22C55E")
    /// Camelot key — violet
    static let cratesKey      = Color(hex: "#A78BFA")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1,   255,  255,  255)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Track color avatar

/// Generates a deterministic gradient for a track based on its title.
/// Used as a visual fingerprint when no album art is available.
struct TrackAvatar: View {
    let title: String
    let size: CGFloat

    private var colors: (Color, Color) {
        let palettes: [(Color, Color)] = [
            (Color(hex: "#FF6500"), Color(hex: "#FF3300")),
            (Color(hex: "#7C3AED"), Color(hex: "#4F46E5")),
            (Color(hex: "#0EA5E9"), Color(hex: "#0891B2")),
            (Color(hex: "#10B981"), Color(hex: "#059669")),
            (Color(hex: "#F59E0B"), Color(hex: "#D97706")),
            (Color(hex: "#EC4899"), Color(hex: "#BE185D")),
            (Color(hex: "#6366F1"), Color(hex: "#4338CA")),
            (Color(hex: "#14B8A6"), Color(hex: "#0F766E")),
        ]
        let hash = abs(title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        return palettes[hash % palettes.count]
    }

    var body: some View {
        LinearGradient(
            colors: [colors.0, colors.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: size, height: size)
        .overlay(
            Text(title.prefix(1).uppercased())
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
        )
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}

// MARK: - Button styles

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundColor(Color(hex: "#0A0A0A"))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.cratesAccent.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Color.cratesDim.opacity(configuration.isPressed ? 0.5 : 1))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.cratesElevated.opacity(configuration.isPressed ? 1 : 0))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
