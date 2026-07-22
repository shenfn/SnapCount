import Foundation

enum ShortcutTemplateKind: String, CaseIterable, Identifiable {
    case photo
    case screenshot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return "拍照记录"
        case .screenshot: return "截图记录"
        }
    }

    var detail: String {
        switch self {
        case .photo: return "拍下小票、餐食或屏幕"
        case .screenshot: return "把刚截的图片直接交给芥子"
        }
    }

    var systemImage: String {
        switch self {
        case .photo: return "camera.fill"
        case .screenshot: return "rectangle.on.rectangle.angled"
        }
    }

    var url: String {
        switch self {
        case .photo: return AppConfig.photoShortcutTemplateURL
        case .screenshot: return AppConfig.screenshotShortcutTemplateURL
        }
    }
}
