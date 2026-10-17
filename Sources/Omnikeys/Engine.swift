import AppKit
import FoundationModels
import Observation
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
@Generable struct WordList {
    @Guide(description: "Single words or very short phrases, most likely first.", .count(3...5))
    var words: [String]
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
        switch r.length {
        case .short: s += "\nSuggest at most 3 words."
        case .medium: s += "\nSuggest about 4 to 7 words, ending at a natural break."
        case .long: s += "\nSuggest up to one full sentence."
        }
        if r.british { s += "\nUse British English spelling." }
        if !custom.isEmpty { s += "\n\nAbout the writer: \(custom)" }
        if !r.appInstructions.isEmpty { s += "\n\nWhen writing in \(r.appName): \(r.appInstructions)" }
        // A sample taken from this very document makes the model echo it instead of continuing.
        let head = String(r.before.prefix(40))
        let ex = r.examples.filter { head.count < 20 || !$0.contains(head) }
        if !ex.isEmpty {
            s += "\n\nSamples of how this writer writes. Favor their vocabulary and phrasing:\n" + ex.map { "- \($0)" }.joined(separator: "\n")
        }
        return s
    }

    func complete(_ r: CompletionRequest, custom: String) async throws -> String {
        // The small models lose the thread when anything follows the typed text, so the prompt is the text alone
        // and everything else (writer notes, samples, clipboard) lives in the instructions. Plain string output:
        // the JSON wrapper of @Generable ate most of a 20-token budget and left one-word suggestions.
        var ins = instructions(r, custom: custom)
        if let c = r.clipboard, !c.isEmpty { ins += "\n\nThe writer's clipboard, which may be relevant:\n\(c.prefix(300))" }
        let afterLine = r.after.prefix(while: { $0 != "\n" })
        if !afterLine.trimmingCharacters(in: .whitespaces).isEmpty { ins += "\n\nThe text after the cursor is: \(afterLine.prefix(200))\nYour words must fit before it." }
        if !r.screen.isEmpty {
            ins += "\n\nOther text visible on screen right now (the rest of this window, then windows beside it). Use the names, numbers and facts in it when the sentence calls for them, but do not copy sentences from it:\n\(r.screen.prefix(3200))"
        }
        ins += "\n\nExample:\nText: I went to the\nContinuation: store to pick up milk"
        let prompt = "Text: \(r.before.suffix(1500))\nContinuation:"
        let tokens: Int
        switch r.length { case .short: tokens = 12; case .medium: tokens = 24; case .long: tokens = 48 }
        let out: String
        if r.model == Models.apple {
            let session = LanguageModelSession(model: model, instructions: ins)
            out = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy, temperature: 0, maximumResponseTokens: tokens)).content
        } else {
            let session = ChatSession(try await mlx(r.model), instructions: ins,
                                      generateParameters: GenerateParameters(maxTokens: tokens, temperature: 0),
                                      additionalContext: ["enable_thinking": false])
            out = try await session.respond(to: prompt)
        }
        return Engine.clean(before: r.before, raw: out, maxWords: r.length == .short ? 3 : (r.length == .medium ? 8 : 20), existing: r.after + "\n" + r.screen)
    }

    // MARK: MLX models
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

    func alternatives(_ r: CompletionRequest, firstWord: String, custom: String) async throws -> [String] {
        let session = LanguageModelSession(model: model, instructions: instructions(r, custom: custom))
        let prompt = "Text before the cursor:\n\(r.before.suffix(800))\n\nThe suggested next word is \"\(firstWord)\". List other plausible next words instead of it."
        let out = try await session.respond(to: prompt, generating: WordList.self, options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 60)).content.words
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0.lowercased() != firstWord.lowercased() }
    }

    func synonyms(selection: String, before: String, after: String, british: Bool) async throws -> [String] {
        let session = LanguageModelSession(model: model, instructions: "You suggest synonyms that fit a sentence. Output only words.\(british ? " Use British English spelling." : "")")
        let prompt = "Sentence: \(before.suffix(300))[\(selection)]\(after.prefix(200))\n\nGive synonyms for the bracketed words that fit this sentence, matching its case and grammar."
        let out = try await session.respond(to: prompt, generating: WordList.self, options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 60)).content.words
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0.lowercased() != selection.lowercased() }
    }

    /// Normalizes raw model output into a ghost-text continuation.
    static func norm(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: #"[\s\p{P}]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
    /// `existing` is other text the model could have copied (after the cursor, on screen).
    static func clean(before: String, raw: String, maxWords: Int, existing: String = "") -> String {
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
        // A copy of a line that already exists (earlier in the text, after the cursor, or on screen) is not a continuation.
        let lastPartial = before.last.map { $0.isLetter || $0.isNumber } == true ? String(before.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).last ?? "") : ""
        let candidate = norm((s.first?.isLetter == true && !lastPartial.isEmpty ? lastPartial : "") + s)
        if candidate.split(separator: " ").count >= 4 {
            let pool = norm(String(before.suffix(3000))) + " \n " + norm(String(existing.prefix(6000)))
            if pool.contains(candidate) { return "" }
        }
        // Joining: a new word after a complete word needs a space; mid-word it must not have one.
        let lastChar = before.last
        let firstChar = s.first!
        if let lc = lastChar, lc.isLetter || lc.isNumber, firstChar.isLetter {
            let lastWord = String(before.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).last ?? "")
            if Spell.isWord(lastWord) { s = " " + s }
        } else if let lc = lastChar, lc == " " || lc == "\n", firstChar == " " {
            s = String(s.drop(while: { $0 == " " }))
        } else if lastChar == nil, firstChar == " " {
            s = String(s.drop(while: { $0 == " " }))
        }
        // Cap the word count at a boundary; collapses runs of spaces too.
        let lead = s.prefix(while: { $0 == " " })
        let words = s.dropFirst(lead.count).split(separator: " ", omittingEmptySubsequences: true).prefix(maxWords)
        s = String(lead) + words.joined(separator: " ")
        return s
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
