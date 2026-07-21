import Foundation

struct NativeUserSettings: Equatable {
    var plan = "free"
    var screenshotVisionPrimary = "auto"
    var photoVisionPrimary = "qwen"
    var qwenScreenshotModel = "qwen3.6-flash"
    var qwenPhotoModel = "qwen3.6-flash"
    var qwenScreenshotThinking = false
    var qwenPhotoThinking = false
    var aiInsightProvider = "auto"
    var companionEnabled = true
    var companionMemoryEnabled = true
    var companionPersona = "observer"
    var companionMemoryStrength = "balanced"
    var companionExpressionStyle = "plain"
    var companionCustomNote = ""
    var aiLogsEnabled = false
    var promptOptimizationEnabled = false
    var keepSourceImages = true
    var imageRetentionDays = -1

    var planTitle: String {
        switch plan {
        case "pro": return "Pro"
        case "seed": return "种子用户"
        default: return "免费版"
        }
    }

    var retentionDescription: String {
        if !keepSourceImages { return "新截图识别后不保留原图" }
        switch imageRetentionDays {
        case 7: return "新截图保留 7 天后自动清理"
        case 30: return "新截图保留 30 天后自动清理"
        default: return "新截图永久保留，不自动清理"
        }
    }
}

struct NativeSettingsOption: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
}

enum NativeSettingsOptions {
    static let visionProviders = [
        NativeSettingsOption(id: "auto", title: "自动（推荐）", detail: "根据截图或拍照链路选择 Qwen 模型"),
        NativeSettingsOption(id: "qwen", title: "阿里云百炼 Qwen", detail: "仅使用已配置的 3.6 / 3.7 模型")
    ]

    static let qwenModels = [
        NativeSettingsOption(id: "qwen3.6-flash", title: "3.6 Flash", detail: "速度优先"),
        NativeSettingsOption(id: "qwen3.7-plus", title: "3.7 Plus", detail: "质量优先")
    ]

    static let insightProviders = [
        NativeSettingsOption(id: "auto", title: "自动", detail: "使用 Qwen 完成路由和联动分析"),
        NativeSettingsOption(id: "qwen", title: "阿里云百炼 Qwen", detail: "固定使用 Qwen 分析链路")
    ]

    static let personas = [
        NativeSettingsOption(id: "observer", title: "旁观者", detail: "冷静看见细节，事实为主"),
        NativeSettingsOption(id: "warm", title: "老朋友", detail: "关心但不说教"),
        NativeSettingsOption(id: "sharp", title: "损友", detail: "基于数据轻轻指出问题"),
        NativeSettingsOption(id: "minimal", title: "极简", detail: "尽量压缩为一句话")
    ]

    static let memoryStrengths = [
        NativeSettingsOption(id: "light", title: "轻量", detail: "偶尔引用历史"),
        NativeSettingsOption(id: "balanced", title: "自然", detail: "兼顾当前记录与历史模式"),
        NativeSettingsOption(id: "bold", title: "大胆", detail: "有证据时突出连续变化")
    ]

    static let expressionStyles = [
        NativeSettingsOption(id: "plain", title: "纯文字", detail: "只使用文字"),
        NativeSettingsOption(id: "emoji", title: "Emoji", detail: "偶尔加入贴切表情"),
        NativeSettingsOption(id: "kaomoji", title: "颜文字", detail: "偶尔使用轻量颜文字")
    ]

    static func normalizedVisionProvider(_ value: String, fallback: String = "auto") -> String {
        visionProviders.contains(where: { $0.id == value }) ? value : fallback
    }

    static func normalizedQwenModel(_ value: String, fallback: String = "qwen3.6-flash") -> String {
        qwenModels.contains(where: { $0.id == value }) ? value : fallback
    }

    static func normalizedInsightProvider(_ value: String) -> String {
        insightProviders.contains(where: { $0.id == value }) ? value : "auto"
    }
}

enum NativeExportContent: String, CaseIterable, Identifiable, Hashable {
    case expense, income, allFinance = "all_finance", universal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .expense: return "支出记录"
        case .income: return "收入记录"
        case .allFinance: return "全部财务"
        case .universal: return "通用记录"
        }
    }
}

enum NativeExportRange: String, CaseIterable, Identifiable, Hashable {
    case thisMonth = "this_month", lastMonth = "last_month", lastThreeMonths = "last_3_months", all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .thisMonth: return "本月"
        case .lastMonth: return "上月"
        case .lastThreeMonths: return "近 3 月"
        case .all: return "全部"
        }
    }
}

enum NativeExportFormat: String, CaseIterable, Identifiable, Hashable {
    case csv, json
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

struct NativeDataExportRequest {
    var content: NativeExportContent = .expense
    var range: NativeExportRange = .thisMonth
    var format: NativeExportFormat = .csv
    var includeFullPayload = false
}

struct NativeExportedFile: Identifiable {
    let url: URL
    var id: String { url.path }
}
