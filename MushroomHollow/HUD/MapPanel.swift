import GameCore
import SwiftUI

/// The world map (M): the whole hollow with every hunting ground and its levels. Pinch to zoom
/// in on a region or the critters around you, drag to look around, double-tap to find yourself
/// again (or A to step through the zoom, LB/RB to zoom, the stick to pan). Quest areas pulse.
struct MapPanel: View {
    let session: GameSession

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            MapCanvas(session: session)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            MapSidebar(session: session)
                .frame(width: 220)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding(.vertical, 12)
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.45))
    }
}

private struct MapSidebar: View {
    let session: GameSession

    var body: some View {
        let zone = session.zone
        let quests = Dictionary(grouping: session.questTargets, by: \.title).keys.sorted()
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mushroom Hollow").font(.title3.weight(.bold))
                Spacer()
                Button(action: session.closePanel) {
                    Label("Close", systemImage: session.glyphs?.back ?? "xmark")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
            }
            if let zone {
                VStack(alignment: .leading, spacing: 3) {
                    Label(zone.name, systemImage: "location.fill").font(.headline)
                    if let levels = zone.levels {
                        Text("Level \(levels.lowerBound)–\(levels.upperBound)").font(.subheadline.weight(.semibold))
                            .foregroundStyle(MapStyle.levelColor(levels, player: session.hud.player?.stats.level ?? 1))
                    }
                    if let blurb = zone.blurb {
                        Text(blurb).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !quests.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quests").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    ForEach(quests, id: \.self) { title in
                        Label(title, systemImage: "scroll.fill").font(.caption).foregroundStyle(.yellow)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Legend").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Label("You", systemImage: "location.north.fill").foregroundStyle(.white)
                Label("Quest area", systemImage: "circle.dashed").foregroundStyle(.yellow)
                if session.mapSpan < MapCanvas.labelAllSpan {
                    Label("Attacks on sight", systemImage: "circle.fill").foregroundStyle(.red)
                    Label("Only fights back", systemImage: "circle.fill").foregroundStyle(.orange)
                }
                Label("Road", systemImage: "line.diagonal").foregroundStyle(Color(red: 0.8, green: 0.65, blue: 0.45))
            }
            .font(.caption)
            Spacer(minLength: 0)
            Text(session.isGamepadConnected ? "LB/RB zoom · stick to look around" : "Pinch to zoom · drag to look around · double-tap to find yourself")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button {
                session.cycleMapZoom()
            } label: {
                let zoomedIn = session.mapSpan < 60
                Label(zoomedIn ? "Whole hollow" : "Zoom in",
                      systemImage: session.glyphs?.primary ?? (zoomedIn ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }
}

enum MapStyle {
    /// Red: too strong for you yet. Yellow: your level. Grey-green: you've outgrown it.
    static func levelColor(_ levels: ClosedRange<Int>, player: Int) -> Color {
        if player < levels.lowerBound - 2 { return Color(red: 1, green: 0.4, blue: 0.35) }
        if player < levels.lowerBound { return .orange }
        if player <= levels.upperBound { return Color(red: 1, green: 0.92, blue: 0.5) }
        return Color(red: 0.7, green: 0.85, blue: 0.7)
    }
}

private struct MapCanvas: View {
    let session: GameSession
    /// Span and center when the current pinch or drag began.
    @State private var gestureStart: (span: Float, center: Vec2)?

    /// Zoomed in closer than this, every place gets its name (further out, the inner ring gets badges).
    static let labelAllSpan: Float = 200
    /// Closer than this, the villagers show.
    static let villagerSpan: Float = 80

    var body: some View {
        let image = Image(uiImage: session.mapImage)
        let span = session.mapSpan
        GeometryReader { geometry in
            TimelineView(.periodic(from: .now, by: 0.2)) { timeline in
                let markers = session.mapMarkers
                let center = session.effectiveMapCenter
                let pulse = 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 3)
                Canvas { context, size in
                    draw(in: &context, size: size, image: image, markers: markers, span: span, center: center, pulse: pulse)
                }
            }
            .contentShape(.rect)
            .gesture(pinch.simultaneously(with: pan(width: geometry.size.width)))
            .onTapGesture(count: 2) { session.recenterMap() }
        }
        .background(Color(red: 0.2, green: 0.17, blue: 0.12))
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = gestureStart ?? (session.mapSpan, session.effectiveMapCenter)
                gestureStart = start
                // Zoom toward the point between your fingers: it stays put while the map scales around it.
                let span = min(max(start.span / Float(value.magnification), GameSession.mapSpanRange.lowerBound),
                               GameSession.mapSpanRange.upperBound)
                let anchor = start.center + Vec2(Float(value.startAnchor.x) - 0.5, Float(value.startAnchor.y) - 0.5) * 2 * start.span
                session.setMapView(span: span, center: anchor + (start.center - anchor) * (span / start.span))
            }
            .onEnded { _ in gestureStart = nil }
    }

    /// Dragging moves the ground under your finger.
    private func pan(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = gestureStart ?? (session.mapSpan, session.effectiveMapCenter)
                gestureStart = start
                let metersPerPoint = 2 * session.mapSpan / Float(max(width, 1))
                let moved = Vec2(Float(value.translation.width), Float(value.translation.height)) * metersPerPoint
                session.setMapView(span: session.mapSpan, center: start.center - moved)
            }
            .onEnded { _ in gestureStart = nil }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, image: Image, markers: MapMarkers, span halfSpan: Float,
                      center: Vec2, pulse: Double) {
        let map = session.map
        let zoomed = halfSpan < Self.labelAllSpan
        let scale = CGFloat(Float(size.width) / 2 / halfSpan)
        func point(_ p: Vec2) -> CGPoint {
            CGPoint(x: size.width / 2 + CGFloat(p.x - center.x) * scale, y: size.height / 2 + CGFloat(p.y - center.y) * scale)
        }
        func disc(_ p: Vec2, _ radius: CGFloat) -> Path {
            let c = point(p)
            return Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius))
        }

        // The painted hollow.
        let extent = GroundPainter.extent
        let corner = point(Vec2(-extent, -extent))
        context.draw(image, in: CGRect(origin: corner, size: CGSize(width: CGFloat(2 * extent) * scale, height: CGFloat(2 * extent) * scale)))

        // Quest areas.
        for target in session.questTargets {
            let path = disc(target.center, CGFloat(target.radius) * scale)
            context.fill(path, with: .color(.yellow.opacity(0.08 + 0.1 * pulse)))
            context.stroke(path, with: .color(.yellow.opacity(0.6 + 0.4 * pulse)), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
        }

        // Critters nearby (zoomed in only).
        if zoomed {
            for mob in markers.mobs {
                let color: Color = mob.isHostile ? .red : .orange
                if mob.isFighting {
                    context.stroke(disc(mob.position, 7), with: .color(.red), lineWidth: 2)
                }
                context.fill(disc(mob.position, 3.5), with: .color(color))
                context.stroke(disc(mob.position, 3.5), with: .color(.black.opacity(0.6)), lineWidth: 1)
            }
            for npc in map.npcs where halfSpan < Self.villagerSpan {
                let symbol = npc.id.definition.isShopkeeper ? "bag.fill" : npc.id.definition.upgradesGear ? "hammer.fill" : "person.fill"
                context.draw(Text(Image(systemName: symbol)).font(.caption).foregroundStyle(.white), at: point(npc.position))
            }
        }

        // Labels, with a dark halo so they read over any ground.
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.95), radius: 2.5))
            let level = session.hud.player?.stats.level ?? 1
            for zone in map.zones where zone.radius < 100 {
                let at = point(zone.center)
                guard at.x > -60, at.x < size.width + 60, at.y > -30, at.y < size.height + 30 else { continue }
                let isLake = map.terrain.lakes.contains { $0.name == zone.name }
                let isVillage = zone.levels == nil && !isLake
                // The whole hollow is too small on a phone to name the inner ring: badges there.
                if !zoomed, zone.center.length < 120 {
                    if let levels = zone.levels {
                        let badge = Text("\(levels.lowerBound)–\(levels.upperBound)")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(MapStyle.levelColor(levels, player: level))
                        layer.draw(badge, at: at)
                    } else if isVillage {
                        layer.draw(Text(Image(systemName: "house.fill")).font(.system(size: 11)).foregroundStyle(.white),
                                   at: CGPoint(x: at.x, y: at.y + 4))
                    }
                    continue
                }
                let titleSize = CGFloat(min(16, max(10.5, 10.5 + (Self.labelAllSpan - halfSpan) / 30)))
                var title = Text(zone.name).font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(isLake ? Color(red: 0.75, green: 0.92, blue: 1) : .white)
                if isLake { title = title.italic() }
                // Villages are labeled beneath and lakes above, so the name doesn't sit on the houses or water.
                let labelAt = isVillage ? point(zone.center + Vec2(0, zone.radius * 0.8))
                    : isLake ? point(zone.center - Vec2(0, zone.radius * 0.85)) : at
                layer.draw(title, at: labelAt)
                if let levels = zone.levels {
                    layer.draw(Text("Lv \(levels.lowerBound)–\(levels.upperBound)")
                        .font(.system(size: titleSize - 1, weight: .semibold, design: .rounded))
                        .foregroundStyle(MapStyle.levelColor(levels, player: level)),
                               at: CGPoint(x: labelAt.x, y: labelAt.y + titleSize + 2))
                }
            }
            if let arena = map.bossArena {
                let at = point(arena.center + (arena.perch - arena.center) * 2)
                layer.draw(Text(Image(systemName: markers.bossAwake ? "moon.stars.fill" : "moon.zzz.fill"))
                    .font(.system(size: 16))
                    .foregroundStyle(markers.bossAwake ? Color.red : Color(red: 0.7, green: 0.75, blue: 1)), at: CGPoint(x: at.x, y: at.y - 20))
                if markers.bossAwake {
                    layer.draw(Text("The owl is awake!").font(.caption2.weight(.bold)).foregroundStyle(.red),
                               at: CGPoint(x: at.x, y: at.y - 38))
                }
            }
            if zoomed {
                layer.draw(Text("The Great Tree").font(.system(size: 14, weight: .heavy, design: .serif))
                    .foregroundStyle(Color(red: 1, green: 0.9, blue: 0.7)), at: point(.zero))
            }
        }

        // You: an arrow pointing the way you face, and a soft cone where the camera looks.
        if let player = markers.player {
            let at = point(player.position)
            var cone = Path()
            cone.move(to: at)
            let look = atan2(Double(markers.viewDirection.y), Double(markers.viewDirection.x))
            cone.addArc(center: at, radius: 34, startAngle: .radians(look - 0.45), endAngle: .radians(look + 0.45), clockwise: false)
            cone.closeSubpath()
            context.fill(cone, with: .radialGradient(Gradient(colors: [.white.opacity(0.35), .white.opacity(0)]),
                                                    center: at, startRadius: 0, endRadius: 34))
            let facing = CGVector(dx: CGFloat(sin(player.yaw)), dy: CGFloat(cos(player.yaw)))
            let side = CGVector(dx: -facing.dy, dy: facing.dx)
            var arrow = Path()
            arrow.move(to: CGPoint(x: at.x + facing.dx * 11, y: at.y + facing.dy * 11))
            arrow.addLine(to: CGPoint(x: at.x - facing.dx * 7 + side.dx * 7, y: at.y - facing.dy * 7 + side.dy * 7))
            arrow.addLine(to: CGPoint(x: at.x - facing.dx * 3, y: at.y - facing.dy * 3))
            arrow.addLine(to: CGPoint(x: at.x - facing.dx * 7 - side.dx * 7, y: at.y - facing.dy * 7 - side.dy * 7))
            arrow.closeSubpath()
            context.fill(disc(player.position, 11 + 3 * pulse), with: .color(.white.opacity(0.18)))
            context.fill(arrow, with: .color(.white))
            context.stroke(arrow, with: .color(.black.opacity(0.7)), lineWidth: 1.2)
        }

        // Compass and scale.
        context.draw(Text("N").font(.system(size: 14, weight: .heavy, design: .serif)).foregroundStyle(.white),
                     at: CGPoint(x: size.width - 22, y: 20))
        let meters: Float = halfSpan < 70 ? 20 : (zoomed ? 50 : 100)
        let barLength = CGFloat(meters) * scale
        // Bottom right, clear of the place names.
        let barStart = size.width - 14 - barLength
        var bar = Path()
        bar.move(to: CGPoint(x: barStart, y: size.height - 16))
        bar.addLine(to: CGPoint(x: size.width - 14, y: size.height - 16))
        context.stroke(bar, with: .color(.white), lineWidth: 3)
        context.draw(Text("\(Int(meters)) m").font(.caption2.weight(.semibold)).foregroundStyle(.white),
                     at: CGPoint(x: barStart + barLength / 2, y: size.height - 28))
    }
}
