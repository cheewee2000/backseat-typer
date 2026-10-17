import AppKit
import ApplicationServices

struct FocusContext {
    var element: AXUIElement
    var pid: pid_t
    var bundleID: String
    var appName: String
    var role: String
    var subrole: String
    var before: String
    var after: String
    var selected: String
    var caret: Int
    var caretRect: CGRect?   // AppKit coordinates
    var font: NSFont          // the font at the caret, so ghost text matches the context
    var textColor: NSColor
    var fontSize: CGFloat { font.pointSize }
    var isSecure: Bool { subrole == (kAXSecureTextFieldSubrole as String) }
}

enum AX {
    static let systemWide = AXUIElementCreateSystemWide()

    static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
    static func param(_ el: AXUIElement, _ name: String, _ p: CFTypeRef) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(el, name as CFString, p, &v) == .success ? v : nil
    }
    static func rangeValue(_ r: CFRange) -> AXValue { var r = r; return AXValueCreate(.cfRange, &r)! }
    static func cfRange(_ v: CFTypeRef?) -> CFRange? {
        guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CFRange(); return AXValueGetValue(v as! AXValue, .cfRange, &r) ? r : nil
    }
    static func cgRect(_ v: CFTypeRef?) -> CGRect? {
        guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero; return AXValueGetValue(v as! AXValue, .cgRect, &r) ? r : nil
    }
    /// AX uses a top-left origin on the primary screen; AppKit a bottom-left one.
    static func toAppKit(_ r: CGRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }
    static func string(_ el: AXUIElement, _ r: CFRange) -> String? {
        guard r.length > 0 else { return "" }
        return param(el, kAXStringForRangeParameterizedAttribute as String, rangeValue(r)) as? String
    }

    static func focusedContext(beforeMax: Int = 1500, afterMax: Int = 400) -> FocusContext? {
        guard let el = attr(systemWide, kAXFocusedUIElementAttribute as String) else { return nil }
        let element = el as! AXUIElement
        var pid: pid_t = 0; AXUIElementGetPid(element, &pid)
        let app = NSRunningApplication(processIdentifier: pid)
        let role = attr(element, kAXRoleAttribute as String) as? String ?? ""
        let subrole = attr(element, kAXSubroleAttribute as String) as? String ?? ""
        guard let sel = cfRange(attr(element, kAXSelectedTextRangeAttribute as String)) else { return nil }
        let caret = sel.location
        var total = attr(element, kAXNumberOfCharactersAttribute as String) as? Int ?? -1
        var before: String?, after: String?
        if total >= 0 {
            let s = max(0, caret - beforeMax)
            before = string(element, CFRange(location: s, length: caret - s))
            let e = min(total, caret + sel.length + afterMax)
            after = string(element, CFRange(location: caret + sel.length, length: max(0, e - caret - sel.length)))
        }
        if before == nil {  // fall back to the whole value
            let v = (attr(element, kAXValueAttribute as String) as? String ?? "") as NSString
            total = v.length
            guard caret <= total else { return nil }
            before = v.substring(with: NSRange(location: max(0, caret - beforeMax), length: caret - max(0, caret - beforeMax)))
            let aStart = min(total, caret + sel.length)
            after = v.substring(with: NSRange(location: aStart, length: min(afterMax, total - aStart)))
        }
        let selected = sel.length > 0 ? (string(element, sel) ?? "") : ""
        // Caret position: right edge of the previous character, else the element's frame.
        var rect: CGRect?
        if caret > 0, let r = cgRect(param(element, kAXBoundsForRangeParameterizedAttribute as String, rangeValue(CFRange(location: caret - 1, length: 1)))), r.height > 1, r.height < 400 {
            rect = toAppKit(CGRect(x: r.maxX, y: r.minY, width: 0, height: r.height))
        } else if let r = cgRect(param(element, kAXBoundsForRangeParameterizedAttribute as String, rangeValue(CFRange(location: caret, length: 1)))), r.height > 1, r.height < 400 {
            rect = toAppKit(CGRect(x: r.minX, y: r.minY, width: 0, height: r.height))
        } else if let p = cgRect(attr(element, kAXPositionAttribute as String).map { pt -> CFTypeRef in pt }).map({ $0 }) {
            rect = toAppKit(p)
        }
        if rect == nil, let pos = attr(element, kAXPositionAttribute as String), let size = attr(element, kAXSizeAttribute as String) {
            var p = CGPoint.zero, s = CGSize.zero
            if AXValueGetValue(pos as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) {
                let f = toAppKit(CGRect(origin: p, size: s))
                rect = CGRect(x: f.minX + 6, y: f.minY + 4, width: 0, height: min(18, f.height - 8))
            }
        }
        var font: NSFont? = nil
        var color: NSColor = .textColor
        if caret > 0, let a = param(element, kAXAttributedStringForRangeParameterizedAttribute as String, rangeValue(CFRange(location: caret - 1, length: 1))) as? NSAttributedString, a.length > 0 {
            let attrs = a.attributes(at: 0, effectiveRange: nil)
            if let f = attrs[NSAttributedString.Key("AXFont")] as? [String: Any] {
                let sz = f["AXFontSize"] as? CGFloat ?? 13
                font = (f["AXFontName"] as? String).flatMap { NSFont(name: $0, size: sz) }
                    ?? (f["AXFontFamily"] as? String).flatMap { NSFont(name: $0, size: sz) } ?? NSFont.systemFont(ofSize: sz)
            } else if let f = attrs[.font] as? NSFont { font = f }
            if let cg = attrs[NSAttributedString.Key("AXForegroundColor")], CFGetTypeID(cg as CFTypeRef) == CGColor.typeID,
               let c = NSColor(cgColor: cg as! CGColor) { color = c }
            else if let c = attrs[.foregroundColor] as? NSColor { color = c }
        }
        let fallbackSize = max(11, min(28, (rect?.height ?? 18) * 0.72))
        return FocusContext(element: element, pid: pid, bundleID: app?.bundleIdentifier ?? "pid.\(pid)", appName: app?.localizedName ?? "App",
                            role: role, subrole: subrole, before: before ?? "", after: after ?? "", selected: selected,
                            caret: caret, caretRect: rect, font: font ?? NSFont.systemFont(ofSize: fallbackSize), textColor: color)
    }
}
