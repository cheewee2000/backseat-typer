import AppKit

/// `Omnikeys --selftest`: the one runnable check. Fails loudly if the engine, cleaner, spell fixer or emoji table break.
enum SelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ cond: Bool, _ detail: String = "") {
            print((cond ? "PASS " : "FAIL ") + name + (detail.isEmpty ? "" : "  [\(detail)]")); if !cond { ok = false }
        }
        // cleaner
        check("overlap strip", Engine.clean(before: "I went to the", raw: "to the store today", maxWords: 8) == " store today", Engine.clean(before: "I went to the", raw: "to the store today", maxWords: 8).debugDescription)
        check("space joins words", Engine.clean(before: "I went to the", raw: "store", maxWords: 8) == " store")
        check("mid-word continues", Engine.clean(before: "I went to the sto", raw: "re", maxWords: 8) == "re")
        check("no double space", Engine.clean(before: "I went to the ", raw: " store", maxWords: 8) == "store")
        check("word cap", Engine.clean(before: "a b", raw: " one two three four five", maxWords: 3) == " one two three", Engine.clean(before: "a b", raw: " one two three four five", maxWords: 3).debugDescription)
        check("single line", Engine.clean(before: "Hi", raw: " there\nmore", maxWords: 8) == " there")
        // emoji
        check("emoji prefix", Emoji.matches("smi").first?.1 == "😄")
        check("emoji +1", Emoji.matches("+1").first?.1 == "👍")
        // spelling
        check("typo fix teh", Spell.fix("teh") == "the", Spell.fix("teh") ?? "nil")
        check("no fix for real word", Spell.fix("hello") == nil)
        check("no fix for names", Spell.fix("Taylor") == nil)
        // shortcuts
        let tab = Shortcut(keyCode: 48, modifiers: 0, label: "TAB")
        check("shortcut match", tab.matches(48, []) && !tab.matches(48, .maskCommand) && tab.matches(48, .maskNonCoalesced))
        // model
        let e = Engine.shared
        check("model available", e.available, e.statusText)
        if e.available {
            let sem = DispatchSemaphore(value: 0)
            var out = "", ms = 0, err = ""
            Task {
                let t0 = Date()
                do {
                    out = try await e.complete(CompletionRequest(before: "Dear Taylor,\n\nThanks for sending the drawings over. I had a look at the", after: "", clipboard: nil, appName: "Mail", appInstructions: "", examples: [], length: .medium, british: false), custom: "")
                } catch { err = "\(error)" }
                ms = Int(Date().timeIntervalSince(t0) * 1000)
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 30)
            check("completion non-empty", !out.isEmpty, "\(ms)ms \(out.debugDescription) \(err)")
            check("completion starts with space", out.hasPrefix(" "), out.debugDescription)
            check("completion under 3s", ms < 3000, "\(ms)ms")
        }
        print(ok ? "SELFTEST PASS" : "SELFTEST FAIL")
        return ok
    }
}
