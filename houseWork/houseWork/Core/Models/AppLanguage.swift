//
//  AppLanguage.swift
//  houseWork
//
//  Controls explicit locale selection for the app.
//

import Foundation
import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    
    var id: String { rawValue }
    
    var displayKey: LocalizedStringKey {
        switch self {
        case .system:
            return LocalizedStringKey("settings.language.option.system")
        case .english:
            return LocalizedStringKey("settings.language.option.en")
        case .simplifiedChinese:
            return LocalizedStringKey("settings.language.option.zhHans")
        }
    }
    
    var locale: Locale? {
        switch self {
        case .system:
            return nil
        case .english:
            return Locale(identifier: "en")
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        }
    }
}

@MainActor
final class LanguageStore: ObservableObject {
    @Published private(set) var selectedLanguage: AppLanguage
    
    private let defaults: UserDefaults
    private let key = "app.language.selection"
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: key), let language = AppLanguage(rawValue: raw) {
            selectedLanguage = language
        } else {
            selectedLanguage = .system
        }
    }
    
    var locale: Locale {
        if let override = selectedLanguage.locale {
            return override
        }
        if let preferred = Locale.preferredLanguages.first {
            return Locale(identifier: preferred)
        }
        return Locale(identifier: "en")
    }
    
    func select(_ language: AppLanguage) {
        guard selectedLanguage != language else { return }
        selectedLanguage = language
        if language == .system {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(language.rawValue, forKey: key)
        }
    }
}
