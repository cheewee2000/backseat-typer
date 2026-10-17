import AppKit
import FoundationModels

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
}

final class Engine {
    static let shared = Engine()
    let model = SystemLanguageModel.default
    var available: Bool { if case .available = model.availability { return true }; return false }
    var statusText: String {
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
    You are an inline autocomplete engine, like predictive text on a keyboard. The user is typing. You output only the words that come next, continuing their text seamlessly in the same language, register and style. Never explain, never comment, never repeat text that is already written, never wrap the output in quotes. If the text ends mid-word, finish that word first.
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
        // The 3B model loses the thread when anything follows the typed text, so the prompt is the text alone
        // and everything else (writer notes, samples, clipboard) lives in the instructions. Plain string output:
        // the JSON wrapper of @Generable ate most of a 20-token budget and left one-word suggestions.
        var ins = instructions(r, custom: custom)
        if let c = r.clipboard, !c.isEmpty { ins += "\n\nThe writer's clipboard, which may be relevant:\n\(c.prefix(300))" }
        let afterLine = r.after.prefix(while: { $0 != "\n" })
        if !afterLine.trimmingCharacters(in: .whitespaces).isEmpty { ins += "\n\nThe text after the cursor is: \(afterLine.prefix(200))\nYour words must fit before it." }
        ins += "\n\nExample:\nText: I went to the\nContinuation: store to pick up milk"
        let session = LanguageModelSession(model: model, instructions: ins)
        let prompt = "Text: \(r.before.suffix(1500))\nContinuation:"
        let tokens: Int
        switch r.length { case .short: tokens = 12; case .medium: tokens = 24; case .long: tokens = 48 }
        let opts = GenerationOptions(sampling: .greedy, temperature: 0, maximumResponseTokens: tokens)
        let out = try await session.respond(to: prompt, options: opts).content
        return Engine.clean(before: r.before, raw: out, maxWords: r.length == .short ? 3 : (r.length == .medium ? 8 : 20))
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
    static func clean(before: String, raw: String, maxWords: Int) -> String {
        var s = raw.replacingOccurrences(of: "\r", with: "")
        if let nl = s.firstIndex(of: "\n") { s = String(s[..<nl]) }   // single line
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”`"))
        // Strip anything the model repeated from the end of the context.
        let tail = String(before.suffix(60))
        for k in stride(from: min(tail.count, s.count), through: 2, by: -1) {
            if s.hasPrefix(tail.suffix(k)) { s = String(s.dropFirst(k)); break }
        }
        if s.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
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
