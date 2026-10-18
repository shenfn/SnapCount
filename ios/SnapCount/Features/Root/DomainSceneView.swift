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
    @State private var catTrimStart: CGFloat = 0
    @State private var faceOpacity: Double = 1
    @State private var decorationOpacity: Double = 1
    @State private var transitionTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let extent = JieziPrototypeLayout.cat_viewbox_size
            let scale = min(geometry.size.width, geometry.size.height) / extent
            let decoration = catPose.decoration
            let foreground = JieziScene.tokens(for: catDomain.rawValue).foreground
            ZStack {
                Ellipse()
                    .fill(decoration.color)
                    .frame(width: decoration.rx * 2 * scale, height: decoration.ry * 2 * scale)
                    .position(
                        x: geometry.size.width / 2 + (decoration.cx - extent / 2) * scale,
                        y: geometry.size.height / 2 + (decoration.cy - extent / 2) * scale
                    )
                    .opacity(decoration.opacity * decorationOpacity)
                JieziCatShape(pose: catPose)
                    .trim(from: min(catTrimStart, catProgress), to: catProgress)
                    .stroke(foreground, style: StrokeStyle(lineWidth: JieziPrototypeLayout.cat_stroke_width * scale, lineCap: .round, lineJoin: .round))
                JieziCatShape(pose: catPose, drawsFace: true)
                    .stroke(foreground, style: StrokeStyle(lineWidth: JieziPrototypeLayout.cat_face_stroke_width * scale, lineCap: .round, lineJoin: .round))
                    .opacity(faceOpacity)
            }
        }
        .frame(width: JieziPrototypeLayout.cat_width, height: JieziPrototypeLayout.cat_height)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onAppear {
            transitionTask?.cancel()
            transitionTask = nil
            catPose = .forDomain(domain.rawValue)
            catDomain = domain
            catProgress = 1
            catTrimStart = 0
            faceOpacity = 1
            decorationOpacity = 1
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
            catTrimStart = 0
            faceOpacity = 1
            decorationOpacity = 1
        }
        .onChange(of: reduceMotion) { _, isEnabled in
            guard isEnabled else { return }
            transitionTask?.cancel()
            transitionTask = nil
            catPose = .forDomain(domain.rawValue)
            catDomain = domain
            catProgress = 1
            catTrimStart = 0
            faceOpacity = 1
            decorationOpacity = 1
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
            catTrimStart = 0
            faceOpacity = 1
            decorationOpacity = 1
            return
        }

        withAnimation(.easeOut(duration: JieziPrototypeMotion.cat_face_hide_ms)) {
            faceOpacity = 0
        }
        withAnimation(.easeInOut(duration: JieziPrototypeMotion.cat_decoration_fade_ms)) {
            decorationOpacity = 0
        }
        withAnimation(.timingCurve(0.5, 0, 0.9, 0.5, duration: JieziPrototypeMotion.cat_retract_ms)) {
            catTrimStart = 1
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
            var reset = Transaction(animation: nil)
            reset.disablesAnimations = true
            withTransaction(reset) {
                catTrimStart = 0
                catProgress = 0
            }
            // 原型 drop 阶段：先提交新路径的空描线帧，再开始绘制。
            do {
                try await Task.sleep(for: .seconds(JieziPrototypeMotion.cat_reset_frame_ms))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.6, 0, 0.25, 1, duration: JieziPrototypeMotion.cat_draw_ms)) {
                catProgress = 1
            }
            withAnimation(.easeOut(duration: JieziPrototypeMotion.cat_decoration_fade_ms)) {
                decorationOpacity = 1
            }
            do {
                try await Task.sleep(for: .seconds(JieziPrototypeMotion.cat_face_delay_ms))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: JieziPrototypeMotion.cat_face_fade_ms)) {
                faceOpacity = 1
            }
        }
    }
}
