import SwiftUI

/// Sky mode, first step: where the real Moon is from here, which way to point,
/// and the disk as you'd see it now, with each site lit or in shadow.
struct SkyView: View {
    @Environment(SitesStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var sensors = SkySensors()
    @State private var selectedID: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            let place = sensors.location
            let sky = SkyModel.snapshot(
                at: context.date,
                latitude: place?.coordinate.latitude ?? SkyModel.sanJose.latitude,
                longitude: place?.coordinate.longitude ?? SkyModel.sanJose.longitude,
                height: place?.altitude ?? SkyModel.sanJose.height,
                sites: store.sites
            )
            content(sky: sky, placeName: place == nil ? "San José" : tr("Your location", "Tu ubicación"))
        }
        .background(Color.space.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { sensors.start() }
        .onDisappear { sensors.stop() }
        .sheet(item: Binding(get: { store.site(id: selectedID) }, set: { selectedID = $0?.id })) { site in
            StoryCardView(site: site)
                .presentationDetents([.medium, .large])
                .presentationBackground(Color.surface)
                .presentationCornerRadius(Radius.lg)
        }
    }

    private func content(sky: SkySnapshot, placeName: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                HStack {
                    CircleButton(systemName: "chevron.left", label: tr("Back", "Atrás")) { dismiss() }
                    Spacer()
                    Text("\(tr("Sky", "Cielo")) · \(placeName)")
                        .style(.label)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, Spacing.s3)
                        .frame(height: 32)
                        .background(Color.surface, in: Capsule())
                }

                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text(sky.isUp ? tr("The Moon is up", "La Luna está arriba") : tr("The Moon is below the horizon", "La Luna está bajo el horizonte"))
                        .style(.display)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(positionLine(sky)).style(.coordinate).foregroundStyle(Color.inkMuted)
                }

                SkyMoonDisk(sky: sky, sites: store.sites, selectedID: selectedID) { selectedID = $0.id }
                    .frame(maxWidth: 300)
                    .frame(maxWidth: .infinity)

                if sky.isUp {
                    finder(sky: sky)
                    NavigationLink(value: Route.skyCamera) {
                        Text(tr("See it through the camera", "Verla en la cámara"))
                    }
                    .buttonStyle(.primary)
                }

                facts(sky: sky)
                siteList(sky: sky)
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.bottom, Spacing.s8)
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func finder(sky: SkySnapshot) -> some View {
        if let az = sensors.cameraAzimuth, let el = sensors.cameraElevation {
            let turn = wrap180(sky.azimuth - az)
            let tilt = sky.altitude - el
            let onTarget = abs(turn) < 6 && abs(tilt) < 6
            HStack(spacing: Spacing.s4) {
                Image(systemName: onTarget ? "scope" : "location.north.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.signal)
                    .rotationEffect(.degrees(onTarget ? 0 : atan2(turn, tilt) * 180 / .pi))
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(onTarget ? tr("The Moon is in front of you", "La Luna está frente a ti") : guidance(turn: turn, tilt: tilt))
                        .font(TextStyle.bodyStrong.font).foregroundStyle(Color.ink)
                    Text(tr("Hold the phone up, back camera to the sky.", "Sostén el teléfono con la cámara trasera hacia el cielo."))
                        .style(.bodySmall).foregroundStyle(Color.inkMuted)
                }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(onTarget ? Color.signal : Color.line))
        }
    }

    private func facts(sky: SkySnapshot) -> some View {
        VStack(spacing: 0) {
            fact(tr("Lit", "Iluminada"), "\(Int((sky.illuminatedFraction * 100).rounded()))%")
            fact(tr("Rises", "Sale"), time(sky.moonrise))
            fact(tr("Sets", "Se pone"), time(sky.moonset))
            fact(tr("North tilt", "Giro del norte"), String(format: "%.0f°", sky.northFromUp))
            Rectangle().fill(Color.line).frame(height: 1)
        }
    }

    private func siteList(sky: SkySnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(tr("Daylight at each site now", "Luz del día en cada sitio ahora"))
                .style(.label).foregroundStyle(Color.inkMuted)
            ForEach(store.sites) { site in
                let sun = sky.siteSunElevation[site.id] ?? -90
                Button { selectedID = site.id } label: {
                    HStack {
                        Circle()
                            .strokeBorder(Color.signal, lineWidth: 2)
                            .background(Circle().fill(sun > 0 ? Color.signal : .clear))
                            .frame(width: 12, height: 12)
                        Text(site.mission).font(TextStyle.bodyStrong.font).foregroundStyle(Color.ink)
                        Spacer()
                        Text(sun > 0 ? String(format: tr("Sun %.0f° up", "Sol a %.0f°"), sun) : tr("In shadow", "En sombra"))
                            .style(.label).font(.custom("IBMPlexMono-Medium", size: 12))
                            .foregroundStyle(sun > 0 ? Color.signalText : Color.inkMuted)
                    }
                    .padding(.vertical, Spacing.s2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func fact(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).style(.label).foregroundStyle(Color.inkMuted)
            Spacer()
            Text(value).style(.coordinate).foregroundStyle(Color.ink)
        }
        .padding(.vertical, Spacing.s3)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
    }

    // MARK: Text

    private func positionLine(_ sky: SkySnapshot) -> String {
        String(format: "%@ %.0f° · %@ %.0f° %@",
               tr("Altitude", "Altura"), sky.altitude,
               tr("azimuth", "azimut"), sky.azimuth, compass(sky.azimuth))
    }

    private func guidance(turn: Double, tilt: Double) -> String {
        var parts: [String] = []
        if abs(turn) >= 6 {
            parts.append(String(format: turn > 0 ? tr("Turn %.0f° right", "Gira %.0f° a la derecha")
                                                 : tr("Turn %.0f° left", "Gira %.0f° a la izquierda"), abs(turn)))
        }
        if abs(tilt) >= 6 {
            parts.append(String(format: tilt > 0 ? tr("tilt up %.0f°", "sube %.0f°") : tr("tilt down %.0f°", "baja %.0f°"), abs(tilt)))
        }
        return parts.joined(separator: " · ")
    }

    private func compass(_ azimuth: Double) -> String {
        let names = Locale.preferredLanguages.first?.hasPrefix("es") == true
            ? ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
            : ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return names[Int((azimuth / 45).rounded()) % 8]
    }

    private func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return Self.clock.string(from: date)
    }

    /// 24-hour, like a mission log; "omitted AM/PM" on a 12-hour locale would turn 14:44 into 02:44.
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private func wrap180(_ d: Double) -> Double {
        let x = (d + 180).truncatingRemainder(dividingBy: 360)
        return (x < 0 ? x + 360 : x) - 180
    }
}

/// The Moon's disk as seen now: the lit part, the terminator, and a light on each site
/// (filled in daylight, hollow in shadow), turned the way it appears in the sky.
struct SkyMoonDisk: View {
    let sky: SkySnapshot
    let sites: [LandingSite]
    var selectedID: String?
    var onSelect: (LandingSite) -> Void

    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let points: [(LandingSite, CGPoint)] = sites.compactMap { site in
                guard let p = SkyModel.diskPoint(lat: site.lat, lon: site.lon, in: sky) else { return nil }
                return (site, CGPoint(x: c.x + p.x * r, y: c.y - p.y * r))
            }

            ZStack {
                Canvas { ctx, _ in
                    let disk = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                    ctx.fill(disk, with: .color(.surfaceRaised))
                    ctx.fill(litPath(center: c, radius: r), with: .color(.regolith))
                    ctx.stroke(disk, with: .color(.dust), lineWidth: 1)

                    let dot = r * 0.05
                    for (site, p) in points {
                        let lit = (sky.siteSunElevation[site.id] ?? -90) > 0
                        let rect = CGRect(x: p.x - dot, y: p.y - dot, width: 2 * dot, height: 2 * dot)
                        if lit {
                            let halo = dot * 2.2
                            ctx.fill(Path(ellipseIn: CGRect(x: p.x - halo, y: p.y - halo, width: 2 * halo, height: 2 * halo)),
                                     with: .color(.signal.opacity(0.18)))
                            ctx.fill(Path(ellipseIn: rect), with: .color(.signal))
                        } else {
                            ctx.stroke(Path(ellipseIn: rect), with: .color(.signal), lineWidth: 2)
                        }
                        if site.id == selectedID {
                            let ring = dot * 3
                            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: 2 * ring, height: 2 * ring)),
                                       with: .color(.signal), lineWidth: 2)
                        }
                    }
                }
                ForEach(points, id: \.0.id) { site, p in
                    Button { onSelect(site) } label: { Circle().fill(.clear).contentShape(Circle()) }
                        .frame(width: 32, height: 32)
                        .position(p)
                        .accessibilityLabel(site.mission)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The sunlit part of the disk: the limb on the bright side closed by the terminator,
    /// an ellipse whose width follows the phase.
    private func litPath(center c: CGPoint, radius r: CGFloat) -> Path {
        let k = sky.illuminatedFraction
        // Bright limb direction on screen (y down), counterclockwise from up.
        let θ = sky.brightLimbFromUp * .pi / 180
        let bright = CGVector(dx: -sin(θ), dy: -cos(θ))
        let side = CGVector(dx: -bright.dy, dy: bright.dx)
        func point(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(x: c.x + r * (along * bright.dx + across * side.dx),
                    y: c.y + r * (along * bright.dy + across * side.dy))
        }
        // Terminator offset toward the bright side: -1 when full, +1 when new.
        let terminator = CGFloat(1 - 2 * k)
        var path = Path()
        let steps = 60
        for i in 0...steps {   // Bright limb, from one cusp to the other.
            let a = Double.pi * Double(i) / Double(steps) - .pi / 2
            let p = point(CGFloat(cos(a)), CGFloat(sin(a)))
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        for i in stride(from: steps, through: 0, by: -1) {   // Terminator, back to the first cusp.
            let a = Double.pi * Double(i) / Double(steps) - .pi / 2
            path.addLine(to: point(terminator * CGFloat(cos(a)), CGFloat(sin(a))))
        }
        path.closeSubpath()
        return path
    }
}
