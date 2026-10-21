import AppKit
import FoundationModels
import Observation
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Model choices. "apple-on-device" is the Apple Intelligence model; the rest are the open-weight
/// models Cotypist ships (Gemma 4 default, Qwen), fetched from Hugging Face on first use and run by MLX.
enum Models {
    static let apple = "apple-on-device"
    static let options: [(String, String)] = [
        (apple, "Apple"),
        ("mlx-community/gemma-4-e2b-it-4bit", "Gemma 4 E2B"),
        ("mlx-community/gemma-4-e4b-it-4bit", "Gemma 4 E4B"),
        ("mlx-community/Qwen2.5-1.5B-Instruct-4bit", "Qwen2.5 1.5B"),
        ("mlx-community/Qwen3-1.7B-4bit", "Qwen3 1.7B"),
    ]
}

@Generable struct Continuation {
    @Guide(description: "The next few words that continue the text exactly from the cursor. Start with a space if a new word begins there. No quotes, no explanation.")
    var text: String
}
struct CompletionRequest {
    var before: String
    var after: String
    var clipboard: String?
    var appName: String
    var appInstructions: String
    var examples: [String]
    var length: CompletionLength
    var british: Bool
    var model = Models.apple
    var screen = ""   // other text on screen, see ScreenContext
}

@Observable final class Engine {
    static let shared = Engine()
    let model = SystemLanguageModel.default
    var available: Bool { Settings.shared.p.model != Models.apple || { if case .available = model.availability { return true }; return false }() }
    var statusText: String {
        let id = Settings.shared.p.model
        if id != Models.apple { return mlxState[id] ?? "DOWNLOADS ON FIRST USE" }
        switch model.availability {
        case .available: return "READY"
        case .unavailable(let r):
            switch r {
            case .deviceNotEligible: return "DEVICE NOT ELIGIBLE"
            case .appleIntelligenceNotEnabled: return "ENABLE APPLE INTELLIGENCE IN SYSTEM SETTINGS"
            case .modelNotReady: return "MODEL DOWNLOADING"
            @unknown default: return "UNAVAILABLE"
            }
        }
    }

    func prewarm() {
        LanguageModelSession(model: model, instructions: Engine.baseInstructions).prewarm()
    }

    static let baseInstructions = """
    You are an inline autocomplete engine, like predictive text on a keyboard. The user is typing. You output only the words that come next, continuing their text seamlessly in the same language, register and style. Never explain, never comment, never wrap the output in quotes. If the text ends mid-word, finish that word first. Never repeat text that is already written: not the words just before the cursor, and not a sentence or list item that appears earlier in the text or elsewhere on screen. Say something new.
    """

    func instructions(_ r: CompletionRequest, custom: String) -> String {
        var s = Engine.baseInstructions
        // The MLX path continues the text itself, so a word count only makes it pad ("…immediately now"); the caps trim.
        if r.model == Models.apple {
            switch r.length {
            case .short: s += "\nSuggest at most 3 words."
            case .medium: s += "\nSuggest about 4 to 7 words, ending at a natural break."
            case .long: s += "\nSuggest up to one full sentence."
            }
        }
        if r.british { s += "\nUse British English spelling." }
        if !custom.isEmpty { s += "\n\nAbout the writer: \(custom)" }
        if !r.appInstructions.isEmpty { s += "\n\nWhen writing in \(r.appName): \(r.appInstructions)" }
        // A sample taken from this very document makes the model echo it instead of continuing.
        let doc = Engine.norm(r.before)
        let ex = r.examples.filter { let h = Engine.norm(String($0.prefix(80))); return h.count < 20 || !doc.contains(h) }
        if !ex.isEmpty {
            s += "\n\nSamples of how this writer writes. Favor their vocabulary and phrasing:\n" + ex.map { "- \($0)" }.joined(separator: "\n")
        }
        return s
    }

    /// A suggestion that `clean` threw away as a copy of the screen leaves nothing to show; in Google Docs after a
    /// full stop the model kept lifting a line from a neighbouring window. Once, retry with the screen text out of the
    /// prompt so the model has to continue the writer's own text instead.
    func complete(_ r: CompletionRequest, custom: String) async throws -> String {
        let out = try await completeOnce(r, custom: custom)
        guard out.isEmpty else { return out }
        var bare = r; bare.screen = ""; bare.clipboard = nil
        let again = try await completeOnce(bare, custom: custom, strict: true)
        if !again.isEmpty { Log.w("RETRY without screen text -> \(again.debugDescription)") }
        return again
    }
    /// `strict`: the first token must carry a letter or digit ("See you on" → "..." then a thinking channel is a stop in disguise).
    func completeOnce(_ r: CompletionRequest, custom: String, strict: Bool = false) async throws -> String {
        // The small models lose the thread when anything follows the typed text, so the prompt is the text alone
        // and everything else (writer notes, samples, clipboard) lives in the instructions. Plain string output:
        // the JSON wrapper of @Generable ate most of a 20-token budget and left one-word suggestions.
        var ins = instructions(r, custom: custom)
        if let c = r.clipboard, !c.isEmpty { ins += "\n\nThe writer's clipboard, which may be relevant:\n\(c.prefix(300))" }
        if !r.screen.isEmpty {
            ins += "\n\nOther text visible on screen right now (the rest of this window, then windows beside it). Use the names, numbers and facts in it when the sentence calls for them, but do not copy sentences from it:\n\(r.screen.prefix(3200))"
        }
        let tokens: Int
        switch r.length { case .short: tokens = 12; case .medium: tokens = 24; case .long: tokens = 48 }
        var out: String
        var glued = false
        if r.model == Models.apple {
            ins += "\n\nExample:\nText: I went to the\nContinuation: store to pick up milk"
            let session = LanguageModelSession(model: model, instructions: ins)
            out = try await session.respond(to: "Text: \(r.before.suffix(1500))\nContinuation:", options: GenerationOptions(sampling: .greedy, temperature: 0, maximumResponseTokens: tokens)).content
        } else {
            // Prefill: the model's own turn starts with the writer's text, so the next tokens are plain language-model
            // continuation of it rather than an answer about it. The screen dump used to win that contest and the same
            // suggestion came back whatever was typed.
            ins += "\n\nYour reply starts with the writer's text so far, exactly as they wrote it. Keep writing from where it stops."
            let window = String(r.before.suffix(2000))
            var (prefill, partial) = Engine.healed(window)
            let container = try await mlx(r.model)
            // `partial` is the fragment the model must type again; with a space in front when one was dropped before it.
            func gen(_ prefill: String, _ partial: String) async throws -> String {
                let target = partial.isEmpty ? "" : (window.dropLast(partial.count).last == " " ? " " : "") + partial
                return try await container.perform { (ctx: ModelContext) -> String in
                    var ids = try ctx.tokenizer.applyChatTemplate(messages: [["role": "user", "content": ins]], tools: nil, additionalContext: ["enable_thinking": false])
                    ids += ctx.tokenizer.encode(text: prefill, addSpecialTokens: false)
                    let input = LMInput(tokens: MLXArray(ids))
                    // An instruct model likes to end its turn after a finished sentence; a suggestion is wanted anyway.
                    let stops = Array(ctx.configuration.eosTokenIds) + ([ctx.tokenizer.eosTokenId, ctx.tokenizer.unknownTokenId] + ctx.configuration.extraEOSTokens.map { ctx.tokenizer.convertTokenToId($0) }).compactMap { $0 }
                    let steer = Steer(stop: stops, left: 3, target: target, vocab: Engine.vocab(r.model, ctx.tokenizer), tokenizer: ctx.tokenizer, strict: strict)
                    let it = try TokenIterator(input: input, model: ctx.model, processor: steer, sampler: ArgMaxSampler(), maxTokens: tokens)
                    return MLXLMCommon.generate(input: input, context: ctx, iterator: it) { (_: [Int]) in .more }.output
                }
            }
            out = try await gen(prefill, partial)
            // Letters glued straight onto a finished word mean the model was continuing it across a bad token split
            // ("instal" + "ation"). Let it type the whole word from the boundary instead.
            if partial.isEmpty, window.last?.isLetter == true, out.first?.isLetter == true {
                (prefill, partial) = Engine.healed(window, retype: true)
                out = try await gen(prefill, partial)
            }
            Log.w("RAW \(String(r.before.suffix(160)).debugDescription) -> \(out.debugDescription)\(partial.isEmpty ? "" : " (healing \(partial))")")
            // Token healing: the model re-typed the fragment from the word boundary; it must agree with what was typed.
            if !partial.isEmpty {
                let t = out.drop(while: { $0 == " " })
                out = t.lowercased().hasPrefix(partial.lowercased()) ? String(t.dropFirst(partial.count)) : ""
                glued = out.first?.isLetter == true
            }
        }
        if r.model == Models.apple { Log.w("RAW \(String(r.before.suffix(160)).debugDescription) -> \(out.debugDescription)") }
        let existing = ([r.after, r.clipboard ?? ""] + r.examples + [r.screen]).joined(separator: "\n")
        return Engine.clean(before: r.before, raw: out, maxWords: r.length == .short ? 3 : (r.length == .medium ? 8 : 20), existing: existing, glued: glued)
    }

    // MARK: MLX models
    nonisolated(unsafe) private static var vocabs: [String: [(String, Int32)]] = [:]
    /// Token texts sorted for prefix lookup, built once per model (~0.3 s for Gemma's 262k tokens).
    static func vocab(_ model: String, _ t: MLXLMCommon.Tokenizer) -> [(String, Int32)] {
        if let v = vocabs[model] { return v }
        var v: [(String, Int32)] = []
        var id = 0
        while let tok = t.convertIdToToken(id) { if !tok.hasPrefix("<") { v.append((tok.replacingOccurrences(of: "▁", with: " "), Int32(id))) }; id += 1 }
        v.sort { $0.0 < $1.0 }
        vocabs[model] = v
        return v
    }
    private(set) var mlxState: [String: String] = [:]
    private var mlxLoads: [String: Task<ModelContainer, Error>] = [:]
    /// One model resident at a time; the others are dropped when a new one loads.
    @MainActor private func mlx(_ id: String) async throws -> ModelContainer {
        if let t = mlxLoads[id] { return try await t.value }
        mlxLoads = [:]
        mlxState[id] = "LOADING"
        let t = Task { [weak self] in
            try await LLMModelFactory.shared.loadContainer(from: #hubDownloader(), using: #huggingFaceTokenizerLoader(),
                                                           configuration: ModelConfiguration(id: id)) { p in
                Task { @MainActor in self?.mlxState[id] = "DOWNLOADING \(Int(p.fractionCompleted * 100))%" }
            }
        }
        mlxLoads[id] = t
        do { let c = try await t.value; mlxState[id] = "READY"; return c }
        catch { mlxState[id] = "FAILED: \(error.localizedDescription)"; mlxLoads[id] = nil; throw error }
    }

    /// Token healing for the prefill. A trailing fragment that is not a word ("sto") would tokenize unlike the word it
    /// starts, so it is left off the prefill and the model types it again; trailing spaces likewise, since a word
    /// token carries its own leading space. `retype` leaves the last word off even when it is a word: used when the
    /// model glued letters onto it ("instal" + "ation"), which means it was continuing the word from a bad token split.
    /// Returns the text to prefill and the fragment the output must start with.
    static func healed(_ before: String, retype: Bool = false) -> (prefill: String, partial: String) {
        var p = before
        var partial = ""
        if let l = p.last, l.isLetter || l.isNumber {
            let w = String(p.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).last ?? "")
            if retype || !Spell.isWord(w) { partial = w; p = String(p.dropLast(w.count)) }
        }
        p = String(p.reversed().drop(while: { $0 == " " }).reversed())
        return (p, partial)
    }
    /// Normalizes raw model output into a ghost-text continuation.
    static func norm(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: #"[\s\p{P}\p{C}]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
    /// A suggestion whose opening words (the first four, or all of a three-word one) already sit in `pool` is a copy,
    /// even when the model tacks a new word on the end. Inputs are `norm`ed.
    static func isCopy(_ candidates: [String], of pool: String) -> Bool {
        candidates.contains { c in
            let w = c.split(separator: " "); guard w.count >= 3 else { return false }
            return pool.contains(w.prefix(4).joined(separator: " "))
        }
    }
    /// Screen text arrives as segments split by " | " and newlines; a suggestion equal to a whole segment is a copy of it.
    static func isChrome(_ c: String, of existing: String) -> Bool {
        guard c.split(separator: " ").count >= 2 else { return false }
        return existing.split(whereSeparator: { $0 == "|" || $0 == "\n" }).contains { norm(String($0)) == c }
    }
    /// `existing` is other text the model could have copied (after the cursor, on screen).
    /// `glued`: the output is known to continue the last word (healed fragment), so no space is inserted.
    static func clean(before: String, raw: String, maxWords: Int, existing: String = "", glued: Bool = false) -> String {
        var s = raw.replacingOccurrences(of: "\r", with: "")
        if let nl = s.firstIndex(of: "\n") { s = String(s[..<nl]) }   // single line
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”`"))
        // The prompt's own label leaks back when the model has nothing to add.
        if s.lowercased().hasPrefix("continuation") { s = String(s.dropFirst("continuation".count)).trimmingCharacters(in: CharacterSet(charactersIn: ": ")) }
        // Strip anything the model repeated from the end of the context.
        let tail = String(before.suffix(60))
        for k in stride(from: min(tail.count, s.count), through: 2, by: -1) {
            if s.hasPrefix(tail.suffix(k)) { s = String(s.dropFirst(k)); break }
        }
        // Same again at word level, case- and punctuation-insensitive: "…review the Projections" + "review the projections and" → " and".
        let tailWords = norm(String(before.suffix(300))).split(separator: " ").map(String.init)
        var outWords = s.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if !outWords.isEmpty {
            for n in stride(from: min(tailWords.count, outWords.count, 20), through: 1, by: -1) {
                let a = tailWords.suffix(n), b = outWords.prefix(n).map { norm($0) }
                if Array(a) == b { s = " " + outWords.dropFirst(n).joined(separator: " "); outWords = Array(outWords.dropFirst(n)); break }
            }
        }
        if s.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        // Punctuation alone ("...", "—") adds nothing to what is being typed.
        if !s.contains(where: { $0.isLetter || $0.isNumber }) { return "" }
        // A copy of a line that already exists (earlier in the text, after the cursor, or on screen) is not a continuation.
        // The output may finish the last word or start a new one; a copy under either reading is dropped.
        let lastPartial = before.last.map { $0.isLetter || $0.isNumber } == true ? String(before.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).last ?? "") : ""
        let candidates = [norm(s)] + (s.first?.isLetter == true && !lastPartial.isEmpty ? [norm(lastPartial + s)] : [])
        if Engine.isCopy(candidates, of: norm(String(before.suffix(3000))) + " \n " + norm(String(existing.prefix(6000)))) { return "" }
        // A suggestion that is, whole, one piece of window chrome ("229 notes", a date, a tab title) is a copy however short.
        if Engine.isChrome(norm(s), of: existing) { return "" }
        // Joining: a new word after a complete word needs a space; mid-word it must not have one.
        let lastChar = before.last
        let firstChar = s.first!
        if let lc = lastChar, lc.isLetter || lc.isNumber, firstChar.isLetter {
            let lastWord = String(before.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).last ?? "")
            let firstWord = String(s.prefix(while: { $0.isLetter || $0 == "'" }))
            if !glued, Spell.isWord(lastWord), !Spell.isWord(lastWord + firstWord) { s = " " + s }
        } else if let lc = lastChar, lc.isWhitespace, firstChar == " " {   // web fields report a typed space as NBSP
            s = String(s.drop(while: { $0 == " " }))
        } else if lastChar == nil, firstChar == " " {
            s = String(s.drop(while: { $0 == " " }))
        }
        // Cap the word count at a boundary; collapses runs of spaces too. A cap that cuts mid-clause backs up to the
        // last clause break instead, when that keeps most of the words: "…look great, I think we" → "…look great,".
        let lead = s.prefix(while: { $0 == " " })
        let all = s.dropFirst(lead.count).split(separator: " ", omittingEmptySubsequences: true)
        var words = Array(all.prefix(maxWords))
        if all.count > maxWords, let i = words.lastIndex(where: { ",;:.!?".contains($0.last!) }), i + 1 >= maxWords / 2 { words = Array(words[...i]) }
        s = String(lead) + words.joined(separator: " ")
        return s
    }
}

/// Logit processor for the prefill path. Masks the end-of-turn tokens for the first `left` tokens, and while the
/// output is shorter than `target` (the word fragment being healed) allows only tokens that keep it a prefix of the
/// target or complete it: "measurem" then comes back as "measurements", not whichever word the model preferred.
struct Steer: LogitProcessor {
    let stop: MLXArray
    var left: Int
    let target: String
    let newline: MLXArray   // tokens that begin with a line break: not as the first token, the suggestion continues this line
    let wordless: MLXArray  // tokens with no letter or digit; masked as the first token on the strict retry
    init(stop: [Int], left: Int, target: String, vocab: [(String, Int32)], tokenizer: MLXLMCommon.Tokenizer, strict: Bool = false) {
        self.stop = MLXArray(stop.map { Int32($0) }); self.left = left; self.target = target; self.vocab = vocab; self.tokenizer = tokenizer
        self.newline = MLXArray(vocab.filter { $0.0.hasPrefix("\n") || $0.0.hasPrefix("\r") }.map(\.1))
        self.wordless = strict ? MLXArray(vocab.filter { !$0.0.contains(where: { $0.isLetter || $0.isNumber }) }.map(\.1)) : MLXArray([Int32]())
    }
    let vocab: [(String, Int32)]   // token text (space for ▁), sorted by text
    let tokenizer: MLXLMCommon.Tokenizer
    var ids: [Int] = []
    var done = ""
    mutating func prompt(_ prompt: MLXArray) {}
    func process(logits: MLXArray) -> MLXArray {
        if done.count < target.count {
            let rem = String(target.dropFirst(done.count))
            var allowed: [Int32] = []
            // tokens that are a prefix of the remainder
            for n in 1...rem.count { let p = String(rem.prefix(n)); var i = Steer.lower(vocab, p); while i < vocab.count, vocab[i].0 == p { allowed.append(vocab[i].1); i += 1 } }
            // tokens that start with the remainder
            var i = Steer.lower(vocab, rem); while i < vocab.count, vocab[i].0.hasPrefix(rem) { allowed.append(vocab[i].1); i += 1 }
            if !allowed.isEmpty {
                let idx = MLXArray(allowed)
                let m = MLXArray.full(logits.shape, values: MLXArray(-Float.infinity), type: Float.self)
                m[.ellipsis, idx] = logits[.ellipsis, idx]
                return m
            }
        }
        guard left > 0 else { return logits }
        let l = logits
        l[.ellipsis, stop] = MLXArray(-Float.infinity)
        // After a full stop the model likes to open a new paragraph, and the single-line rule then shows nothing.
        if ids.isEmpty, newline.size > 0 { l[.ellipsis, newline] = MLXArray(-Float.infinity) }
        if ids.isEmpty, wordless.size > 0 { l[.ellipsis, wordless] = MLXArray(-Float.infinity) }
        return l
    }
    mutating func didSample(token: MLXArray) {
        left -= 1
        ids.append(token.item(Int.self))
        if done.count < target.count { done = tokenizer.decode(tokenIds: ids) }
    }
    static func lower(_ v: [(String, Int32)], _ key: String) -> Int {
        var lo = 0, hi = v.count
        while lo < hi { let mid = (lo + hi) / 2; if v[mid].0 < key { lo = mid + 1 } else { hi = mid } }
        return lo
    }
}

enum Spell {
    static func isWord(_ w: String) -> Bool {
        guard w.count >= 2 else { return w.count == 1 && ["a", "i", "A", "I"].contains(w) }
        let r = NSSpellChecker.shared.checkSpelling(of: w, startingAt: 0, language: Settings.shared.spellLanguage, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return r.location == NSNotFound
    }
    /// A correction for a misspelled plain lowercase word, else nil.
    static func fix(_ w: String) -> String? {
        guard w.count >= 3, w.allSatisfy({ $0.isLetter || $0 == "'" }), w == w.lowercased() else { return nil }
        let sc = NSSpellChecker.shared
        let lang = Settings.shared.spellLanguage
        let r = sc.checkSpelling(of: w, startingAt: 0, language: lang, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        guard r.location != NSNotFound else { return nil }
        if let c = sc.correction(forWordRange: NSRange(location: 0, length: (w as NSString).length), in: w, language: lang, inSpellDocumentWithTag: 0), c != w { return c }
        return sc.guesses(forWordRange: NSRange(location: 0, length: (w as NSString).length), in: w, language: lang, inSpellDocumentWithTag: 0)?.first
    }
}
