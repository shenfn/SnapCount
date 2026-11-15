//
//  JieziTheme+Generated.swift
//  SnapCount
//
//  数据源：trae-design-system/tokens/design-tokens.json v0.2.0
//  禁止手工修改本文件。任何调整请改 SSOT 后运行 scripts/generate-ios.mjs
//

import SwiftUI
import UIKit

// MARK: - 颜色工具（自包含，勿与手写版重复定义）

extension Color {
    init(jieziHex: String) {
        let cleaned = jieziHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    func jieziBlended(with other: Color, amount: Double) -> Color {
        let ratio = CGFloat(min(max(amount, 0), 1))
        let lhs = UIColor(self)
        let rhs = UIColor(other)
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
        return Color(
            red: Double(lr + (rr - lr) * ratio),
            green: Double(lg + (rg - lg) * ratio),
            blue: Double(lb + (rb - lb) * ratio),
            opacity: Double(la + (ra - la) * ratio)
        )
    }
}

// MARK: - 主题 Palette（运行时可切换）

struct JieziGeneratedPalette {
    let id: String
    let name: String
    let description: String
    let paper: Color
    let brand: Color
    let light: Color
    let space: Color
    let ink: Color
    let muted: Color
    let coral: Color

    /// 派生分隔线色：brand 13%（SSOT 派生规则，不是独立槽位）
    var line: Color { brand.opacity(0.13) }

    static let cyan = JieziGeneratedPalette(
        id: "cyan", name: "芥青微光", description: "温暖日常之下，一座正在呼吸的记忆生境。",
        paper: Color(jieziHex: "#F5F1E7"),
        brand: Color(jieziHex: "#426E63"),
        light: Color(jieziHex: "#DCBF74"),
        space: Color(jieziHex: "#17312D"),
        ink: Color(jieziHex: "#202A27"),
        muted: Color(jieziHex: "#6E7773"),
        coral: Color(jieziHex: "#B76555")
    )

    static let xuan = JieziGeneratedPalette(
        id: "xuan", name: "玄青须弥", description: "克制现实表面之下，隐藏深邃而辽阔的个人宇宙。",
        paper: Color(jieziHex: "#EFEFEB"),
        brand: Color(jieziHex: "#263F3D"),
        light: Color(jieziHex: "#C79B4E"),
        space: Color(jieziHex: "#10211F"),
        ink: Color(jieziHex: "#1A2624"),
        muted: Color(jieziHex: "#5E6764"),
        coral: Color(jieziHex: "#A85648")
    )

    static let paper = JieziGeneratedPalette(
        id: "paper", name: "宣纸生境", description: "人生像墨痕留在纸上，在时间中晕开生长。",
        paper: Color(jieziHex: "#F2EDE0"),
        brand: Color(jieziHex: "#586C55"),
        light: Color(jieziHex: "#BC8A54"),
        space: Color(jieziHex: "#535F4D"),
        ink: Color(jieziHex: "#2A2F26"),
        muted: Color(jieziHex: "#6B7163"),
        coral: Color(jieziHex: "#B26B50")
    )

    static let jade = JieziGeneratedPalette(
        id: "jade", name: "竹影鎏金", description: "沉静竹青承载长期记忆，克制鎏金点亮联系。",
        paper: Color(jieziHex: "#F3F4EC"),
        brand: Color(jieziHex: "#345F50"),
        light: Color(jieziHex: "#C8A55D"),
        space: Color(jieziHex: "#183A31"),
        ink: Color(jieziHex: "#1F2B26"),
        muted: Color(jieziHex: "#67756C"),
        coral: Color(jieziHex: "#A85F4F")
    )

    static let lotus = JieziGeneratedPalette(
        id: "lotus", name: "藕荷余晖", description: "降低科技感，突出柔软、亲密与长期陪伴。",
        paper: Color(jieziHex: "#F6F0EB"),
        brand: Color(jieziHex: "#75696F"),
        light: Color(jieziHex: "#C77C72"),
        space: Color(jieziHex: "#3B3038"),
        ink: Color(jieziHex: "#2E2530"),
        muted: Color(jieziHex: "#7A6F76"),
        coral: Color(jieziHex: "#B85A4E")
    )

    static let tea = JieziGeneratedPalette(
        id: "tea", name: "苔茶暖金", description: "苔绿与茶金形成朴素、安静、耐看的东方生活感。",
        paper: Color(jieziHex: "#F3EFDF"),
        brand: Color(jieziHex: "#66704A"),
        light: Color(jieziHex: "#BD8D46"),
        space: Color(jieziHex: "#353D26"),
        ink: Color(jieziHex: "#2A2F1E"),
        muted: Color(jieziHex: "#6F7059"),
        coral: Color(jieziHex: "#AC5F40")
    )

    static let moon = JieziGeneratedPalette(
        id: "moon", name: "月白远青", description: "以月白与远山青平衡现代科技感和东方留白。",
        paper: Color(jieziHex: "#F0F2F1"),
        brand: Color(jieziHex: "#416775"),
        light: Color(jieziHex: "#C7B06E"),
        space: Color(jieziHex: "#142C35"),
        ink: Color(jieziHex: "#1C2C32"),
        muted: Color(jieziHex: "#5F7480"),
        coral: Color(jieziHex: "#A8554A")
    )

    static let springWood = JieziGeneratedPalette(
        id: "springWood", name: "枯木逢春", description: "第一版正式主题。全暖调的侘寂设计，以枯木褐、晚柿红和焦木深夜形成安全、私密的日记本气质。",
        paper: Color(jieziHex: "#F3EFE6"),
        brand: Color(jieziHex: "#6E5A4B"),
        light: Color(jieziHex: "#D07A55"),
        space: Color(jieziHex: "#29211C"),
        ink: Color(jieziHex: "#241D19"),
        muted: Color(jieziHex: "#6F6258"),
        coral: Color(jieziHex: "#B4523A")
    )

    static let temple = JieziGeneratedPalette(
        id: "temple", name: "古刹苔痕", description: "候选主题。以古刹石壁、苔痕与微弱金光表达枯寂、禅意和历史厚度。",
        paper: Color(jieziHex: "#EBECE6"),
        brand: Color(jieziHex: "#3A4D40"),
        light: Color(jieziHex: "#D9A752"),
        space: Color(jieziHex: "#1B241E"),
        ink: Color(jieziHex: "#1C241F"),
        muted: Color(jieziHex: "#5E6B61"),
        coral: Color(jieziHex: "#A65543")
    )

    /// 全部主题清单，供设置页展示与切换
    static let all: [JieziGeneratedPalette] = [
        .cyan,
        .xuan,
        .paper,
        .jade,
        .lotus,
        .tea,
        .moon,
        .springWood,
        .temple,
    ]

    /// iOS 默认主题
    static let defaultPalette: JieziGeneratedPalette = .cyan
}

// MARK: - 主题运行时管理器（ObservableObject）

final class JieziThemeManager: ObservableObject {
    /// 全局共享实例。App 根部应使用 @StateObject 持有同一实例并 environmentObject 注入，
    /// 各处读取请用注入的实例，不要自行新建。
    static let shared = JieziThemeManager()

    @Published var palette: JieziGeneratedPalette
    @Published var hourOffset: Int = 0

    init() {
        self.palette = .defaultPalette
    }

    /// 历史 jiezi.theme.id 保留，但不再控制应用外观。
    func switchTo(_ id: String) {}
}

// MARK: - iOS 原型五域场景 Token

struct JieziSceneTokens {
    let background: [Color]
    let accent: Color
    let dataAccent: Color
    let pagerAccent: Color
    let foreground: Color
    let muted: Color
    let surface: Color
    let glow: Color
    let glowOpacity: Double
    let usesDiagonalTexture: Bool
    let stripeWidth: CGFloat
    let textureWash: [Gradient.Stop]
}

enum JieziScene {
    static let expense = JieziSceneTokens(background: [Color(jieziHex: "#EADCC4"), Color(jieziHex: "#F1E8D8"), Color(jieziHex: "#F5F1E7")], accent: Color(jieziHex: "#426E63"), dataAccent: Color(jieziHex: "#C2410C"), pagerAccent: Color(jieziHex: "#C2410C"), foreground: Color(jieziHex: "#202A27"), muted: Color(jieziHex: "#6E7773"), surface: Color(jieziHex: "#FBF9F4"), glow: Color(jieziHex: "#DCBF74"), glowOpacity: 0.45, usesDiagonalTexture: false, stripeWidth: 0, textureWash: [])
    static let sleep = JieziSceneTokens(background: [Color(jieziHex: "#1C2140"), Color(jieziHex: "#17312D"), Color(jieziHex: "#0F1E1C")], accent: Color(jieziHex: "#DCBF74"), dataAccent: Color(jieziHex: "#9A96F0"), pagerAccent: Color(jieziHex: "#9A96F0"), foreground: Color(jieziHex: "#F5F1E7"), muted: Color(jieziHex: "#C7C9D0"), surface: Color(jieziHex: "#10211F"), glow: Color(jieziHex: "#6E78C8"), glowOpacity: 0.35, usesDiagonalTexture: false, stripeWidth: 0, textureWash: [])
    static let food = JieziSceneTokens(background: [Color(jieziHex: "#F2DCC4"), Color(jieziHex: "#F4EADB"), Color(jieziHex: "#F5F1E7")], accent: Color(jieziHex: "#C2410C"), dataAccent: Color(jieziHex: "#EA580C"), pagerAccent: Color(jieziHex: "#EA580C"), foreground: Color(jieziHex: "#202A27"), muted: Color(jieziHex: "#6E7773"), surface: Color(jieziHex: "#FBF9F4"), glow: Color(jieziHex: "#EA580C"), glowOpacity: 0.22, usesDiagonalTexture: false, stripeWidth: 0, textureWash: [])
    static let sport = JieziSceneTokens(background: [Color(jieziHex: "#D5E2D6"), Color(jieziHex: "#E6EBE0"), Color(jieziHex: "#F5F1E7")], accent: Color(jieziHex: "#426E63"), dataAccent: Color(jieziHex: "#B45309"), pagerAccent: Color(jieziHex: "#B45309"), foreground: Color(jieziHex: "#202A27"), muted: Color(jieziHex: "#6E7773"), surface: Color(jieziHex: "#FBF9F4"), glow: Color(jieziHex: "#DCBF74"), glowOpacity: 0.4, usesDiagonalTexture: false, stripeWidth: 0, textureWash: [])
    static let reading = JieziSceneTokens(background: [Color(jieziHex: "#4A5E6E"), Color(jieziHex: "#43566A"), Color(jieziHex: "#10211F")], accent: Color(jieziHex: "#DCBF74"), dataAccent: Color(jieziHex: "#DCBF74"), pagerAccent: Color(jieziHex: "#DCBF74"), foreground: Color(jieziHex: "#F5F1E7"), muted: Color(jieziHex: "#C7C9D0"), surface: Color(jieziHex: "#17312D"), glow: Color(jieziHex: "#10211F"), glowOpacity: 0, usesDiagonalTexture: true, stripeWidth: 10, textureWash: [.init(color: Color(jieziHex: "#10211F").opacity(0.35), location: 0), .init(color: Color(jieziHex: "#10211F").opacity(0.82), location: 0.6), .init(color: Color(jieziHex: "#10211F").opacity(1), location: 1)])

    static func tokens(for domain: String) -> JieziSceneTokens {
        switch domain {
        case "expense": return JieziScene.expense
        case "sleep": return JieziScene.sleep
        case "food": return JieziScene.food
        case "sport": return JieziScene.sport
        case "reading": return JieziScene.reading
        default: return JieziScene.expense
        }
    }
}

enum JieziPrototypeLayout {
    static let page_inset: CGFloat = 14
    static let metric_inset: CGFloat = 20
    static let hero_min_height: CGFloat = 170
    static let cat_width: CGFloat = 140
    static let cat_height: CGFloat = 150
    static let cat_viewbox_size: CGFloat = 200
    static let cat_stroke_width: CGFloat = 2.4
    static let cat_face_stroke_width: CGFloat = 3.4
    static let column_gap: CGFloat = 12
    static let card_inset: CGFloat = 16
    static let card_radius: CGFloat = 24
    static let sheet_radius: CGFloat = 32
    static let selected_page_width: CGFloat = 22
    static let page_dot_size: CGFloat = 8
    static let page_dot_gap: CGFloat = 6
    static let page_dot_hit_width: CGFloat = 44
    static let page_dot_drag_distance: CGFloat = 8
    static let add_button_size: CGFloat = 48
    static let week_day_height: CGFloat = 52
    static let date_strip_month_threshold: CGFloat = 40
    static let calendar_day_height: CGFloat = 44
    static let calendar_arrow_hit_size: CGFloat = 44
    static let food_energy_reference_height: CGFloat = 90
    static let food_energy_point_size: CGFloat = 64
    static let food_photo_size: CGFloat = 64
    static let food_photo_radius: CGFloat = 12
}

enum JieziPrototypeMotion {
    static let page_transition_ms: TimeInterval = 0.45
    static let background_ms: TimeInterval = 0.7
    static let cat_retract_ms: TimeInterval = 0.36
    static let cat_draw_ms: TimeInterval = 1.15
    static let cat_face_delay_ms: TimeInterval = 0.85
    static let cat_face_hide_ms: TimeInterval = 0.12
    static let cat_reset_frame_ms: TimeInterval = 0.016
    static let cat_face_fade_ms: TimeInterval = 0.35
    static let cat_decoration_fade_ms: TimeInterval = 0.5
    static let calendar_feedback_ms: TimeInterval = 0.26
}

enum JieziCatPose: String {
    case expense
    case sleep
    case food
    case sport
    case reading

    static func forDomain(_ domain: String) -> JieziCatPose {
        JieziCatPose(rawValue: domain) ?? .expense
    }

    var decoration: (cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, color: Color, opacity: Double) {
        switch self {
        case .expense: return (cx: 134, cy: 124, rx: 12, ry: 12, color: Color(jieziHex: "#DCBF74"), opacity: 0.6)
        case .sleep: return (cx: 162, cy: 46, rx: 14, ry: 14, color: Color(jieziHex: "#F3E3A6"), opacity: 0.9)
        case .food: return (cx: 120, cy: 124, rx: 30, ry: 7, color: Color(jieziHex: "#FFFFFF"), opacity: 0.95)
        case .sport: return (cx: 92, cy: 171, rx: 78, ry: 4, color: Color(jieziHex: "#426E63"), opacity: 0.28)
        case .reading: return (cx: 156, cy: 56, rx: 10, ry: 10, color: Color(jieziHex: "#F3D99A"), opacity: 0.85)
        }
    }
}

struct JieziCatShape: Shape {
    let pose: JieziCatPose
    var drawsFace = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if drawsFace {
            switch pose {
            case .expense:
                path.move(to: CGPoint(x: 90, y: 88))
                path.addCurve(to: CGPoint(x: 90, y: 89.5), control1: CGPoint(x: 90, y: 88), control2: CGPoint(x: 90, y: 89.5))
                path.move(to: CGPoint(x: 110, y: 88))
                path.addCurve(to: CGPoint(x: 110, y: 89.5), control1: CGPoint(x: 110, y: 88), control2: CGPoint(x: 110, y: 89.5))
            case .sleep:
                path.move(to: CGPoint(x: 50, y: 140))
                path.addCurve(to: CGPoint(x: 56, y: 140), control1: CGPoint(x: 52, y: 142), control2: CGPoint(x: 54, y: 142))
                path.move(to: CGPoint(x: 64, y: 140))
                path.addCurve(to: CGPoint(x: 70, y: 140), control1: CGPoint(x: 66, y: 142), control2: CGPoint(x: 68, y: 142))
                path.move(to: CGPoint(x: 100, y: 92))
                path.addCurve(to: CGPoint(x: 108, y: 92), control1: CGPoint(x: 100, y: 92), control2: CGPoint(x: 108, y: 92))
                path.addCurve(to: CGPoint(x: 100, y: 100), control1: CGPoint(x: 108, y: 92), control2: CGPoint(x: 100, y: 100))
                path.addCurve(to: CGPoint(x: 108, y: 100), control1: CGPoint(x: 100, y: 100), control2: CGPoint(x: 108, y: 100))
                path.move(to: CGPoint(x: 114, y: 78))
                path.addCurve(to: CGPoint(x: 120, y: 78), control1: CGPoint(x: 114, y: 78), control2: CGPoint(x: 120, y: 78))
                path.addCurve(to: CGPoint(x: 114, y: 84), control1: CGPoint(x: 120, y: 78), control2: CGPoint(x: 114, y: 84))
                path.addCurve(to: CGPoint(x: 120, y: 84), control1: CGPoint(x: 114, y: 84), control2: CGPoint(x: 120, y: 84))
            case .food:
                path.move(to: CGPoint(x: 83, y: 88))
                path.addCurve(to: CGPoint(x: 91, y: 88), control1: CGPoint(x: 85.666667, y: 85.333333), control2: CGPoint(x: 88.333333, y: 85.333333))
                path.move(to: CGPoint(x: 105, y: 88))
                path.addCurve(to: CGPoint(x: 113, y: 88), control1: CGPoint(x: 107.666667, y: 85.333333), control2: CGPoint(x: 110.333333, y: 85.333333))
            case .sport:
                path.move(to: CGPoint(x: 54, y: 133))
                path.addCurve(to: CGPoint(x: 54, y: 134.5), control1: CGPoint(x: 54, y: 133), control2: CGPoint(x: 54, y: 134.5))
                path.move(to: CGPoint(x: 68, y: 131))
                path.addCurve(to: CGPoint(x: 68, y: 132.5), control1: CGPoint(x: 68, y: 131), control2: CGPoint(x: 68, y: 132.5))
            case .reading:
                path.move(to: CGPoint(x: 88, y: 90))
                path.addCurve(to: CGPoint(x: 88, y: 91.2), control1: CGPoint(x: 88, y: 90), control2: CGPoint(x: 88, y: 91.2))
                path.move(to: CGPoint(x: 108, y: 90))
                path.addCurve(to: CGPoint(x: 108, y: 91.2), control1: CGPoint(x: 108, y: 90), control2: CGPoint(x: 108, y: 91.2))
            }
        } else {
            switch pose {
            case .expense:
                path.move(to: CGPoint(x: 34, y: 138))
                path.addCurve(to: CGPoint(x: 46, y: 168), control1: CGPoint(x: 18, y: 140), control2: CGPoint(x: 16, y: 168))
                path.addCurve(to: CGPoint(x: 64, y: 118), control1: CGPoint(x: 60, y: 168), control2: CGPoint(x: 58, y: 140))
                path.addCurve(to: CGPoint(x: 66, y: 80), control1: CGPoint(x: 68, y: 104), control2: CGPoint(x: 62, y: 92))
                path.addCurve(to: CGPoint(x: 70, y: 52), control1: CGPoint(x: 66, y: 70), control2: CGPoint(x: 66, y: 60))
                path.addCurve(to: CGPoint(x: 88, y: 66), control1: CGPoint(x: 76, y: 58), control2: CGPoint(x: 82, y: 64))
                path.addCurve(to: CGPoint(x: 112, y: 66), control1: CGPoint(x: 96, y: 64), control2: CGPoint(x: 104, y: 64))
                path.addCurve(to: CGPoint(x: 130, y: 50), control1: CGPoint(x: 118, y: 60), control2: CGPoint(x: 124, y: 54))
                path.addCurve(to: CGPoint(x: 130, y: 78), control1: CGPoint(x: 132, y: 60), control2: CGPoint(x: 132, y: 70))
                path.addCurve(to: CGPoint(x: 108, y: 106), control1: CGPoint(x: 134, y: 92), control2: CGPoint(x: 124, y: 104))
                path.addCurve(to: CGPoint(x: 122, y: 124), control1: CGPoint(x: 112, y: 114), control2: CGPoint(x: 116, y: 120))
                path.addCurve(to: CGPoint(x: 134, y: 136), control1: CGPoint(x: 122, y: 130.627417), control2: CGPoint(x: 127.372583, y: 136))
                path.addCurve(to: CGPoint(x: 146, y: 124), control1: CGPoint(x: 140.627417, y: 136), control2: CGPoint(x: 146, y: 130.627417))
                path.addCurve(to: CGPoint(x: 134, y: 112), control1: CGPoint(x: 146, y: 117.372583), control2: CGPoint(x: 140.627417, y: 112))
                path.addCurve(to: CGPoint(x: 122, y: 124), control1: CGPoint(x: 127.372583, y: 112), control2: CGPoint(x: 122, y: 117.372583))
                path.addCurve(to: CGPoint(x: 126, y: 166), control1: CGPoint(x: 122, y: 140), control2: CGPoint(x: 118, y: 154))
                path.addCurve(to: CGPoint(x: 164, y: 168), control1: CGPoint(x: 130, y: 168), control2: CGPoint(x: 136, y: 168))
            case .sleep:
                path.move(to: CGPoint(x: 20, y: 168))
                path.addCurve(to: CGPoint(x: 40, y: 168), control1: CGPoint(x: 20, y: 168), control2: CGPoint(x: 40, y: 168))
                path.addCurve(to: CGPoint(x: 48, y: 134), control1: CGPoint(x: 34, y: 156), control2: CGPoint(x: 36, y: 140))
                path.addCurve(to: CGPoint(x: 54, y: 110), control1: CGPoint(x: 48, y: 124), control2: CGPoint(x: 50, y: 116))
                path.addCurve(to: CGPoint(x: 70, y: 122), control1: CGPoint(x: 60, y: 116), control2: CGPoint(x: 64, y: 120))
                path.addCurve(to: CGPoint(x: 86, y: 106), control1: CGPoint(x: 74, y: 116), control2: CGPoint(x: 80, y: 110))
                path.addCurve(to: CGPoint(x: 86, y: 130), control1: CGPoint(x: 88, y: 116), control2: CGPoint(x: 88, y: 124))
                path.addCurve(to: CGPoint(x: 166, y: 140), control1: CGPoint(x: 110, y: 112), control2: CGPoint(x: 154, y: 116))
                path.addCurve(to: CGPoint(x: 144, y: 168), control1: CGPoint(x: 174, y: 156), control2: CGPoint(x: 164, y: 168))
                path.addCurve(to: CGPoint(x: 72, y: 162), control1: CGPoint(x: 120, y: 168), control2: CGPoint(x: 92, y: 168))
                path.addCurve(to: CGPoint(x: 74, y: 150), control1: CGPoint(x: 62, y: 158), control2: CGPoint(x: 64, y: 148))
            case .food:
                path.move(to: CGPoint(x: 34, y: 138))
                path.addCurve(to: CGPoint(x: 46, y: 168), control1: CGPoint(x: 18, y: 140), control2: CGPoint(x: 16, y: 168))
                path.addCurve(to: CGPoint(x: 64, y: 118), control1: CGPoint(x: 60, y: 168), control2: CGPoint(x: 58, y: 140))
                path.addCurve(to: CGPoint(x: 66, y: 80), control1: CGPoint(x: 68, y: 104), control2: CGPoint(x: 62, y: 92))
                path.addCurve(to: CGPoint(x: 70, y: 52), control1: CGPoint(x: 66, y: 70), control2: CGPoint(x: 66, y: 60))
                path.addCurve(to: CGPoint(x: 88, y: 66), control1: CGPoint(x: 76, y: 58), control2: CGPoint(x: 82, y: 64))
                path.addCurve(to: CGPoint(x: 112, y: 66), control1: CGPoint(x: 96, y: 64), control2: CGPoint(x: 104, y: 64))
                path.addCurve(to: CGPoint(x: 130, y: 50), control1: CGPoint(x: 118, y: 60), control2: CGPoint(x: 124, y: 54))
                path.addCurve(to: CGPoint(x: 130, y: 78), control1: CGPoint(x: 132, y: 60), control2: CGPoint(x: 132, y: 70))
                path.addCurve(to: CGPoint(x: 108, y: 106), control1: CGPoint(x: 134, y: 92), control2: CGPoint(x: 124, y: 104))
                path.addCurve(to: CGPoint(x: 88, y: 126), control1: CGPoint(x: 104, y: 116), control2: CGPoint(x: 96, y: 122))
                path.addCurve(to: CGPoint(x: 120, y: 156), control1: CGPoint(x: 88, y: 146), control2: CGPoint(x: 102, y: 156))
                path.addCurve(to: CGPoint(x: 152, y: 126), control1: CGPoint(x: 138, y: 156), control2: CGPoint(x: 152, y: 146))
                path.addCurve(to: CGPoint(x: 158, y: 168), control1: CGPoint(x: 152, y: 142), control2: CGPoint(x: 148, y: 160))
                path.addCurve(to: CGPoint(x: 172, y: 168), control1: CGPoint(x: 158, y: 168), control2: CGPoint(x: 172, y: 168))
            case .sport:
                path.move(to: CGPoint(x: 174, y: 62))
                path.addCurve(to: CGPoint(x: 164, y: 58), control1: CGPoint(x: 178, y: 56), control2: CGPoint(x: 170, y: 50))
                path.addCurve(to: CGPoint(x: 150, y: 98), control1: CGPoint(x: 156, y: 68), control2: CGPoint(x: 160, y: 84))
                path.addCurve(to: CGPoint(x: 160, y: 168), control1: CGPoint(x: 158, y: 116), control2: CGPoint(x: 158, y: 146))
                path.addCurve(to: CGPoint(x: 146, y: 168), control1: CGPoint(x: 160, y: 168), control2: CGPoint(x: 146, y: 168))
                path.addCurve(to: CGPoint(x: 128, y: 146), control1: CGPoint(x: 146, y: 156), control2: CGPoint(x: 140, y: 148))
                path.addCurve(to: CGPoint(x: 72, y: 160), control1: CGPoint(x: 108, y: 144), control2: CGPoint(x: 86, y: 150))
                path.addCurve(to: CGPoint(x: 22, y: 168), control1: CGPoint(x: 72, y: 160), control2: CGPoint(x: 22, y: 168))
                path.addCurve(to: CGPoint(x: 46, y: 148), control1: CGPoint(x: 30, y: 162), control2: CGPoint(x: 40, y: 156))
                path.addCurve(to: CGPoint(x: 44, y: 116), control1: CGPoint(x: 42, y: 136), control2: CGPoint(x: 42, y: 124))
                path.addCurve(to: CGPoint(x: 62, y: 124), control1: CGPoint(x: 50, y: 120), control2: CGPoint(x: 56, y: 124))
                path.addCurve(to: CGPoint(x: 78, y: 108), control1: CGPoint(x: 66, y: 118), control2: CGPoint(x: 72, y: 112))
                path.addCurve(to: CGPoint(x: 78, y: 136), control1: CGPoint(x: 80, y: 118), control2: CGPoint(x: 80, y: 128))
                path.addCurve(to: CGPoint(x: 112, y: 134), control1: CGPoint(x: 88, y: 140), control2: CGPoint(x: 100, y: 142))
                path.addCurve(to: CGPoint(x: 150, y: 98), control1: CGPoint(x: 126, y: 122), control2: CGPoint(x: 138, y: 100))
            case .reading:
                path.move(to: CGPoint(x: 34, y: 138))
                path.addCurve(to: CGPoint(x: 46, y: 168), control1: CGPoint(x: 18, y: 140), control2: CGPoint(x: 16, y: 168))
                path.addCurve(to: CGPoint(x: 64, y: 118), control1: CGPoint(x: 60, y: 168), control2: CGPoint(x: 58, y: 140))
                path.addCurve(to: CGPoint(x: 66, y: 80), control1: CGPoint(x: 68, y: 104), control2: CGPoint(x: 62, y: 92))
                path.addCurve(to: CGPoint(x: 70, y: 52), control1: CGPoint(x: 66, y: 70), control2: CGPoint(x: 66, y: 60))
                path.addCurve(to: CGPoint(x: 88, y: 66), control1: CGPoint(x: 76, y: 58), control2: CGPoint(x: 82, y: 64))
                path.addCurve(to: CGPoint(x: 112, y: 66), control1: CGPoint(x: 96, y: 64), control2: CGPoint(x: 104, y: 64))
                path.addCurve(to: CGPoint(x: 130, y: 50), control1: CGPoint(x: 118, y: 60), control2: CGPoint(x: 124, y: 54))
                path.addCurve(to: CGPoint(x: 130, y: 78), control1: CGPoint(x: 132, y: 60), control2: CGPoint(x: 132, y: 70))
                path.addCurve(to: CGPoint(x: 108, y: 106), control1: CGPoint(x: 134, y: 92), control2: CGPoint(x: 124, y: 104))
                path.addCurve(to: CGPoint(x: 96, y: 118), control1: CGPoint(x: 110, y: 114), control2: CGPoint(x: 104, y: 118))
                path.addCurve(to: CGPoint(x: 84, y: 116), control1: CGPoint(x: 96, y: 118), control2: CGPoint(x: 84, y: 116))
                path.addCurve(to: CGPoint(x: 88, y: 144), control1: CGPoint(x: 84, y: 126), control2: CGPoint(x: 86, y: 136))
                path.addCurve(to: CGPoint(x: 118, y: 152), control1: CGPoint(x: 98, y: 146), control2: CGPoint(x: 110, y: 148))
                path.addCurve(to: CGPoint(x: 118, y: 124), control1: CGPoint(x: 118, y: 142), control2: CGPoint(x: 118, y: 132))
                path.addCurve(to: CGPoint(x: 152, y: 116), control1: CGPoint(x: 128, y: 118), control2: CGPoint(x: 140, y: 116))
                path.addCurve(to: CGPoint(x: 148, y: 144), control1: CGPoint(x: 150, y: 126), control2: CGPoint(x: 150, y: 136))
                path.addCurve(to: CGPoint(x: 118, y: 152), control1: CGPoint(x: 138, y: 146), control2: CGPoint(x: 126, y: 148))
                path.addCurve(to: CGPoint(x: 134, y: 168), control1: CGPoint(x: 120, y: 160), control2: CGPoint(x: 124, y: 166))
                path.addCurve(to: CGPoint(x: 164, y: 168), control1: CGPoint(x: 134, y: 168), control2: CGPoint(x: 164, y: 168))
            }
        }
        let extent = JieziPrototypeLayout.cat_viewbox_size
        let scale = min(rect.width / extent, rect.height / extent)
        let x = rect.midX - extent / 2 * scale
        let y = rect.midY - extent / 2 * scale
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
            .applying(CGAffineTransform(translationX: x, y: y))
    }
}

// MARK: - 时间相位（与 PWA 一致，相邻相位线性插值）

struct JieziPhase {
    let id: String
    let name: String
    let start: Int
    let end: Int
    let warmth: Double
    let brightness: Double
    let saturation: Double
    let spaceShift: Double

    /// 相邻相位在边界前后各 transitionMinutes/2 分钟内线性插值
    static let transitionMinutes: Double = 45

    static let deepNight = JieziPhase(id: "deepNight", name: "深夜", start: 0, end: 5, warmth: -12, brightness: -24, saturation: -8, spaceShift: -18)
    static let dawn = JieziPhase(id: "dawn", name: "破晓", start: 5, end: 8, warmth: 10, brightness: 8, saturation: -4, spaceShift: -7)
    static let morning = JieziPhase(id: "morning", name: "晨光", start: 8, end: 11, warmth: 5, brightness: 14, saturation: 0, spaceShift: 0)
    static let noon = JieziPhase(id: "noon", name: "日中", start: 11, end: 15, warmth: 0, brightness: 18, saturation: -6, spaceShift: 5)
    static let afternoon = JieziPhase(id: "afternoon", name: "午后", start: 15, end: 18, warmth: 8, brightness: 8, saturation: 2, spaceShift: 0)
    static let dusk = JieziPhase(id: "dusk", name: "暮色", start: 18, end: 21, warmth: 18, brightness: -2, saturation: 8, spaceShift: -8)
    static let night = JieziPhase(id: "night", name: "入夜", start: 21, end: 24, warmth: -4, brightness: -16, saturation: -2, spaceShift: -15)

    static let all: [JieziPhase] = [
        .deepNight,
        .dawn,
        .morning,
        .noon,
        .afternoon,
        .dusk,
        .night,
    ]

    static func at(hour: Int) -> JieziPhase {
        let h = ((hour % 24) + 24) % 24
        return all.first(where: { h >= $0.start && h < $0.end }) ?? .deepNight
    }
}

/// 插值后的相位数值（用于实时调色）
struct JieziPhaseValues {
    let warmth: Double
    let brightness: Double
    let saturation: Double
    let spaceShift: Double
}

extension JieziPhase {
    /// 计算某时刻的插值相位数值。边界前后 transitionMinutes/2 内与相邻相位线性混合，避免整点跳变。
    static func values(atHour hour: Int, minute: Int = 0) -> JieziPhaseValues {
        let t = (Double(hour) * 60 + Double(minute)).truncatingRemainder(dividingBy: 1440)
        let tr = transitionMinutes / 2
        guard let idx = all.firstIndex(where: { t >= Double($0.start) * 60 && t < Double($0.end) * 60 }) else {
            return JieziPhaseValues(warmth: deepNight.warmth, brightness: deepNight.brightness, saturation: deepNight.saturation, spaceShift: deepNight.spaceShift)
        }
        let p = all[idx]
        let startM = Double(p.start) * 60
        let endM = Double(p.end) * 60
        if t - startM < tr {
            let prev = all[(idx - 1 + all.count) % all.count]
            let progress = ((t - startM) + tr) / (2 * tr)
            return lerp(prev, p, progress)
        } else if endM - t < tr {
            let next = all[(idx + 1) % all.count]
            let progress = (t - (endM - tr)) / (2 * tr)
            return lerp(p, next, progress)
        }
        return JieziPhaseValues(warmth: p.warmth, brightness: p.brightness, saturation: p.saturation, spaceShift: p.spaceShift)
    }

    private static func lerp(_ a: JieziPhase, _ b: JieziPhase, _ k: Double) -> JieziPhaseValues {
        JieziPhaseValues(
            warmth: a.warmth + (b.warmth - a.warmth) * k,
            brightness: a.brightness + (b.brightness - a.brightness) * k,
            saturation: a.saturation + (b.saturation - a.saturation) * k,
            spaceShift: a.spaceShift + (b.spaceShift - a.spaceShift) * k
        )
    }
}

// MARK: - 间距 Token

enum JieziSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xl2: CGFloat = 24
    static let xl3: CGFloat = 32
    static let xl4: CGFloat = 40
    static let xl5: CGFloat = 48
    static let xl6: CGFloat = 64
    static let xl7: CGFloat = 80

    enum Semantic {
        static let page_padding: CGFloat = 16
        static let card_padding: CGFloat = 18
        static let card_padding_lg: CGFloat = 24
        static let section_gap: CGFloat = 32
        static let item_gap: CGFloat = 12
        static let item_gap_tight: CGFloat = 8
    }
}

// MARK: - 圆角 Token

enum JieziRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 18
    static let xl2: CGFloat = 24
    static let xl3: CGFloat = 32
    static let pill: CGFloat = 999

    enum Semantic {
        static let card: CGFloat = 24
        static let button: CGFloat = 18
        static let input: CGFloat = 12
        static let chip: CGFloat = 999
        static let sheet: CGFloat = 32
    }
}

// MARK: - 阴影 Token（按 palette 解析颜色，主题感知）

struct JieziShadow {
    let color: Color
    let alpha: Double
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum JieziShadows {
    static let none = JieziShadow(color: .clear, alpha: 0, radius: 0, x: 0, y: 0)
    static func sm(_ p: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> JieziShadow {
        JieziShadow(color: p.space, alpha: 0.06, radius: 6, x: 0, y: 2)
    }
    static func md(_ p: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> JieziShadow {
        JieziShadow(color: p.space, alpha: 0.08, radius: 14, x: 0, y: 6)
    }
    static func lg(_ p: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> JieziShadow {
        JieziShadow(color: p.space, alpha: 0.08, radius: 22, x: 0, y: 12)
    }
    static func xl(_ p: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> JieziShadow {
        JieziShadow(color: p.space, alpha: 0.12, radius: 32, x: 0, y: 18)
    }
    static func brand(_ p: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> JieziShadow {
        JieziShadow(color: p.brand, alpha: 0.18, radius: 14, x: 0, y: 8)
    }

    enum Semantic {
        /// 语义阴影：card → lg
        static func card(_ p: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> JieziShadow { JieziShadows.lg(p) }
        /// 语义阴影：modal → xl
        static func modal(_ p: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> JieziShadow { JieziShadows.xl(p) }
        /// 语义阴影：primary_button → brand
        static func primary_button(_ p: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> JieziShadow { JieziShadows.brand(p) }
    }
}

extension View {
    func jieziShadow(_ shadow: JieziShadow) -> some View {
        self.shadow(color: shadow.color.opacity(shadow.alpha), radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

// MARK: - 字体 Token（HIG 层级）

enum JieziFont {
    static let caption2 = Font.system(.caption2).weight(.regular)
    static let caption = Font.system(.caption).weight(.regular)
    static let footnote = Font.system(.footnote).weight(.regular)
    static let subheadline = Font.system(.subheadline).weight(.regular)
    static let body = Font.system(.body).weight(.regular)
    static let callout = Font.system(.callout).weight(.medium)
    static let headline = Font.system(.headline).weight(.semibold)
    static let title3 = Font.system(.title3).weight(.semibold)
    static let title2 = Font.system(.title2).weight(.semibold)
    static let title1 = Font.system(.title).weight(.bold)
    static let largeTitle = Font.system(.largeTitle).weight(.bold)
}

enum JieziFontFamily {
    static let sans = "system"
    static let serif = "NotoSerifSC-ExtraLight"
    static let numeric = "Nunito-ExtraLight"
}

// MARK: - 语义字体角色（「芥子味」：serif 标题 + rounded 金额）
/// 注意：money 系列角色在使用处追加 .monospacedDigit()（SSOT numeric 规则）。
enum JieziType {
    /// 页面主标题、品牌门面（如「个人数据平台」）
    static let display = Font.custom(JieziFontFamily.serif, size: 28, relativeTo: .title).weight(.bold)
    /// 空态大标题、启动页书法字位
    static let displayLarge = Font.custom(JieziFontFamily.serif, size: 34, relativeTo: .largeTitle).weight(.bold)
    /// 财务主数字（净额估算、大金额输入）
    static let moneyHero = Font.custom(JieziFontFamily.numeric, size: 34, relativeTo: .largeTitle).weight(.bold)
    /// 卡片级金额、日汇总数字
    static let moneyCard = Font.custom(JieziFontFamily.numeric, size: 22, relativeTo: .title2).weight(.semibold)
    /// 列表行内金额
    static let moneyInline = Font.custom(JieziFontFamily.numeric, size: 17, relativeTo: .headline).weight(.semibold)
    /// 区块标题（如「财务状态」「每日明细」）
    static let sectionTitle = Font.system(.title3).weight(.semibold)
    /// 卡片内标题、列表行主文字
    static let cardTitle = Font.system(.headline).weight(.semibold)
    /// 按钮文字
    static let button = Font.system(.callout).weight(.semibold)
    /// 分类 Chip、胶囊标签
    static let chip = Font.system(.footnote).weight(.medium)
    /// 指标说明文字（如「可用现金」）
    static let metricLabel = Font.system(.caption).weight(.regular)
    static let prototypeBrand = Font.custom(JieziFontFamily.serif, size: 20, relativeTo: .title2).weight(.bold)
    static let prototypeHero = Font.custom(JieziFontFamily.numeric, size: 44, relativeTo: .largeTitle).weight(.bold)
    static let prototypeSleepHero = Font.custom(JieziFontFamily.numeric, size: 40, relativeTo: .largeTitle).weight(.bold)
    static let prototypeBook = Font.custom(JieziFontFamily.serif, size: 32, relativeTo: .title).weight(.bold)
    static let prototypeOnboarding = Font.custom(JieziFontFamily.serif, size: 32, relativeTo: .largeTitle).weight(.bold)
}

// MARK: - 描边 Token（金线 0.5mm 为骨）

struct JieziStrokeStyle {
    let color: Color
    let width: CGFloat
}

enum JieziStroke {
    /// 金线细描边：印章框、插画框、装饰分隔，新中式的骨
    static func gold_hairline(_ p: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> JieziStrokeStyle {
        JieziStrokeStyle(color: p.light.opacity(0.85), width: 0.5)
    }
    /// 卡片描边（与 glass.card 一致）
    static func brand_hairline(_ p: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> JieziStrokeStyle {
        JieziStrokeStyle(color: p.brand.opacity(0.11), width: 1)
    }
    /// 列表行分隔线
    static func divider(_ p: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> JieziStrokeStyle {
        JieziStrokeStyle(color: p.ink.opacity(0.08), width: 0.5)
    }
    /// 输入框聚焦态
    static func focus_ring(_ p: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> JieziStrokeStyle {
        JieziStrokeStyle(color: p.brand.opacity(0.45), width: 1.5)
    }
}

// MARK: - 图标尺寸 Token

enum JieziIcon {
    /// 行内小图标、chevron
    static let xs: CGFloat = 16
    /// 辅助图标
    static let sm: CGFloat = 20
    /// Tab 图标、工具栏
    static let md: CGFloat = 24
    /// 强调图标
    static let lg: CGFloat = 28
    /// 数据域图标容器
    static let xl: CGFloat = 34
    /// 列表行图标块容器
    static let xl2: CGFloat = 40
    /// 空态/功能大图标容器
    static let xl3: CGFloat = 48

    enum Semantic {
        static let tab: CGFloat = 24
        static let list_row_block: CGFloat = 40
        static let domain_block: CGFloat = 34
    }
}

// MARK: - 数据域色（全局固定，不随主题切换）

enum JieziDomainColor {
    /// 消费·赭石
    static let expense = Color(jieziHex: "#C2410C")
    /// 收入·黛蓝
    static let income = Color(jieziHex: "#1565C0")
    /// 运动·琥珀
    static let sport = Color(jieziHex: "#B45309")
    /// 睡眠·靛青
    static let sleep = Color(jieziHex: "#4338CA")
    /// 阅读·青黛
    static let reading = Color(jieziHex: "#0369A1")
    /// 饮食·朱橙
    static let food = Color(jieziHex: "#EA580C")
    /// 钱包·紫檀
    static let wallet = Color(jieziHex: "#7C3AED")

    static func color(for domain: String) -> Color {
        switch domain {
        case "expense": return JieziDomainColor.expense
        case "income": return JieziDomainColor.income
        case "sport": return JieziDomainColor.sport
        case "sleep": return JieziDomainColor.sleep
        case "reading": return JieziDomainColor.reading
        case "food": return JieziDomainColor.food
        case "wallet": return JieziDomainColor.wallet
        default: return JieziThemeManager.shared.palette.brand
        }
    }
}

// MARK: - 艺术版专用色（功能页面禁用）

enum JieziArtColor {
    /// 极细装饰线（0.5mm 以下）
    static let fluorescentBlue = Color(jieziHex: "#4A9EFF")
    /// 底色渲染（仅启动页/营销图）
    static let cinnabar = Color(jieziHex: "#C8381E")
}

// MARK: - 动效 Token

enum JieziDuration {
    static let instant: TimeInterval = 0
    static let fast: TimeInterval = 0.15
    static let normal: TimeInterval = 0.25
    static let slow: TimeInterval = 0.4
    static let deliberate: TimeInterval = 0.6
}

enum JieziEasing {
    static let standard = Animation.easeInOut(duration: JieziDuration.normal)
    static let decelerate = Animation.easeOut(duration: JieziDuration.normal)
    static let accelerate = Animation.easeIn(duration: JieziDuration.normal)
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let gentle = Animation.easeInOut(duration: JieziDuration.normal)
}

// MARK: - 触觉反馈 Token

enum JieziHaptics {
    /// 列表点按、卡片轻点
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    /// 按钮确认、开关切换
    static func confirm() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    /// 芥子吸纳瞬态（「啵」）
    static func absorb() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    /// 入账完成、同步成功
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    /// 识别失败、删除确认
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - 渐变构建器

enum JieziGradient {
    static func pageBackground(palette: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> LinearGradient {
        LinearGradient(
            colors: JieziScene.expense.background,
            startPoint: .top,
            endPoint: .bottomTrailing
        )
    }

    static func sumeruBackground(palette: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> RadialGradient {
        RadialGradient(
            colors: [
                palette.brand.jieziBlended(with: palette.light, amount: 0.16),
                palette.space,
                palette.space.jieziBlended(with: .black, amount: 0.58)
            ],
            center: .center,
            startRadius: 18,
            endRadius: 520
        )
    }

    static func brandWash(palette: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> LinearGradient {
        LinearGradient(
            colors: [
                palette.brand.opacity(0.92),
                palette.brand.jieziBlended(with: palette.space, amount: 0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - 卡片表面修饰符（玻璃卡 / 实卡）

struct JieziCardStyle: ViewModifier {
    let palette: JieziGeneratedPalette
    var solid: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(JieziScene.expense.surface.opacity(solid ? 0.92 : 0.66), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(palette.brand.opacity(0.11), lineWidth: 1)
            }
            .shadow(color: palette.space.opacity(solid ? 0 : 0.07), radius: 22, x: 0, y: 12)
    }
}

extension View {
    /// 芥子卡片：默认玻璃卡（材质+宣纸底色），solid: true 为实卡（列表行/小卡场景）。
    func jieziCard(palette: JieziGeneratedPalette = JieziThemeManager.shared.palette, solid: Bool = false) -> some View {
        modifier(JieziCardStyle(palette: palette, solid: solid))
    }
}
