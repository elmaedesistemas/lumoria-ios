import SwiftUI

/// The near side of the Moon with a light on each site, joined in mission order.
/// This is the brand symbol drawn from data; the positions are the real ones.
struct MoonDisk: View {
    let sites: [LandingSite]
    var selectedID: String?
    /// Lights are tappable when set.
    var onSelect: ((LandingSite) -> Void)?

    @State private var visibleCount = 0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let points = sites.map { point(for: $0, center: center, radius: radius) }
            let light = radius * 0.05

            ZStack {
                Canvas { ctx, _ in
                    ctx.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                    width: radius * 2, height: radius * 2)),
                             with: .color(.regolith))
                    ctx.fill(maria(center: center, radius: radius), with: .color(.regolithShade))

                    // The trail joins only the six Apollo lights: that's the brand symbol.
                    var trail = Path()
                    trail.addLines(zip(sites, points).prefix(visibleCount).filter { $0.0.isCrewed }.map(\.1))
                    ctx.stroke(trail, with: .color(.dust),
                               style: StrokeStyle(lineWidth: max(1, radius / 90), dash: [radius / 45, radius / 36]))

                    for (site, p) in zip(sites, points).prefix(visibleCount) {
                        let isSelected = site.id == selectedID
                        let base = site.isCrewed ? light : light * 0.55
                        let dot = isSelected ? base * 1.4 : base
                        let halo = light * 2.2
                        if site.isCrewed {
                            ctx.fill(Path(ellipseIn: CGRect(x: p.x - halo, y: p.y - halo, width: halo * 2, height: halo * 2)),
                                     with: .color(.signal.opacity(0.18)))
                        }
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)),
                                 with: .color(.signal))
                        if isSelected {
                            // Selected: a signal ring just outside the halo.
                            let ring = halo + 3
                            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)),
                                       with: .color(.signal), lineWidth: 2.5)
                        }
                    }
                }

                if let onSelect {
                    ForEach(Array(sites.enumerated()), id: \.element.id) { index, site in
                        Button { onSelect(site) } label: {
                            Circle().fill(.clear).contentShape(Circle())
                        }
                        .frame(width: 32, height: 32)
                        .position(points[index])
                        .accessibilityLabel("\(site.mission), \(site.region.current)")
                        .opacity(index < visibleCount ? 1 : 0)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: sites.map(\.id)) {
            // Lights appear one by one in mission order, ~120 ms apart.
            visibleCount = 0
            for i in sites.indices {
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeOut(duration: 0.25)) { visibleCount = i + 1 }
            }
        }
    }

    private func point(for site: LandingSite, center: CGPoint, radius: CGFloat) -> CGPoint {
        let p = site.diskPoint
        return CGPoint(x: center.x + p.x * radius, y: center.y - p.y * radius)
    }

    /// The three maria from lumoria-symbol.svg (viewBox 400, disc r180 at 200,200).
    private func maria(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 90, y: 140))
        path.addCurve(to: CGPoint(x: 180, y: 155), control1: CGPoint(x: 120, y: 110), control2: CGPoint(x: 170, y: 120))
        path.addCurve(to: CGPoint(x: 115, y: 190), control1: CGPoint(x: 190, y: 190), control2: CGPoint(x: 145, y: 202))
        path.addCurve(to: CGPoint(x: 90, y: 140), control1: CGPoint(x: 90, y: 180), control2: CGPoint(x: 75, y: 160))
        path.closeSubpath()
        path.move(to: CGPoint(x: 230, y: 160))
        path.addCurve(to: CGPoint(x: 315, y: 205), control1: CGPoint(x: 270, y: 145), control2: CGPoint(x: 320, y: 165))
        path.addCurve(to: CGPoint(x: 240, y: 235), control1: CGPoint(x: 310, y: 240), control2: CGPoint(x: 270, y: 250))
        path.addCurve(to: CGPoint(x: 230, y: 160), control1: CGPoint(x: 215, y: 222), control2: CGPoint(x: 208, y: 175))
        path.closeSubpath()
        path.move(to: CGPoint(x: 160, y: 240))
        path.addCurve(to: CGPoint(x: 208, y: 270), control1: CGPoint(x: 185, y: 230), control2: CGPoint(x: 215, y: 245))
        path.addCurve(to: CGPoint(x: 158, y: 278), control1: CGPoint(x: 202, y: 290), control2: CGPoint(x: 172, y: 292))
        path.addCurve(to: CGPoint(x: 160, y: 240), control1: CGPoint(x: 145, y: 265), control2: CGPoint(x: 145, y: 246))
        path.closeSubpath()
        let scale = radius / 180
        return path.applying(
            CGAffineTransform(translationX: center.x - 200 * scale, y: center.y - 200 * scale)
                .scaledBy(x: scale, y: scale)
        )
    }
}
