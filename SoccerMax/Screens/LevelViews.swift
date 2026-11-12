// Training level ? the top of the Sessions tab's TRAIN side (2026-10-24, notes/23). The user: "Make the central most
// important UI component a swipe through of different level fields/stadiums. Each stadium should be better than the
// last with names like 'Club, Academy, Pro' and the user should be able to swipe through those and click 'set training
// level'. Each level should be progressively harder with more time spent. This should only effect the sessions
// recommended." v3 (same day): "cut out the 3d model and put the entire thing in the slider" ? each ground is now the
// WHOLE stadium as a cut-out 3D model (on its slab of earth, transparent background) floating in the slider, turning a
// little as you swipe (src/three/stadiums.ts `cut=1` ? scripts/render-stadiums.mjs ? Resources/Stadiums/level-<n>.webp).
// The level only rebuilds the premade sessions (more drills, harder drills, more sets) ? your own never change.
import SwiftUI

struct LevelCarousel: View {
    @Environment(AppStore.self) private var store
    @State private var at: Int?
    @State private var toast: String?

    var body: some View {
        let levels = Library.shared.levels
        let current = store.trainingLevel
        let shown = at ?? current
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(levels.indices, id: \.self) { i in
                        StadiumModel(level: levels[i], index: i, top: i == levels.count - 1, current: i == current)
                            .containerRelativeFrame(.horizontal)  // the scroll view's width minus its margins: neighbours peek
                            .scrollTransition(.interactive, axis: .horizontal) { v, phase in
                                // the model turns a little as it slides, like a turntable
                                v.rotation3DEffect(.degrees(phase.value * -26), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                                    .scaleEffect(1 - abs(phase.value) * 0.16)
                                    .opacity(1 - abs(phase.value) * 0.5)
                            }
                            .onTapGesture { withAnimation(.snappy) { at = i } }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $at)
            .contentMargins(.horizontal, 26, for: .scrollContent)
            .padding(.horizontal, -16)
            .scrollIndicators(.hidden)
            .onAppear { if at == nil { at = DebugRoute.parts.first == "level" ? Int(DebugRoute.parts[safe: 1] ?? "") ?? current : current } }
            .onChange(of: at) { old, new in if old != nil, new != nil { Haptics.play(.stud) } }

            // the ladder: one ball panel per level, filled up to the one you're looking at
            HStack(spacing: 7) {
                ForEach(levels.indices, id: \.self) { i in
                    PanelMark(state: i <= shown ? .stitched : .empty, pent: i == shown, size: i == shown ? 17 : 12)
                }
            }
            .padding(.top, 14)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: shown)
            .accessibilityHidden(true)

            ZStack {
                if shown == current {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark").font(.system(size: 17, weight: .heavy))
                        Text("YOUR TRAINING LEVEL").font(F.display(20))
                    }
                    .foregroundStyle(C.brand)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(Capsule().strokeBorder(C.brand.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, dash: [7, 6])))
                    .transition(.scale(0.92).combined(with: .opacity))
                } else {
                    Button("SET TRAINING LEVEL") { set(shown) }
                        .buttonStyle(.gameLarge)
                        .transition(.scale(0.92).combined(with: .opacity))
                }
            }
            .frame(height: 71, alignment: .top)
            .padding(.top, 14)
            .animation(.spring(response: 0.32, dampingFraction: 0.7), value: shown == current)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(F.round(15, .semibold)).foregroundStyle(C.creme)
                    .padding(.horizontal, 16).frame(height: 44)
                    .background(Capsule().fill(C.char700).overlay(Capsule().stroke(C.charInk, lineWidth: 2)))
                    .offset(y: -96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func set(_ i: Int) {
        let moved = withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { store.setLevel(i) }
        Haptics.play(.goal)
        guard moved > 0 else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            toast = "\(moved) saved session\(moved == 1 ? "" : "s") moved to \(Library.shared.levels[i].name)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { withAnimation(.easeOut(duration: 0.3)) { toast = nil } }
    }
}

/// One ground: the whole stadium as a cut-out 3D model, floating, then its name and how long its sessions run.
/// Your level gets a green glow under it; the top level wears gold.
struct StadiumModel: View {
    let level: TrainingLevel
    let index: Int
    let top: Bool
    let current: Bool

    var body: some View {
        let glow = top ? C.gold : current ? C.brand : Color(hex: 0x8FA3C0)
        VStack(spacing: 0) {
            ZStack {
                // a pool of light on the "floor" under the model
                Ellipse()
                    .fill(RadialGradient(colors: [glow.opacity(current || top ? 0.34 : 0.14), glow.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: 170))
                    .frame(height: 120)
                    .offset(y: 70)
                    .blur(radius: 6)
                if let img = ImageCache.load("level-\(index + 1)", ext: "webp", dir: "Stadiums", maxPixel: 1200) {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fit)
                        .phaseAnimator([false, true]) { v, up in v.offset(y: up ? -5 : 2) } animation: { _ in .easeInOut(duration: 2.6) }
                }
            }
            .aspectRatio(1.25, contentMode: .fit)
            .padding(.horizontal, -8)

            HStack(spacing: 8) {
                Text("LEVEL \(index + 1)")
                    .font(F.round(12, .bold)).kerning(1.4)
                    .foregroundStyle(C.creme2)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Capsule().fill(C.char800).overlay(Capsule().stroke(C.charInk, lineWidth: 2)))
                if current {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                        Text("YOUR LEVEL").font(F.round(12, .bold)).kerning(1.1)
                    }
                    .foregroundStyle(C.brandInk)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Capsule().fill(C.brand).overlay(Capsule().stroke(C.brandInk, lineWidth: 2)))
                    .transition(.scale(0.5).combined(with: .opacity))
                }
            }
            .padding(.top, 2)
            Disp(level.name.uppercased(), size: 40, color: top ? C.gold : C.creme, ink: top ? C.goldInk : C.charInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 8)
            Text("\(level.minutes) MIN SESSIONS")
                .font(F.round(15, .bold)).kerning(1.2)
                .foregroundStyle(top ? C.gold : C.brand)
                .padding(.top, 4)
            Text(level.line)
                .font(F.round(15, .semibold))
                .foregroundStyle(C.creme2)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(level.name), level \(index + 1), \(level.minutes) minute sessions\(current ? ", your training level" : "")")
    }
}
