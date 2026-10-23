import SwiftUI
import UIKit

// Tokens from the Lumoria design system (project/tokens.json).
// Night (dark) is the app's default theme; Day values are kept for parity.

extension Color {
    private static func token(night: UInt32, day: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .light ? UIColor(hex: day) : UIColor(hex: night) })
    }

    static let space = token(night: 0x0B0C0E, day: 0xF4F1EA)
    static let surface = token(night: 0x17181B, day: 0xECE8DF)
    static let surfaceRaised = token(night: 0x222327, day: 0xFFFFFF)
    static let line = token(night: 0x3A3B40, day: 0xCFC9BC)
    static let ink = token(night: 0xECE8DF, day: 0x111214)
    static let inkMuted = token(night: 0xA39E91, day: 0x5E5A50)
    static let regolith = token(night: 0xD9D4C7, day: 0xD9D4C7)
    static let regolithShade = token(night: 0xC9C3B4, day: 0xC9C3B4)
    static let dust = token(night: 0x7E796D, day: 0x7E796D)
    static let signal = token(night: 0xFF6B1A, day: 0xFF6B1A)
    static let onSignal = token(night: 0x0B0C0E, day: 0x0B0C0E)
    static let signalText = token(night: 0xFF8A4C, day: 0xB8420B)
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum Spacing {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s12: CGFloat = 48
    static let s16: CGFloat = 64
}

enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 12
    static let lg: CGFloat = 24
}

/// Text styles: Archivo for what you read, IBM Plex Mono for what you measure.
enum TextStyle {
    case wordmark, title, heading, body, bodySmall, bodyStrong, label, coordinate

    var font: Font {
        switch self {
        case .wordmark: .custom("Archivo-ExtraBold", fixedSize: 34)
        case .title: .custom("Archivo-ExtraBold", size: 48, relativeTo: .largeTitle)
        case .heading: .custom("Archivo-ExtraBold", size: 28, relativeTo: .title)
        case .body: .custom("Archivo-Medium", size: 17, relativeTo: .body)
        case .bodySmall: .custom("Archivo-Medium", size: 15, relativeTo: .subheadline)
        case .bodyStrong: .custom("Archivo-ExtraBold", size: 15, relativeTo: .subheadline)
        case .label: .custom("IBMPlexMono-Medium", size: 13, relativeTo: .caption)
        case .coordinate: .custom("IBMPlexMono-Medium", size: 15, relativeTo: .subheadline)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .wordmark: 6
        case .label: 3
        default: 0
        }
    }

    /// Extra space between lines to reach the token's line height.
    var lineSpacing: CGFloat {
        switch self {
        case .body: 9
        case .bodySmall, .bodyStrong: 7
        default: 0
        }
    }

    var uppercased: Bool { self == .wordmark || self == .label }
}

extension Text {
    func style(_ style: TextStyle) -> some View {
        self.font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
            .textCase(style.uppercased ? .uppercase : nil)
    }
}

/// UI copy in both languages, chosen like `Localized.current`.
func tr(_ en: String, _ es: String) -> String {
    Localized(en: en, es: es).current
}
