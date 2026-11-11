import Foundation

enum DisplayMode: String, CaseIterable, Identifiable {
  case codex
  case claudeCode
  case qoder
  case grok
  case gemini
  case customImage

  var id: String { rawValue }

  var title: String {
    switch self {
    case .codex: return "Codex 用量"
    case .claudeCode: return "Claude Code"
    case .qoder: return "Qoder"
    case .grok: return "Grok"
    case .gemini: return "Gemini"
    case .customImage: return "自定义图片"
    }
  }

  var symbol: String {
    switch self {
    case .codex: return "terminal.fill"
    case .claudeCode: return "sun.max.fill"
    case .qoder: return "wand.and.stars"
    case .grok: return "sparkles"
    case .gemini: return "sparkle"
    case .customImage: return "photo"
    }
  }

  var logoAssetName: String? {
    switch self {
    case .codex: return "LogoCodex"
    case .claudeCode: return "LogoClaude"
    case .qoder: return "LogoQoder"
    case .grok: return "LogoGrok"
    case .gemini: return "LogoGemini"
    case .customImage: return nil
    }
  }

  var isUsageMode: Bool {
    switch self {
    case .customImage: return false
    case .codex, .claudeCode, .qoder, .grok, .gemini: return true
    }
  }
}
