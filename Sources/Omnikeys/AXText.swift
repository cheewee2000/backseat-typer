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
    nonisolated(unsafe) static var nudged = Set<pid_t>()   // Chromium processes already switched to full accessibility
    nonisolated(unsafe) static var docsCursor = [pid_t: AXUIElement]()
    /// Google Docs draws the document on a canvas; its focused edit target has no usable geometry, but the caret is a
    /// DOM element (class kix-cursor) that Chrome exposes with a frame. Found by a one-time walk of the Docs window,
    /// then re-read each time. Only runs when the focused window is a Google Docs tab.
    static func docsCaret(pid: pid_t) -> CGRect? {
        func frame(_ e: AXUIElement) -> CGRect? {
            guard let r = cgRect(attr(e, "AXFrame")), r.height >= 8, r.height <= 80, r.width <= 4 else { return nil }
            return r
        }
        if let e = docsCursor[pid], let r = frame(e) { return r }
        docsCursor[pid] = nil
        guard let win = attr(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as String),
              (attr(win as! AXUIElement, kAXTitleAttribute as String) as? String)?.contains("Google Docs") == true else { return nil }
        var n = 0, found: AXUIElement?
        func walk(_ e: AXUIElement, _ depth: Int) {
            guard found == nil, n < 4000, depth < 60 else { return }
            n += 1
            if let cls = attr(e, "AXDOMClassList") as? [String], cls.contains("kix-cursor") { found = e; return }
            for k in (attr(e, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] { walk(k, depth + 1) }
        }
        walk(win as! AXUIElement, 0)
        guard let e = found, let r = frame(e) else { Log.w("AX: no kix-cursor in Google Docs window after \(n) elements"); return nil }
        docsCursor[pid] = e
        return r
    }

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
        guard let sel = cfRange(attr(element, kAXSelectedTextRangeAttribute as String)) else {
            Log.w("AX: no selected text range on \(role)/\(subrole) in \(app?.localizedName ?? "?") value=\(attr(element, kAXValueAttribute as String) == nil ? "none" : "yes")")
            return nil
        }
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
        // Terminal emulators (Knife Terminal) report never-written cells as NUL; those are spaces to the model and the copy filter.
        let selected = sel.length > 0 ? (string(element, sel) ?? "") : ""
        // Caret position: right edge of the previous character, else the element's frame.
        var rect: CGRect?
        var how = "none"
        if caret > 0, let r = cgRect(param(element, kAXBoundsForRangeParameterizedAttribute as String, rangeValue(CFRange(location: caret - 1, length: 1)))), r.height > 1, r.height < 400, r.width < 400 {
            rect = toAppKit(CGRect(x: r.maxX, y: r.minY, width: 0, height: r.height)); how = "prev-char"
        } else if let r = cgRect(param(element, kAXBoundsForRangeParameterizedAttribute as String, rangeValue(CFRange(location: caret, length: 1)))), r.height > 1, r.height < 400, r.width < 400 {
            rect = toAppKit(CGRect(x: r.minX, y: r.minY, width: 0, height: r.height)); how = "next-char"
        } else if let r = cgRect(param(element, kAXBoundsForRangeParameterizedAttribute as String, rangeValue(CFRange(location: caret, length: 0)))), r.height > 1, r.height < 400 {
            rect = toAppKit(CGRect(x: r.minX, y: r.minY, width: 0, height: r.height)); how = "caret"
        }
        // Chromium (Electron, Chrome) answers range bounds with empty rects but gives the caret through text markers,
        // and only after an assistive client has announced itself with AXManualAccessibility on the app. Nudge once
        // per process; Chromium rebuilds its tree within a second and the next refresh gets real geometry.
        if rect == nil, let mr = attr(element, "AXSelectedTextMarkerRange") {
            if let r = cgRect(param(element, "AXBoundsForTextMarkerRange", mr)), r.height > 1, r.height < 400 {
                rect = toAppKit(CGRect(x: r.minX, y: r.minY, width: 0, height: r.height)); how = "marker"
            } else if !nudged.contains(pid) {
                nudged.insert(pid)
                AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
                Log.w("AX: enabled Chromium accessibility for \(app?.localizedName ?? "pid \(pid)")")
            }
        }
        if rect == nil, let r = docsCaret(pid: pid) { rect = toAppKit(CGRect(x: r.minX, y: r.minY, width: 0, height: r.height)); how = "kix-cursor" }
        if rect == nil, let pos = attr(element, kAXPositionAttribute as String), let size = attr(element, kAXSizeAttribute as String) {
            var p = CGPoint.zero, s = CGSize.zero
            if AXValueGetValue(pos as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) {
                let f = toAppKit(CGRect(origin: p, size: s))
                // No character geometry: top-left of the field for a one-line field, else the bottom-left line.
                rect = s.height < 60 ? CGRect(x: f.minX + 6, y: f.minY + (f.height - min(18, f.height - 8)) / 2, width: 0, height: min(18, f.height - 8))
                                     : CGRect(x: f.minX + 6, y: f.maxY - 22, width: 0, height: 18)
                how = "frame"
            }
        }
        Log.lastCaretHow = how
        var font: NSFont? = nil
        var color: NSColor? = nil
        func read(_ el: AXUIElement, _ r: CFRange) {
            guard let a = param(el, kAXAttributedStringForRangeParameterizedAttribute as String, rangeValue(r)) as? NSAttributedString, a.length > 0 else { return }
            let attrs = a.attributes(at: 0, effectiveRange: nil)
            if font == nil, let f = attrs[NSAttributedString.Key("AXFont")] as? [String: Any] {
                let sz = f["AXFontSize"] as? CGFloat ?? 13
                font = (f["AXFontName"] as? String).flatMap { NSFont(name: $0, size: sz) }
                    ?? (f["AXFontFamily"] as? String).flatMap { NSFont(name: $0, size: sz) } ?? NSFont.systemFont(ofSize: sz)
            } else if font == nil, let f = attrs[.font] as? NSFont { font = f }
            if let cg = attrs[NSAttributedString.Key("AXForegroundColor")], CFGetTypeID(cg as CFTypeRef) == CGColor.typeID,
               let c = NSColor(cgColor: cg as! CGColor) { color = c }
            else if let c = attrs[.foregroundColor] as? NSColor { color = c }
        }
        // The text colour: the character before the caret, else the first character, else the field's own label
        // (an empty field has no text of its own), else the system theme. Overlay adds a contrasting halo anyway.
        if caret > 0 { read(element, CFRange(location: caret - 1, length: 1)) }
        if color == nil, total > 0 { read(element, CFRange(location: 0, length: 1)) }
        if color == nil, let t = attr(element, kAXTitleUIElementAttribute as String) { read(t as! AXUIElement, CFRange(location: 0, length: 1)) }
        if color == nil, let parent = attr(element, kAXParentAttribute as String), let kids = attr(parent as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement],
           let i = kids.firstIndex(where: { CFEqual($0, element) }) {
            for k in kids[..<i].reversed().prefix(3) where (attr(k, kAXRoleAttribute as String) as? String) == "AXStaticText" { read(k, CFRange(location: 0, length: 1)); if color != nil { break } }
        }
        let dark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fallbackSize = max(11, min(28, (rect?.height ?? 18) * 0.72))
        return FocusContext(element: element, pid: pid, bundleID: app?.bundleIdentifier ?? "pid.\(pid)", appName: app?.localizedName ?? "App",
                            role: role, subrole: subrole, before: (before ?? "").replacingOccurrences(of: "\0", with: " "), after: (after ?? "").replacingOccurrences(of: "\0", with: " "), selected: selected,
                            caret: caret, caretRect: rect, font: font ?? NSFont.systemFont(ofSize: fallbackSize), textColor: color ?? (dark ? .white : .black))
    }
}
