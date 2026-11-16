// OPENING ANIMATION (2026-11-17). Every cold start: the ball drops in with a blue glow, SOCCER LAB writes itself letter
// by letter, the tagline "Play Like a Pro" rises in, then the whole thing fades into the app (about 2.2 s). Reduce
// Motion = a short plain fade. Shown over the app (App.swift), so the app loads underneath while it plays.
import SwiftUI

struct SplashView: View {
    var done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ball = false
    @State private var letters = 0
    @State private var tagline = false
    @State private var glow = false
    @State private var leaving = false

    private let word = Array("SOCCER LAB")

    var body: some View {
        ZStack {
            C.char950.ignoresSafeArea()
            RadialGradient(colors: [C.brand.opacity(glow ? 0.45 : 0.0), .clear], center: .center, startRadius: 10, endRadius: 360)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.9), value: glow)

            VStack(spacing: 22) {
                IconBall(size: 96)
                    .shadow(color: C.brand.opacity(0.8), radius: glow ? 30 : 0)
                    .scaleEffect(ball ? 1 : 0.2)
                    .rotationEffect(.degrees(ball ? 0 : -200))
                    .opacity(ball ? 1 : 0)
                    .offset(y: ball ? 0 : -120)

                HStack(spacing: 2) {
                    ForEach(word.indices, id: \.self) { i in
                        Text(String(word[i]))
                            .font(.system(size: 38, weight: .heavy))
                            .kerning(2)
                            .foregroundStyle(i >= 7 ? C.brand : C.creme)
                            .opacity(i < letters ? 1 : 0)
                            .offset(y: i < letters ? 0 : 14)
                            .blur(radius: i < letters ? 0 : 6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Soccer Lab")

                Text("Play Like a Pro")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(C.brandHi)
                    .opacity(tagline ? 1 : 0)
                    .offset(y: tagline ? 0 : 12)
            }
        }
        .opacity(leaving ? 0 : 1)
        .scaleEffect(leaving ? 1.06 : 1)
        .allowsHitTesting(!leaving)
        .task { await play() }
    }

    private func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    private func play() async {
        if reduceMotion {
            ball = true; letters = word.count; tagline = true; glow = true
            await wait(0.9)
            withAnimation(.easeOut(duration: 0.3)) { leaving = true }
            await wait(0.3)
            done()
            return
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.62)) { ball = true }
        Haptics.play(.kick)
        await wait(0.35)
        glow = true
        for i in 1...word.count {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { letters = i }
            await wait(0.055)
        }
        await wait(0.15)
        withAnimation(.easeOut(duration: 0.45)) { tagline = true }
        await wait(1.0)
        withAnimation(.easeIn(duration: 0.35)) { leaving = true }
        await wait(0.35)
        done()
    }
}
