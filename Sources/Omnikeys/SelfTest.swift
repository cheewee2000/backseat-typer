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
        check("copied line dropped", Engine.clean(before: "- Confirm the SOW will read as a fixed fee\n- Send th", raw: "e SOW will read as a fixed fee", maxWords: 8) == "", Engine.clean(before: "- Confirm the SOW will read as a fixed fee\n- Send th", raw: "e SOW will read as a fixed fee", maxWords: 8).debugDescription)
        check("copied screen line dropped", Engine.clean(before: "Hi Taylor, ", raw: "Confirm the SOW will read as a fixed", maxWords: 8, existing: "todo: confirm the SOW will read as a fixed fee") == "")
        check("case-insensitive overlap", Engine.clean(before: "Please review the Projections", raw: "review the projections and finalize", maxWords: 8) == " and finalize", Engine.clean(before: "Please review the Projections", raw: "review the projections and finalize", maxWords: 8).debugDescription)
        check("short repeat allowed", Engine.clean(before: "I said yes and", raw: " yes", maxWords: 8) == " yes")
        check("copied phrase after a letter dropped", Engine.clean(before: "i get \"try the same sentence again\" if i type in, this", raw: "try the same sentence again if", maxWords: 8) == "")
        check("copy plus a new word dropped", Engine.clean(before: "like \"this is showing similar issues\" the autocomplete is \"s", raw: "this is showing similar issues with", maxWords: 8) == "")
        check("common opener kept", Engine.clean(before: "I think the plan is fine. I think", raw: " we should go ahead with it", maxWords: 8) == " we should go ahead with it")
        check("three-word copy dropped", Engine.clean(before: "like \"this is showing similar issues\" the autocomplete is \"", raw: "showing similar issues", maxWords: 8) == "")
        check("label echo dropped", Engine.clean(before: "I had a look at the sketches.", raw: "continuation", maxWords: 8) == "")
        check("single line", Engine.clean(before: "Hi", raw: " there\nmore", maxWords: 8) == " there")
        check("cap backs up to clause break", Engine.clean(before: "I had a look at the", raw: " drawings and they look great, I think we should", maxWords: 8) == " drawings and they look great,", Engine.clean(before: "I had a look at the", raw: " drawings and they look great, I think we should", maxWords: 8).debugDescription)
        check("cap keeps words when break is early", Engine.clean(before: "x", raw: " Yes, we can do that for you next week", maxWords: 8) == " Yes, we can do that for you next")
        // prefill token healing
        check("healed fragment", Engine.healed("I went to the sto") == ("I went to the", "sto"), "\(Engine.healed("I went to the sto"))")
        check("healed whole word kept", Engine.healed("I went to the") == ("I went to the", ""))
        check("healed retype", Engine.healed("the instal", retype: true) == ("the", "instal"))
        check("glued word continuation keeps no space", Engine.clean(before: "covers the instal", raw: "lation.", maxWords: 8) == "lation.", Engine.clean(before: "covers the instal", raw: "lation.", maxWords: 8).debugDescription)
        check("healed trailing space dropped", Engine.healed("I went to the ") == ("I went to the", ""))
        check("healed newline kept", Engine.healed("- one\n") == ("- one\n", ""))
        // terminal: the typed line is above the agent's status bar
        let tui = "─────\n> show a ti        \n─────\n  ⏵⏵ auto mode on · ← 1 agent"
        check("terminal input line", Controller.agentInput(tui) == "─────\n> show a ti", Controller.agentInput(tui).debugDescription)
        check("terminal wrapped input", Controller.agentInput("> one two\n  three   \n\nstatus") == "> one two\n  three")
        check("NUL-padded terminal repeat", Engine.clean(before: "the autocomplete is \"showing similar issues\"", raw: "showing similar issues", maxWords: 8, existing: "x\0showing\0similar\0issues") == "")
        check("terminal no prompt", Controller.agentInput("ls -la\nfoo") == nil)
        // learned-field fuzzy matching
        var vd = VaultData()
        let k = vd.addCustomField(label: "Tell us about yourself", kind: .list, sensitive: false); vd.setValue("P1", k, "Maker.")
        check("fuzzy label match", Matcher.match("Describe yourself", pid: "P1", vault: vd) == "{P1.\(k)|lines}", Matcher.match("Describe yourself", pid: "P1", vault: vd))
        check("fuzzy no false match", Matcher.match("City", pid: "P1", vault: vd) == "{P1.city}", Matcher.match("City", pid: "P1", vault: vd))
        check("schema beats weak fuzzy", Matcher.match("Reason for your visit", pid: "P1", vault: vd) == "", Matcher.match("Reason for your visit", pid: "P1", vault: vd))
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
            var done = false
            var out = "", ms = 0, err = ""
            let modelID = ProcessInfo.processInfo.environment["OMNIKEYS_MODEL"] ?? Models.apple
            // OMNIKEYS_BENCH=1: the same contexts through whichever model, output and latency per line.
            let bench = ProcessInfo.processInfo.environment["OMNIKEYS_BENCH"] != nil
            let contexts = bench ? ["What are we doing with all this stuff", "Elizabeth Holmes is the", "I went to the store to buy some",
                                    "Hey, are you free for lunch on", "The bench has a rocker sole so it", "Can you send me the invoice for the",
                                    // echo-prone: agent prompt lines and text that quotes itself
                                    "─────────────\n❯ ok trying the same sentence", "─────────────\n❯ how are we doing",
                                    "when i type in something like \"this is showing similar issues\" the autocomplete is \"s",
                                    "ok trying the same sentence. when i do that, i get \"try the same sentence again\" if i type in, this",
                                    "- Confirm the SOW will read as a fixed fee\n- Send the drawings to Taylor\n- ",
                                    "The autocomplete keeps repeating what I already wrote. It should instead",
                                    "Dear Taylor,\n\nThanks for sending the drawings over. I had a look at the",
                                    // grammar-sensitive joins: sentence end, mid-word, trailing space, after a comma, a list
                                    "Thanks for the update. ", "I went to the sto", "Can you send me the ", "If the budget allows,", "The budget covers the ash and the instal",
                                    "Shopping list:\n- eggs\n- milk\n- ", "The meeting is on Thursday at 3pm, so please",
                                    "we should probably", "Hi Sam, hope you're well. I wanted to ask whether"] : ["Dear Taylor,\n\nThanks for sending the drawings over. I had a look at the"]
            var echoes = 0, empties = 0, total = 0
            Task {
                for (i, c) in contexts.enumerated() {
                    let t0 = Date()
                    do {
                        out = try await e.complete(CompletionRequest(before: c, after: "", clipboard: nil, appName: "Mail", appInstructions: "", examples: [], length: .medium, british: false, model: modelID), custom: "")
                    } catch { err = "\(error)" }
                    ms = Int(Date().timeIntervalSince(t0) * 1000)
                    if bench {
                        // An echo: three or more words of the suggestion already sit in the context.
                        let echo = Engine.isCopy([Engine.norm(out)], of: Engine.norm(c))
                        echoes += echo ? 1 : 0; empties += out.isEmpty ? 1 : 0; total += ms
                        print("BENCH \(ms)ms\(echo ? " ECHO" : "") \(c.suffix(60).debugDescription) -> \(out.debugDescription)")
                    }
                }
                if bench { print("BENCH SUMMARY \(contexts.count) contexts, \(echoes) echoes, \(empties) empty, mean \(total / contexts.count)ms") }
                done = true
            }
            // Pump the main run loop instead of blocking it: the MLX loader runs on the main actor.
            let mlx = ProcessInfo.processInfo.environment["OMNIKEYS_MODEL"] != nil
            let deadline = Date().addingTimeInterval(mlx ? 900 : 30)
            var lastState = ""
            while !done && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                if mlx, e.statusText != lastState { lastState = e.statusText; print("  model: \(lastState)") }
            }
            check("completion non-empty", !out.isEmpty, "\(ms)ms \(out.debugDescription) \(err)")
            check("completion starts with space", out.hasPrefix(" "), out.debugDescription)
            check("completion under 3s", ms < 3000 || ProcessInfo.processInfo.environment["OMNIKEYS_MODEL"] != nil, "\(ms)ms")
        }
        print(ok ? "SELFTEST PASS" : "SELFTEST FAIL")
        return ok
    }
}
