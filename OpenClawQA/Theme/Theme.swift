import SwiftUI

// MARK: - Color Theme (matches dark mockup exactly)
enum AppColors {
    // Backgrounds
    static let windowBackground = Color(hex: "0D1117")
    static let sidebarBackground = Color(hex: "0D1117")
    static let cardBackground = Color(hex: "161B22")
    static let cardBackgroundHover = Color(hex: "1C2128")
    static let inputBackground = Color(hex: "21262D")
    static let selectedBackground = Color(hex: "1F6FEB").opacity(0.15)

    // Borders
    static let border = Color(hex: "30363D")
    static let borderSubtle = Color(hex: "21262D")

    // Text
    static let textPrimary = Color(hex: "E6EDF3")
    static let textSecondary = Color(hex: "8B949E")
    static let textTertiary = Color(hex: "484F58")

    // Accent / Brand
    static let accentBlue = Color(hex: "58A6FF")
    static let accentPurple = Color(hex: "A371F7")
    static let brandGreen = Color(hex: "3FB950")

    // Severity
    static let critical = Color(hex: "F85149")
    static let high = Color(hex: "D29922")
    static let medium = Color(hex: "E3B341")
    static let low = Color(hex: "3FB950")
    static let info = Color(hex: "58A6FF")

    // Status
    static let success = Color(hex: "3FB950")
    static let warning = Color(hex: "D29922")
    static let error = Color(hex: "F85149")
    static let running = Color(hex: "58A6FF")
    static let pending = Color(hex: "8B949E")

    // Charts
    static let chartGreen = Color(hex: "3FB950")
    static let chartRed = Color(hex: "F85149")
    static let chartOrange = Color(hex: "D29922")
    static let chartBlue = Color(hex: "58A6FF")
    static let chartPurple = Color(hex: "A371F7")

    // Sidebar
    static let sidebarSelected = Color(hex: "1F6FEB")
    static let sidebarHover = Color(hex: "161B22")
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography
enum AppFont {
    static func title(_ size: CGFloat = 24) -> Font { .system(size: size, weight: .bold) }
    static func heading(_ size: CGFloat = 18) -> Font { .system(size: size, weight: .semibold) }
    static func subheading(_ size: CGFloat = 14) -> Font { .system(size: size, weight: .medium) }
    static func body(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .regular) }
    static func caption(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .regular) }
    static func mono(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .regular, design: .monospaced) }
    static func statValue(_ size: CGFloat = 36) -> Font { .system(size: size, weight: .bold) }
}

// MARK: - Spacing
enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Card Style Modifier
struct CardStyle: ViewModifier {
    var padding: CGFloat = AppSpacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppColors.cardBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.border, lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle(padding: CGFloat = AppSpacing.lg) -> some View {
        modifier(CardStyle(padding: padding))
    }
}
