import Foundation

struct Language {
    let name: String
    let code: String
}

// Based on https://docs.aws.amazon.com/transcribe/latest/dg/supported-languages.html
// for streaming audio
let supportedLanguages: [Language] = [
    Language(name: "English", code: "en-US"),
    Language(name: "中文（简体）", code: "zh-CN"),
    Language(name: "Español", code: "es-ES"),
    Language(name: "Français", code: "fr-FR"),
    Language(name: "Deutsch", code: "de-DE"),
    Language(name: "日本語", code: "ja-JP"),
    Language(name: "한국어", code: "ko-KR"),
    Language(name: "Português", code: "pt-PT"),
    Language(name: "Русский", code: "ru-RU"),
    Language(name: "ไทย", code: "th-TH"),
    Language(name: "Tiếng Việt", code: "vi-VN"),
    Language(name: "Dansk", code: "da-DK"),
    Language(name: "Suomi", code: "fi-FI"),
    Language(name: "Norsk", code: "no-NO"),
    Language(name: "Nederlands", code: "nl-NL"),
    Language(name: "Italiano", code: "it-IT"),
    Language(name: "Svenska", code: "sv-SE"),
] 