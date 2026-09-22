import Foundation

enum TargetLanguage: String, CaseIterable {
    case english = "en"
    case simplifiedChinese = "zh-CN"
    case indonesian = "id"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .indonesian: return "Bahasa Indonesia"
        }
    }
}

@MainActor
enum Settings {
    private static let targetLanguageKey = "targetLanguage"
    private static let showPinyinKey = "showPinyin"

    static var targetLanguage: TargetLanguage {
        get {
            if let raw = UserDefaults.standard.string(forKey: targetLanguageKey),
               let lang = TargetLanguage(rawValue: raw) {
                return lang
            }
            return .english
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: targetLanguageKey) }
    }

    static var showPinyin: Bool {
        get {
            if UserDefaults.standard.object(forKey: showPinyinKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: showPinyinKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showPinyinKey) }
    }
}
