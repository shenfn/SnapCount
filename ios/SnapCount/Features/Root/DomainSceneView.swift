import SwiftUI

struct DomainSceneView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let domain: AppDomain

    @State private var catPose: JieziCatPose = .expense
    @State private var catProgress: CGFloat = 1
    @State private var transitionTask: Task<Void, Never>?

    private var scene: JieziSceneTokens { JieziScene.tokens(for: domain.rawValue) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: scene.background,
                startPoint: .top,
                endPoint: .bottom
            )
            .animation(.easeInOut(duration: JieziPrototypeMotion.background_ms), value: domain)

            if scene.usesDiagonalTexture {
                diagonalTexture
                    .transition(.opacity)
                    .animation(.easeInOut(duration: JieziPrototypeMotion.background_ms), value: domain)
            }

            JieziCatShape(pose: catPose)
                .trim(from: 0, to: catProgress)
                .stroke(
                    scene.accent,
                    style: StrokeStyle(lineWidth: 2.35, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 112, height: 112)
                .opacity(0.48)
                .padding(.trailing, 14)
                .padding(.bottom, 74)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .onAppear {
            transitionTask?.cancel()
            transitionTask = nil
            catPose = .forDomain(domain.rawValue)
            catProgress = 1
        }
        .onChange(of: domain) { _, newDomain in
            transition(to: newDomain)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            transitionTask?.cancel()
            transitionTask = nil
            catPose = .forDomain(domain.rawValue)
            catProgress = 1
        }
        .onChange(of: reduceMotion) { _, isEnabled in
            guard isEnabled else { return }
            transitionTask?.cancel()
            transitionTask = nil
            catPose = .forDomain(domain.rawValue)
            catProgress = 1
        }
        .onDisappear {
            transitionTask?.cancel()
            transitionTask = nil
        }
    }

    private var diagonalTexture: some View {
        Canvas { context, size in
            var x: CGFloat = -size.height
            while x < size.width {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: size.height))
                stripe.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(stripe, with: .color(.white.opacity(0.035)), lineWidth: 1)
                x += 16
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func transition(to newDomain: AppDomain) {
        transitionTask?.cancel()
        transitionTask = nil
        let nextPose = JieziCatPose.forDomain(newDomain.rawValue)
        guard !reduceMotion, scenePhase == .active else {
            catPose = nextPose
            catProgress = 1
            return
        }

        withAnimation(.easeInOut(duration: JieziPrototypeMotion.cat_retract_ms)) {
            catProgress = 0
        }
        transitionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(JieziPrototypeMotion.cat_retract_ms))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            catPose = nextPose
            withAnimation(.easeOut(duration: JieziPrototypeMotion.cat_draw_ms)) {
                catProgress = 1
            }
        }
    }
}
