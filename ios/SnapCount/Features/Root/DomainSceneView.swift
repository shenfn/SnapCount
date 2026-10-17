import SwiftUI

struct DomainSceneView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let domain: AppDomain

    private var scene: JieziSceneTokens { JieziScene.tokens(for: domain.rawValue) }

    var body: some View {
        ZStack {
            if scene.usesDiagonalTexture {
                diagonalTexture
                LinearGradient(stops: scene.textureWash, startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: scene.background, startPoint: .top, endPoint: .bottom)
            }
            GeometryReader { geometry in
                RadialGradient(
                    colors: [scene.glow.opacity(scene.glowOpacity), .clear],
                    center: UnitPoint(x: 0.82, y: 0.12),
                    startRadius: 0,
                    endRadius: geometry.size.width * 0.7
                )
            }
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: JieziPrototypeMotion.background_ms), value: domain)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var diagonalTexture: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(scene.background[0]))
            guard scene.stripeWidth > 0 else { return }
            var x: CGFloat = -size.height
            while x < size.width {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: size.height))
                stripe.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(stripe, with: .color(scene.background[1]), lineWidth: scene.stripeWidth)
                x += scene.stripeWidth * 2 * sqrt(2)
            }
        }
    }
}

/// 猫属于主值右侧的独立视觉层，不参与分页命中和业务状态。
struct DomainCatView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let domain: AppDomain
    @State private var catPose: JieziCatPose = .expense
    @State private var catDomain: AppDomain = .expense
    @State private var catProgress: CGFloat = 1
    @State private var transitionTask: Task<Void, Never>?

    var body: some View {
        JieziCatShape(pose: catPose)
            .trim(from: 0, to: catProgress)
            .stroke(
                JieziScene.tokens(for: catDomain.rawValue).foreground,
                style: StrokeStyle(lineWidth: 2.35, lineCap: .round, lineJoin: .round)
            )
            .frame(width: JieziPrototypeLayout.cat_width, height: JieziPrototypeLayout.cat_height)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        .onAppear {
            transitionTask?.cancel()
            transitionTask = nil
            catPose = .forDomain(domain.rawValue)
            catDomain = domain
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
            catDomain = domain
            catProgress = 1
        }
        .onChange(of: reduceMotion) { _, isEnabled in
            guard isEnabled else { return }
            transitionTask?.cancel()
            transitionTask = nil
            catPose = .forDomain(domain.rawValue)
            catDomain = domain
            catProgress = 1
        }
        .onDisappear {
            transitionTask?.cancel()
            transitionTask = nil
        }
    }

    private func transition(to newDomain: AppDomain) {
        transitionTask?.cancel()
        transitionTask = nil
        let nextPose = JieziCatPose.forDomain(newDomain.rawValue)
        guard !reduceMotion, scenePhase == .active else {
            catPose = nextPose
            catDomain = newDomain
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
            catDomain = newDomain
            withAnimation(.easeOut(duration: JieziPrototypeMotion.cat_draw_ms)) {
                catProgress = 1
            }
        }
    }
}
