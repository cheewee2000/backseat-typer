import AppKit
import Observation
import ServiceManagement

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64   // CGEventFlags masked to ⌃⌥⇧⌘
    var label: String
    static let mask: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue
    func matches(_ code: UInt16, _ flags: CGEventFlags) -> Bool {
        keyCode == code && (flags.rawValue & Shortcut.mask) == modifiers
    }
    static func describe(code: UInt16, flags: UInt64, char: String) -> String {
        var s = ""
        if flags & CGEventFlags.maskControl.rawValue != 0 { s += "⌃" }
        if flags & CGEventFlags.maskAlternate.rawValue != 0 { s += "⌥" }
        if flags & CGEventFlags.maskShift.rawValue != 0 { s += "⇧" }
        if flags & CGEventFlags.maskCommand.rawValue != 0 { s += "⌘" }
        let names: [UInt16: String] = [48: "TAB", 50: "`", 53: "ESC", 36: "RETURN", 49: "SPACE", 51: "DELETE",
                                       123: "←", 124: "→", 125: "↓", 126: "↑", 76: "ENTER", 117: "FWD DEL"]
        let c = char.trimmingCharacters(in: .whitespacesAndNewlines)
        return s + (names[code] ?? (c.isEmpty ? "KEY \(code)" : c.uppercased()))
    }
}

enum EscBehavior: String, Codable, CaseIterable { case pauseBriefly, offUntilAppSwitch, passThrough }
enum CompletionLength: String, Codable, CaseIterable { case short, medium, long }
enum AltTrigger: String, Codable, CaseIterable { case pause, shortcut }
enum SynTrigger: String, Codable, CaseIterable { case afterSelection, shortcut, off }

struct AppRule: Codable, Identifiable, Equatable {
    var id: String          // bundle id or domain
    var name: String
    var enabled = true
    var recording = true
    var tabEnabled = true
    var improveCompatibility = false
    var instructions = ""
}

struct Prefs: Codable {
    var enabled = true
    var completionLength = CompletionLength.medium
    var debounceMs = 220
    var minContextChars = 12
    var trailingSpaceAfterWord = false
    var tabEnabled = true
    var escBehavior = EscBehavior.pauseBriefly
    var midLine = true
    var screenContext = true     // read the rest of the window and the windows beside it
    var clipboardAwareness = false   // off: measured to derail the 3B model
    var fullAutocorrect = true
    var emojiSuggestions = true
    var completeInCodeEditors = false
    var completeInTerminals = false
    var model = Models.apple
    // form fill (vault ported from Form Filler)
    var formFill = true
    var fillSensitive = false
    var learnForms = true
    var fillProfile = "P1"
    var fillForm: Shortcut? = Shortcut(keyCode: 3, modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue, label: "⌃⌥F")
    // shortcuts
    var nextWord: Shortcut? = Shortcut(keyCode: 48, modifiers: 0, label: "TAB")
    var acceptAll: Shortcut? = Shortcut(keyCode: 50, modifiers: 0, label: "`")
    var dismiss: Shortcut? = Shortcut(keyCode: 53, modifiers: 0, label: "ESC")
    var forceActivate: Shortcut? = Shortcut(keyCode: 50, modifiers: CGEventFlags.maskControl.rawValue, label: "⌃`")
    var toggleApp: Shortcut? = Shortcut(keyCode: 50, modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue, label: "⌃⌥⌘`")
    var toggleGlobal: Shortcut? = nil
    var revealAlternatives: Shortcut? = nil
    var showSynonyms: Shortcut? = nil
    // personalization
    var recording = false
    var recordAll = false
    var personalization = 3     // 0 OFF … 5 MAX
    var customInstructions = Prefs.defaultInstructions()
    var apps: [AppRule] = []
    // labs
    var wordAlternatives = false
    var altTrigger = AltTrigger.pause
    var synonyms = true
    var synTrigger = SynTrigger.afterSelection
    var synDelayMs = 600
    var britishEnglish = false
    var rtl = false
    // stats
    var wordsToday = 0
    var dayKey = ""
    var wordsTotal = 0
    var firstRunDone = false

    static func defaultInstructions() -> String {
        let loc = Locale.current
        let lang = loc.localizedString(forLanguageCode: loc.language.languageCode?.identifier ?? "en") ?? "English"
        let region = loc.region.flatMap { loc.localizedString(forRegionCode: $0.identifier) } ?? ""
        return "I write mostly in \(lang)\(region.isEmpty ? "" : " and live in \(region)"). Match my tone and vocabulary. Keep suggestions natural and concise."
    }
}

@Observable final class Settings {
    static let shared = Settings()
    private static let key = "prefs"
    var p: Prefs { didSet { save() } }

    init() {
        self.p = UserDefaults.standard.data(forKey: Settings.key).map(Settings.decode) ?? Prefs()
        rollDay()
    }
    /// Saved keys over defaults, so a key added in a newer version never throws the whole file away.
    static func decode(_ d: Data) -> Prefs {
        if let p = try? JSONDecoder().decode(Prefs.self, from: d) { return p }
        guard let def = try? JSONEncoder().encode(Prefs()), var base = (try? JSONSerialization.jsonObject(with: def)) as? [String: Any],
              let saved = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return Prefs() }
        for (k, v) in saved { base[k] = v }
        return (try? JSONSerialization.data(withJSONObject: base)).flatMap { try? JSONDecoder().decode(Prefs.self, from: $0) } ?? Prefs()
    }
    private func save() {
        if let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: Settings.key) }
    }
    func rollDay() {
        let k = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        if p.dayKey != k { p.dayKey = k; p.wordsToday = 0 }
    }
    func rule(for bundleID: String, name: String) -> AppRule {
        if let r = p.apps.first(where: { $0.id == bundleID }) { return r }
        let r = AppRule(id: bundleID, name: name)
        p.apps.append(r)
        return r
    }
    func update(_ r: AppRule) {
        if let i = p.apps.firstIndex(where: { $0.id == r.id }) { p.apps[i] = r } else { p.apps.append(r) }
    }
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { try? (newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()) }
    }
    var spellLanguage: String { p.britishEnglish ? "en_GB" : "en" }
    var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
}

enum Log {
    static var lastCaretHow = ""   // which geometry produced the caret rect, for the GHOST log line
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Omnikeys.log")
    static func w(_ s: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        print(line, terminator: "")
        if let d = line.data(using: .utf8) {
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(d); try? h.close() }
            else { try? d.write(to: url) }
        }
    }
}
