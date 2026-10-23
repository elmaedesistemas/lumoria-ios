import SwiftUI

// MARK: - Button

/// Primary (signal fill) for the one main action on a screen; secondary (outlined) for the rest.
struct LumoriaButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TextStyle.bodyStrong.font)
            .foregroundStyle(kind == .primary ? Color.onSignal : Color.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, Spacing.s4)
            .background {
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(kind == .primary ? Color.signal : .clear)
            }
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(Color.inkMuted, lineWidth: 1.5)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

extension ButtonStyle where Self == LumoriaButtonStyle {
    static var primary: LumoriaButtonStyle { .init(kind: .primary) }
    static var secondary: LumoriaButtonStyle { .init(kind: .secondary) }
}

// MARK: - Site marker

/// The bootprint on a signal disc (assets/Logos/lumoria-site-marker.svg), drawn natively.
struct SiteMarker: View {
    var size: CGFloat = 40
    var selected = false

    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 72
            ctx.scaleBy(x: s, y: s)
            ctx.fill(Path(ellipseIn: CGRect(x: 2, y: 2, width: 68, height: 68)), with: .color(.signal))

            ctx.translateBy(x: 36, y: 36)
            ctx.rotate(by: .degrees(-20))
            ctx.translateBy(x: -36, y: -36)
            let sole = Path(roundedRect: CGRect(x: 28, y: 12, width: 16, height: 48), cornerRadius: 8)
            ctx.fill(sole, with: .color(.onSignal))
            ctx.clip(to: sole)
            for (y, h) in [(17.0, 2.5), (22, 2.5), (27, 2.5), (32, 2.5), (38, 4), (45, 2.5), (50, 2.5)] {
                ctx.fill(Path(CGRect(x: 26, y: y, width: 20, height: h)), with: .color(.signal))
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if selected {
                Circle().stroke(Color.signal, lineWidth: 2).padding(-Spacing.s1 - 1)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Formatting

extension LandingSite {
    /// "26.132° N  3.633° E"
    var coordinateText: String {
        let lat = String(format: "%.3f° %@", abs(lat), lat >= 0 ? "N" : "S")
        let lon = String(format: "%.3f° %@", abs(lon), lon >= 0 ? "E" : "W")
        return "\(lat)  \(lon)"
    }

    /// Orthographic position on the near side, x right and y up, both in -1...1.
    var diskPoint: CGPoint {
        let φ = lat * .pi / 180, λ = lon * .pi / 180
        return CGPoint(x: cos(φ) * sin(λ), y: sin(φ))
    }
}
