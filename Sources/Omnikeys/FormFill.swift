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
        }
        if let p = str(kAXPlaceholderValueAttribute as String) { return p }
        // Nearest preceding static text among the siblings, like content.js walks previousElementSibling.
        if let parent = AX.attr(el, kAXParentAttribute as String), let kids = AX.attr(parent as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement],
           let i = kids.firstIndex(where: { CFEqual($0, el) }) {
            for k in kids[..<i].reversed().prefix(3) {
                if (AX.attr(k, kAXRoleAttribute as String) as? String) == "AXStaticText", let s = (AX.attr(k, kAXValueAttribute as String) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s.count < 80 { return s }
            }
        }
        return ""
    }
    /// The DOM id or name on web fields, Form Filler's second signal after the label.
    static func name(of el: AXUIElement) -> String { AX.attr(el, "AXDOMIdentifier") as? String ?? "" }

    static func match(_ el: AXUIElement, profile: String) -> Match? {
        let vault = Vault.shared.data
        let l = label(of: el)
        let tpl = Matcher.matchWeb(label: l, name: name(of: el), autocomplete: "", pid: profile, vault: vault)
        guard !tpl.isEmpty else { return nil }
        let v = Template.render(tpl, vault)
        guard !v.isEmpty else { return nil }
        return Match(element: el, label: l, value: v, sensitive: Template.isSensitive(tpl, vault))
    }

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
    /// First empty text field in the window, for the e2e driver to focus.
    static func firstField(in w: AXUIElement) -> AXUIElement? {
        var queue = [w], nodes = 0
        while !queue.isEmpty, nodes < 1500 {
            let e = queue.removeFirst(); nodes += 1
            if fieldRoles.contains(AX.attr(e, kAXRoleAttribute as String) as? String ?? "") { return e }
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
