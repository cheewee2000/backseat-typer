import AppKit
import ApplicationServices

/// Form filling from the vault, system-wide through Accessibility. Label discovery mirrors Form Filler's
/// content.js (label[for], aria-label, wrapping label, preceding text, placeholder) in AX terms.
enum FormFill {
    struct Match { var element: AXUIElement; var label: String; var value: String; var sensitive: Bool }
    private static let fieldRoles: Set<String> = ["AXTextField", "AXComboBox", "AXTextArea"]

    /// The label a person would read for this field.
    static func label(of el: AXUIElement) -> String {
        func str(_ a: String) -> String? { (AX.attr(el, a) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        if let t = str(kAXTitleAttribute as String) { return t }
        if let t = str(kAXDescriptionAttribute as String) { return t }
        if let tu = AX.attr(el, kAXTitleUIElementAttribute as String) {
            let t = tu as! AXUIElement
            if let s = (AX.attr(t, kAXValueAttribute as String) as? String ?? AX.attr(t, kAXTitleAttribute as String) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty { return s }
            if let s = text(under: t) { return s }   // Chrome's <label> is a group whose words sit in static text children
        }
        if let p = str(kAXPlaceholderValueAttribute as String) { return p }
        // Nearest preceding static text, like content.js walks previousElementSibling, climbing out of the wrapper
        // divs web forms put around inputs (Chrome exposes each as an AXGroup).
        var cur = el
        for _ in 0..<4 {
            guard let parent = AX.attr(cur, kAXParentAttribute as String), let kids = AX.attr(parent as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement],
                  let i = kids.firstIndex(where: { CFEqual($0, cur) }) else { break }
            for k in kids[..<i].reversed().prefix(3) { if let s = lastText(in: k), s.count < 80 { return s } }
            cur = parent as! AXUIElement
        }
        return ""
    }
    /// The last static text in a subtree, skipping other fields (their values are not labels).
    private static func lastText(in el: AXUIElement, depth: Int = 3) -> String? {
        let role = AX.attr(el, kAXRoleAttribute as String) as? String ?? ""
        // A lone "*" or ":" is a required marker beside the label, not the label.
        if role == "AXStaticText" { return (AX.attr(el, kAXValueAttribute as String) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty.flatMap { $0.contains(where: \.isLetter) ? $0 : nil } }
        guard depth > 0, !fieldRoles.contains(role), let kids = AX.attr(el, kAXChildrenAttribute as String) as? [AXUIElement] else { return nil }
        for k in kids.suffix(10).reversed() { if let s = lastText(in: k, depth: depth - 1) { return s } }
        return nil
    }
    /// Every string attribute on an element, for the no-match log.
    static func dump(_ el: AXUIElement) -> String {
        var names: CFArray?
        AXUIElementCopyAttributeNames(el, &names)
        return ((names as? [String]) ?? []).compactMap { n in (AX.attr(el, n) as? String).flatMap { $0.isEmpty ? nil : "\(n)=\(String($0.prefix(40)).debugDescription)" } }.joined(separator: " ")
    }
    /// The static text inside a label element, a few levels deep.
    private static func text(under el: AXUIElement, depth: Int = 3) -> String? {
        guard depth > 0, let kids = AX.attr(el, kAXChildrenAttribute as String) as? [AXUIElement] else { return nil }
        let s = kids.prefix(20).compactMap { k -> String? in
            (AX.attr(k, kAXRoleAttribute as String) as? String) == "AXStaticText" ? AX.attr(k, kAXValueAttribute as String) as? String : text(under: k, depth: depth - 1)
        }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
    /// The DOM id or name on web fields, Form Filler's second signal after the label.
    static func name(of el: AXUIElement) -> String { AX.attr(el, "AXDOMIdentifier") as? String ?? "" }

    static func match(_ el: AXUIElement, profile: String) -> Match? {
        let vault = Vault.shared.data
        let l = label(of: el)
        if l.localizedCaseInsensitiveContains("search") { return nil }   // Chrome's "Address and search bar" is not a street address
        let tpl = Matcher.matchWeb(label: l, name: name(of: el), autocomplete: "", pid: profile, vault: vault)
        guard !tpl.isEmpty else { return nil }
        let v = Template.render(tpl, vault)
        guard !v.isEmpty else { return nil }
        return Match(element: el, label: l, value: v, sensitive: Template.isSensitive(tpl, vault))
    }

    static func isField(_ c: FocusContext) -> Bool { fieldRoles.contains(c.role) && c.subrole != "AXSearchField" && !c.isSecure }
    static func isEmptyField(_ c: FocusContext) -> Bool {
        fieldRoles.contains(c.role) && c.subrole != "AXSearchField" && c.before.isEmpty && c.after.isEmpty && !c.isSecure
    }

    /// Sets the value through AX when the app allows it (atomic, fires the field's own change handling).
    @discardableResult static func set(_ el: AXUIElement, _ value: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue else { return false }
        return AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, value as CFString) == .success
    }

    private static func readback(_ e: AXUIElement, _ v: String) -> Bool {
        for _ in 0..<6 {   // the value lands asynchronously in browsers
            if (AX.attr(e, kAXValueAttribute as String) as? String) == v { return true }
            usleep(50_000)
        }
        return false
    }
    /// Every empty, visible field in the window that matches the vault. Returns (filled, skipped as sensitive).
    /// The window to fill: the focused element's window, else the frontmost app's focused window.
    static func frontWindow() -> AXUIElement? {
        if let el = AX.attr(AX.systemWide, kAXFocusedUIElementAttribute as String), let w = AX.attr(el as! AXUIElement, kAXWindowAttribute as String) { return (w as! AXUIElement) }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return AX.attr(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute as String).map { $0 as! AXUIElement }
    }
    /// First text field in the window (optionally by label), for the e2e driver to focus.
    static func firstField(in w: AXUIElement, labelled: String? = nil) -> AXUIElement? {
        var queue = [w], nodes = 0
        while !queue.isEmpty, nodes < 1500 {
            let e = queue.removeFirst(); nodes += 1
            if fieldRoles.contains(AX.attr(e, kAXRoleAttribute as String) as? String ?? ""), labelled.map({ label(of: e).localizedCaseInsensitiveContains($0) }) ?? true { return e }
            if let kids = AX.attr(e, kAXChildrenAttribute as String) as? [AXUIElement] { queue.append(contentsOf: kids.prefix(300)) }
        }
        return nil
    }
    static func fillWindow(_ w: AXUIElement, profile: String, includeSensitive: Bool) -> (Int, Int) {
        var queue = [w], nodes = 0, filled = 0, skipped = 0
        while !queue.isEmpty, nodes < 1500 {
            let e = queue.removeFirst(); nodes += 1
            let role = AX.attr(e, kAXRoleAttribute as String) as? String ?? ""
            if fieldRoles.contains(role), (AX.attr(e, kAXSubroleAttribute as String) as? String) != "AXSearchField",
               ((AX.attr(e, kAXValueAttribute as String) as? String) ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
               let m = match(e, profile: profile) {
                if m.sensitive && !includeSensitive { skipped += 1; Log.w("FILL skip sensitive \(m.label.debugDescription)"); continue }
                AXUIElementSetAttributeValue(e, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                var ok = set(e, m.value) && readback(e, m.value)
                if !ok { Controller.shared.tap.type(m.value); ok = readback(e, m.value) }   // a field that ignores AX writes still takes keystrokes
                Log.w("FILL \(m.label.debugDescription) -> \(m.sensitive ? Template.mask(m.value) : m.value.debugDescription) ok=\(ok)")
                if ok { filled += 1 }
                continue
            }
            if let kids = AX.attr(e, kAXChildrenAttribute as String) as? [AXUIElement] { queue.append(contentsOf: kids.prefix(300)) }
        }
        return (filled, skipped)
    }
}

extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }


/// Remembers what you type into labelled fields, into the vault, so the next form with the same label fills itself.
enum FormLearn {
    private static let skip = try! NSRegularExpression(pattern: #"search|password|passcode|\bpin\b|cvv|cvc|card number|security code|captcha|message|reply|chat|prompt|otp|verification code|document content"#, options: [.caseInsensitive])
    static func clean(_ raw: String) -> String {
        var l = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        l = l.replacingOccurrences(of: #"\s*(\(required\)|\(optional\)|required|optional|\*|:)+\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return String(l.trimmingCharacters(in: .whitespaces).prefix(60))
    }
    static func remember(label raw: String, value: String, multiline: Bool, profile: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines), label = clean(raw)
        guard (3...60).contains(label.count), (1...2000).contains(v.count),
              skip.firstMatch(in: label, range: NSRange(location: 0, length: (label as NSString).length)) == nil,
              v.filter(\.isNumber).count < 13 else { return }   // never a card number
        let vault = Vault.shared
        let tpl = Matcher.match(label, pid: profile, vault: vault.data)
        if tpl.isEmpty {
            let key = vault.data.addCustomField(label: label, kind: multiline ? .list : .text, sensitive: false)
            vault.data.setValue(profile, key, v)
        } else {
            // Only a plain single-field template: an empty schema field, or a learned field whose answer changed.
            let refs = Template.refs(in: tpl)
            guard refs.count == 1, let ref = refs.first, tpl == "{\(ref.pid).\(ref.key)}" || tpl.hasSuffix("|lines}"), let f = vault.data.field(ref.key), f.kind != .date else { return }
            let current = vault.data.value(profile, ref.key)
            guard current.isEmpty || (f.custom && current != v) else { return }
            vault.data.setValue(profile, ref.key, v)
        }
        vault.save(); Log.w("LEARN \(label.debugDescription) (\(v.count) chars)")
    }
}
