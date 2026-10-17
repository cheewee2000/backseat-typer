import AppKit
import Observation

enum Suggestion: Equatable {
    case completion(String)
    case typo(word: String, fix: String, trailing: String)
    case emoji(code: String, emoji: String)
    case fill(label: String, value: String, sensitive: Bool)
    var display: String {
        switch self {
        case .completion(let s): return s
        case .typo(_, let fix, _): return "→ \(fix)"
        case .emoji(let code, let e): return "\(e) :\(code):"
        case .fill(_, let v, let sensitive): return sensitive ? Template.mask(v) : v
        }
    }
}

@MainActor @Observable final class Controller {
    static let shared = Controller()
    let tap = KeyTap()
    let ghost = OverlayPanel(bordered: false)
    let settings = Settings.shared
    var tapRunning = false
    var accessibilityTrusted = false

    private(set) var ctx: FocusContext?
    private(set) var suggestion: Suggestion?
    private var gen = 0
    private var pending: DispatchWorkItem?
    private var task: Task<Void, Never>?
    // pauses
    var pausedGlobally = false
    var appPauseUntil: [String: Date] = [:]
    var fieldPauseUntil: Date?
    var offInApp: String?
    private var forcedElement: AXUIElement?
    // recording
    private var lastElement: AXUIElement?
    private var lastText = ""
    private var lastApp = ""
    private var lastField: (label: String, multiline: Bool)?   // the labelled form field last focused, for learning
    private var sessionAccepted = false
    /// Set by the Shortcuts pane: the next key press is captured instead of handled.
    var recorder: ((Shortcut) -> Void)?

    private let codeEditors: Set<String> = ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "com.microsoft.VSCodeInsiders"]
    private let terminals: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "com.cwandt.knifeterminal"]

    func start() {
        tap.onKey = { [weak self] e, c, f in self?.handleKey(e, c, f) ?? false }
        tap.onMouse = { [weak self] in self?.hideAll(); self?.schedule() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { AX.nudgeChromium(app) }
            Task { @MainActor in self?.offInApp = nil; self?.hideAll(); self?.schedule() }
        }
        NSWorkspace.shared.runningApplications.forEach(AX.nudgeChromium)
        pollTrust()
        Engine.shared.prewarm()
    }
    private func pollTrust() {
        accessibilityTrusted = AXIsProcessTrusted()
        if accessibilityTrusted && !tapRunning {
            tapRunning = tap.start()
            Log.w(tapRunning ? "tap started" : "tap FAILED")
        }
        if !tapRunning { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.pollTrust() } }
    }

    // MARK: keys
    private func handleKey(_ e: CGEvent, _ code: UInt16, _ flags: CGEventFlags) -> Bool {
        let p = settings.p
        if let rec = recorder {
            recorder = nil
            if code != 53 { rec(Shortcut(keyCode: code, modifiers: flags.rawValue & Shortcut.mask, label: Shortcut.describe(code: code, flags: flags.rawValue & Shortcut.mask, char: tap.char(of: e)))) }
            return true
        }
        if p.toggleGlobal?.matches(code, flags) == true { pausedGlobally.toggle(); hideAll(); Log.w("global \(pausedGlobally ? "OFF" : "ON")"); return true }
        if p.toggleApp?.matches(code, flags) == true, let b = ctx?.bundleID ?? frontBundle() {
            if let u = appPauseUntil[b], u > Date() { appPauseUntil[b] = nil } else { appPauseUntil[b] = Date().addingTimeInterval(300) }
            hideAll(); return true
        }
        if p.forceActivate?.matches(code, flags) == true {
            if let c = AX.focusedContext() { forcedElement = c.element; fieldPauseUntil = nil; hideAll(); refresh(force: true) }
            return true
        }
        if p.fillForm?.matches(code, flags) == true { fillForm(); return true }

        let plain = flags.rawValue & Shortcut.mask

        if let s = suggestion {
            let rule = ctx.map { settings.rule(for: $0.bundleID, name: $0.appName) }
            if p.nextWord?.matches(code, flags) == true {
                if p.tabEnabled && rule?.tabEnabled != false { acceptWord(); return true }
            }
            if code == 48, flags.contains(.maskAlternate), p.nextWord?.keyCode == 48 {   // ⌥Tab: a plain Tab for the app
                e.flags = flags.subtracting(.maskAlternate); hideAll(); return false
            }
            if p.acceptAll?.matches(code, flags) == true { acceptAll(); return true }
            if p.dismiss?.matches(code, flags) == true {
                hideAll()
                switch p.escBehavior {
                case .pauseBriefly: fieldPauseUntil = Date().addingTimeInterval(4); return true
                case .offUntilAppSwitch: offInApp = ctx?.bundleID; return true
                case .passThrough: return false
                }
            }
            if case .completion(let text) = s, plain == 0 || plain == CGEventFlags.maskShift.rawValue {
                let ch = tap.char(of: e)
                if ch.count == 1, text.hasPrefix(ch), text.count > ch.count, !ch.unicodeScalars.contains(where: { $0.value < 32 }) {
                    show(.completion(String(text.dropFirst(ch.count)))); schedule(); return false
                }
            }
            hideAll()
        }
        if code == 48 || code == 53 || code == 36 || code == 76 { schedule(); return false }
        schedule()
        return false
    }
    private func frontBundle() -> String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

    // MARK: scheduling
    func schedule(after ms: Int? = nil) {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.refresh() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms ?? settings.p.debounceMs), execute: w)
    }

    func refresh(force: Bool = false) {
        gen += 1
        task?.cancel()
        guard settings.p.enabled, !pausedGlobally, Engine.shared.available else { skip("off"); return }
        guard var c = AX.focusedContext() else { ctx = nil; skip("no AX context"); return }
        ctx = c
        trackRecording(c)
        guard !c.isSecure else { skip("secure field"); return }
        let rule = settings.rule(for: c.bundleID, name: c.appName)
        guard rule.enabled, offInApp != c.bundleID else { skip("app rule off / esc in \(c.appName)"); return }
        if let u = appPauseUntil[c.bundleID], u > Date() { skip("app paused"); return }
        let forced = force || (forcedElement.map { CFEqual($0, c.element) } ?? false)
        if let u = fieldPauseUntil, u > Date(), !forced { skip("field paused"); return }
        if codeEditors.contains(c.bundleID), !settings.p.completeInCodeEditors, !forced { skip("code editor"); return }
        if terminals.contains(c.bundleID), !settings.p.completeInTerminals, !forced, !looksLikeAgentPrompt(c.before) { return }
        if terminals.contains(c.bundleID), let input = Controller.agentInput(c.before) { c.before = input; c.after = "" }
        if c.subrole == "AXSearchField", !forced { skip("search field"); return }

        if !c.selected.isEmpty { skip("selection"); return }
        let p = settings.p
        if p.formFill, FormFill.isEmptyField(c), let m = FormFill.match(c.element, profile: p.fillProfile) {
            Log.w("SHOW fill \(c.appName) \(m.label.debugDescription) -> \(m.sensitive ? Template.mask(m.value) : m.value.debugDescription)")
            show(.fill(label: m.label, value: m.value, sensitive: m.sensitive)); return
        }
        let lastWord = String(c.before.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).last ?? "")
        if p.emojiSuggestions, lastWord.hasPrefix(":"), lastWord.count >= 3, c.before.last != " ",
           let m = Emoji.matches(String(lastWord.dropFirst())).first {
            show(.emoji(code: m.0, emoji: m.1)); return
        }
        if let last = c.before.last, " .,;:!?\n".contains(last) {
            let trailing = String(c.before.reversed().prefix(while: { " .,;:!?\n".contains($0) }).reversed())
            let word = String(c.before.dropLast(trailing.count).reversed().prefix(while: { $0.isLetter || $0 == "'" }).reversed())
            if let fix = Spell.fix(word) {
                show(.typo(word: word, fix: fix, trailing: trailing))
                return
            }
        }
        // Google Docs with screen-reader support off exposes only two zero-width characters: nothing to continue.
        guard c.before.count >= p.minContextChars || forced else { skip((c.before + c.after).allSatisfy({ $0 == "\u{200B}" }) && !c.before.isEmpty ? "Google Docs accessibility mode off (Tools › Accessibility, ⌘⌥Z)" : "short context"); return }
        let afterLine = c.after.prefix(while: { $0 != "\n" })
        if !afterLine.trimmingCharacters(in: .whitespaces).isEmpty, !p.midLine { skip("mid-line"); return }
        lastSkip = ""

        var req = CompletionRequest(
            before: c.before, after: c.after,
            clipboard: p.clipboardAwareness ? NSPasteboard.general.string(forType: .string) : nil,
            appName: c.appName, appInstructions: rule.instructions,
            examples: p.recording ? History.shared.examples(for: c.bundleID, strength: p.personalization) : [],
            length: p.completionLength, british: p.britishEnglish, model: p.model)
        let g = gen
        let custom = p.customInstructions
        let wantScreen = p.screenContext
        task = Task { [weak self] in
            let t0 = Date()
            do {
                if wantScreen {   // AX tree walk off the main actor; cached inside for 3 s
                    let sc = await Task.detached { ScreenContext.gather(focused: c) }.value
                    req.screen = sc.window + sc.others
                    if !req.screen.isEmpty { Log.w("screen ctx window=\(sc.window.count) others=\(sc.others.count) chars \(Int(Date().timeIntervalSince(t0) * 1000))ms: \(String(req.screen.prefix(400)).replacingOccurrences(of: "\n", with: " | "))") }
                }
                let text = try await Engine.shared.complete(req, custom: custom)
                guard let self, g == self.gen, !Task.isCancelled else { return }
                if text.isEmpty { return }
                Log.w("SHOW completion \(Int(Date().timeIntervalSince(t0) * 1000))ms \(req.model.split(separator: "/").last ?? "") \(c.appName) [\(c.font.fontName) \(Int(c.fontSize))]: \(text.debugDescription)")
                self.show(.completion(text))
            } catch {
                if g == self?.gen ?? -1 { Log.w("model error: \(error)") }
            }
        }
    }
    private var lastSkip = ""
    /// Why the last refresh produced no request, logged once per change of reason.
    private func skip(_ why: String) { if why != lastSkip { lastSkip = why; Log.w("skip: \(why) in \(ctx?.appName ?? "?")/\(ctx?.role ?? "?")") } }
    private func looksLikeAgentPrompt(_ before: String) -> Bool { Controller.agentInput(before) != nil }
    /// A terminal's AX caret sits at the end of the screen buffer, below an agent TUI's status bar, so `before` ends in
    /// chrome while the words being typed sit on the `>` prompt line above. Returns the text up to the end of that
    /// input (the prompt line plus wrapped lines starting with a letter or digit), or nil when there is none.
    /// ponytail: a trailing space the user really typed is lost with the padding; the joiner then adds one.
    nonisolated static func agentInput(_ before: String) -> String? {
        let lines = before.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let chrome = CharacterSet(charactersIn: " │┃|\t")
        guard let i = lines.lastIndex(where: { l in
            let t = l.trimmingCharacters(in: chrome); return t.hasPrefix(">") || t.hasPrefix("›") || t.hasPrefix("❯") }) else { return nil }
        var end = i
        while end + 1 < lines.count, let f = lines[end + 1].trimmingCharacters(in: chrome).first, f.isLetter || f.isNumber { end += 1 }
        return String(lines[...end].joined(separator: "\n").reversed().drop(while: { " │┃|\t".contains($0) }).reversed())
    }

    // MARK: recording
    private func trackRecording(_ c: FocusContext) {
        let same = lastElement.map { CFEqual($0, c.element) } ?? false
        if !same {
            if settings.p.learnForms, let f = lastField { FormLearn.remember(label: f.label, value: lastText, multiline: f.multiline, profile: settings.p.fillProfile) }
            flushRecording()
            lastElement = c.element; lastApp = c.bundleID; sessionAccepted = false
            lastField = FormFill.isField(c) ? (FormFill.label(of: c.element), c.role == "AXTextArea") : nil
        }
        lastText = c.before + c.after
    }
    func flushRecording() {
        let p = settings.p
        guard p.recording, !lastApp.isEmpty, !lastText.isEmpty else { lastText = ""; return }
        let rule = settings.p.apps.first(where: { $0.id == lastApp })
        if rule?.recording != false, !terminals.contains(lastApp), sessionAccepted || p.recordAll { History.shared.record(app: lastApp, text: lastText) }
        lastText = ""
    }

    // MARK: show / hide
    private func show(_ s: Suggestion) {
        suggestion = s
        guard let c = ctx, let r = c.caretRect else { Log.w("GHOST no caret rect for \(ctx?.role ?? "?") in \(ctx?.appName ?? "?")"); return }
        let rgb = c.textColor.usingColorSpace(.sRGB)
        Log.w("GHOST at \(Int(r.minX)),\(Int(r.minY)) h=\(Int(r.height)) via \(Log.lastCaretHow) colour=\(rgb.map { String(format: "%.2f,%.2f,%.2f", $0.redComponent, $0.greenComponent, $0.blueComponent) } ?? "?") in \(c.appName)/\(c.role)")
        // context font, faded: the suggestion looks like what you're typing, just not yet committed
        ghost.show(s.display, font: c.font, color: c.textColor.withAlphaComponent(0.55), origin: CGPoint(x: r.minX, y: r.minY), lineHeight: r.height, rtl: settings.p.rtl)
    }
    func hideAll() { suggestion = nil; ghost.hide(); gen += 1; task?.cancel() }
    // MARK: accept
    private func countWords(_ s: String) -> Int { s.split(whereSeparator: { $0 == " " }).count }
    private func typed(_ s: String) {
        Log.w("TYPE \(s.debugDescription)")
        tap.type(s)
        settings.rollDay()
        settings.p.wordsToday += countWords(s); settings.p.wordsTotal += countWords(s)
        sessionAccepted = true
    }
    func acceptWord() {
        guard let s = suggestion else { return }
        switch s {
        case .typo(let word, let fix, let trailing):
            guard settings.p.fullAutocorrect else { hideAll(); return }   // indicator only
            hideAll(); tap.backspace((word as NSString).length + (trailing as NSString).length); typed(fix + trailing); schedule()
        case .emoji(let code, let e):
            hideAll(); tap.backspace((code as NSString).length + 1); typed(e); schedule()
        case .fill(let label, let value, _):
            hideAll()
            if let el = ctx?.element, FormFill.set(el, value) { Log.w("FILL \(label.debugDescription) via AX") ; sessionAccepted = true } else { typed(value) }
            schedule()
        case .completion(let text):
            let lead = text.prefix(while: { $0 == " " })
            let rest = text.dropFirst(lead.count)
            let word = rest.prefix(while: { $0 != " " })
            var out = String(lead) + String(word)
            let remaining = String(rest.dropFirst(word.count))
            if remaining.trimmingCharacters(in: .whitespaces).isEmpty {
                if settings.p.trailingSpaceAfterWord { out += " " }
                hideAll(); typed(out); schedule()
            } else {
                typed(out)
                suggestion = .completion(remaining)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in self?.reposition() }
            }
        }
    }
    func acceptAll() {
        Log.w("acceptAll suggestion=\(String(describing: suggestion))")
        guard case .completion(let text)? = suggestion else { acceptWord(); return }
        hideAll(); typed(text); schedule()
    }
    private func reposition() {
        guard case .completion(let text)? = suggestion, let c = AX.focusedContext() else { return }
        ctx = c
        show(.completion(text))
    }
    // MARK: form fill
    func fillForm() {
        guard let w = FormFill.frontWindow() else { Log.w("FILL form: no front window"); return }
        ctx = AX.focusedContext(); hideAll()
        let (n, skipped) = FormFill.fillWindow(w, profile: settings.p.fillProfile, includeSensitive: settings.p.fillSensitive)
        Log.w("FILL form: \(n) filled, \(skipped) sensitive skipped")
        flash(n == 0 ? (Vault.shared.isEmpty ? "vault is empty" : "no fields matched") : "filled \(n)\(skipped > 0 ? ", \(skipped) sensitive skipped" : "")")
    }
    /// A short note at the caret that goes away on its own.
    private func flash(_ text: String) {
        guard let c = ctx, let r = c.caretRect else { return }
        gen += 1
        ghost.show(text, font: c.font, color: c.textColor.withAlphaComponent(0.6), origin: CGPoint(x: r.minX, y: r.minY), lineHeight: r.height, rtl: settings.p.rtl)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in if self?.suggestion == nil { self?.ghost.hide() } }
    }
}
