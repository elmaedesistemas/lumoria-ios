import SwiftUI

/// Sky mode through the camera: a ring on the real Moon and a magnifier with the six
/// sites as they sit on the disk right now. A tap on the real Moon corrects the compass.
struct SkyCameraView: View {
    @Environment(SitesStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var sensors = SkySensors()
    @State private var tracker = SkyTracker()
    @State private var selectedID: String?

    /// Size of the magnified disk on screen.
    private let magnifier: CGFloat = 150

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let place = sensors.location
            let sky = SkyModel.snapshot(
                at: context.date,
                latitude: place?.coordinate.latitude ?? SkyModel.sanJose.latitude,
                longitude: place?.coordinate.longitude ?? SkyModel.sanJose.longitude,
                height: place?.altitude ?? SkyModel.sanJose.height,
                sites: store.sites
            )
            ZStack {
                Color.space.ignoresSafeArea()
                #if targetEnvironment(simulator)
                Text(tr("The sky camera runs on the iPhone.", "La cámara del cielo funciona en el iPhone."))
                    .style(.bodySmall).foregroundStyle(Color.inkMuted)
                #else
                SkyARView(sky: sky, tracker: tracker).ignoresSafeArea()
                overlay(sky: sky).ignoresSafeArea()
                #endif
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottom(sky: sky)
                }
            }
        }
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

    // MARK: Overlay on the camera

    @ViewBuilder
    private func overlay(sky: SkySnapshot) -> some View {
        let size = tracker.viewSize
        if sky.isUp, let moon = tracker.moonPoint, tracker.offscreenAngle == nil {
            let ring = max(18, tracker.moonDiameter / 2 + 10)
            // Magnifier above the Moon, or below when there's no room.
            let below = moon.y - ring - magnifier - 40 < 60
            let inset = CGPoint(
                x: min(max(moon.x, magnifier / 2 + 16), size.width - magnifier / 2 - 16),
                y: below ? moon.y + ring + 30 + magnifier / 2 : moon.y - ring - 30 - magnifier / 2
            )
            ZStack {
                Path { path in
                    let dx = inset.x - moon.x, dy = inset.y - moon.y
                    let length = max(1, hypot(dx, dy))
                    path.move(to: CGPoint(x: moon.x + dx / length * ring, y: moon.y + dy / length * ring))
                    path.addLine(to: CGPoint(x: inset.x - dx / length * magnifier / 2, y: inset.y - dy / length * magnifier / 2))
                }
                .stroke(Color.signal, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                Circle()
                    .stroke(Color.signal, lineWidth: 2)
                    .frame(width: ring * 2, height: ring * 2)
                    .position(moon)

                SkyMoonDisk(sky: sky, sites: store.sites, selectedID: selectedID) { selectedID = $0.id }
                    .frame(width: magnifier, height: magnifier)
                    .padding(6)
                    .background(Color.space.opacity(0.75), in: Circle())
                    .overlay(Circle().stroke(Color.signal, lineWidth: 1.5))
                    .position(inset)

                Text("×\(Int((magnifier / max(1, tracker.moonDiameter)).rounded()))")
                    .style(.label)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, Spacing.s2)
                    .frame(height: 22)
                    .background(Color.surface, in: Capsule())
                    .position(x: inset.x + magnifier / 2 - 8, y: inset.y - magnifier / 2 + 4)
            }
        } else if sky.isUp, let angle = tracker.offscreenAngle {
            // Arrow at the screen edge pointing toward the Moon.
            let reach = min(size.width, size.height) / 2 - 56
            let θ = angle * .pi / 180
            Image(systemName: "arrow.up")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.onSignal)
                .frame(width: 48, height: 48)
                .background(Color.signal, in: Circle())
                .rotationEffect(.degrees(angle))
                .position(x: size.width / 2 + CGFloat(sin(θ)) * reach, y: size.height / 2 - CGFloat(cos(θ)) * reach)
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: Spacing.s2) {
            CircleButton(systemName: "chevron.left", label: tr("Back", "Atrás")) { dismiss() }
            Spacer()
            Text(tracker.isCalibrated ? tr("Calibrated", "Calibrado") : tr("Sky", "Cielo"))
                .style(.label)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, Spacing.s3)
                .frame(height: 32)
                .background(Color.surface, in: Capsule())
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.top, Spacing.s2)
    }

    private func bottom(sky: SkySnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            if !sky.isUp {
                Text(tr("The Moon is below the horizon.", "La Luna está bajo el horizonte."))
                    .font(TextStyle.bodyStrong.font).foregroundStyle(Color.ink)
            } else if tracker.offscreenAngle != nil {
                Text(tr("Follow the arrow to find the Moon.", "Sigue la flecha para encontrar la Luna."))
                    .font(TextStyle.bodyStrong.font).foregroundStyle(Color.ink)
            } else {
                Text(tr("The ring should sit on the Moon. If it doesn't, tap the real Moon.",
                        "El anillo debería quedar sobre la Luna. Si no, toca la Luna real."))
                    .style(.bodySmall).foregroundStyle(Color.ink)
            }
            if tracker.isCalibrated {
                HStack {
                    Text(String(format: tr("Compass corrected by %.1f°", "Brújula corregida %.1f°"),
                                hypot(tracker.azimuthOffset, tracker.altitudeOffset)))
                        .style(.label).font(.custom("IBMPlexMono-Medium", size: 11))
                        .foregroundStyle(Color.inkMuted)
                    Spacer()
                    Button(tr("Reset", "Reiniciar")) { tracker.resetCalibration() }
                        .font(TextStyle.bodyStrong.font)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s4)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
        .padding(Spacing.s4)
    }
}
