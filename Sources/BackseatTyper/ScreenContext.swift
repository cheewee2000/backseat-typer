import AppKit
import ApplicationServices

/// Text visible on screen beyond the focused field: the rest of its window, then the windows beside it.
/// Read through the Accessibility tree, never pixels. Cached for a few seconds because a tree walk costs
/// tens to hundreds of milliseconds in a browser.
enum ScreenContext {
    private struct Snapshot { var window: String; var others: String; var at: Date; var key: AXUIElement? }
    private static var cache: Snapshot?
    private static let lock = NSLock()
    private static let textRoles: Set<String> = ["AXStaticText", "AXTextArea", "AXTextField", "AXHeading", "AXComboBox"]
    /// Window chrome: tab titles, toolbars and menus say nothing about what the writer is reading.
    private static let skipRoles: Set<String> = ["AXToolbar", "AXTabGroup", "AXMenuBar", "AXMenu", "AXPopUpButton", "AXRadioGroup", "AXSheet"]

    static func gather(focused: FocusContext) -> (window: String, others: String) {
        lock.lock(); defer { lock.unlock() }
        let win = AX.attr(focused.element, kAXWindowAttribute as String).map { $0 as! AXUIElement }
        if let c = cache, Date().timeIntervalSince(c.at) < 3, let k = c.key, let w = win, CFEqual(k, w) { return (c.window, c.others) }
        var windowText = "", winFrame: CGRect?
        if let w = win {
            winFrame = frame(w)
            windowText = String(text(in: w, exclude: focused.element, visible: winFrame).suffix(2000))   // chats: newest at the bottom
        }
        var others = "", count = 0
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        for info in list where count < 3 && others.count < 3000 {   // front to back
            guard (info[kCGWindowLayer as String] as? Int) == 0, let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != getpid(),
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            guard r.width >= 300, r.height >= 200 else { continue }
            if let wf = winFrame {
                if abs(wf.minX - r.minX) < 4, abs(wf.minY - r.minY) < 4 { continue }                 // the focused window itself
                let covered = wf.intersection(r); if covered.width * covered.height > 0.7 * r.width * r.height { continue }   // hidden behind it
            }
            guard let ax = axWindow(pid: pid, bounds: r, title: info[kCGWindowName as String] as? String) else { continue }
            let t = String(text(in: ax, exclude: nil, visible: r).prefix(2000))
            if t.count > 40 {
                others += "\n\n[\(NSRunningApplication(processIdentifier: pid)?.localizedName ?? "window")]\n\(t)"; count += 1
            }
        }
        cache = Snapshot(window: windowText, others: others, at: Date(), key: win)
        return (windowText, others)
    }

    /// Breadth-first over the tree, document order; only elements whose frame touches `visible`.
    private static func text(in root: AXUIElement, exclude: AXUIElement?, visible: CGRect?) -> String {
        var out: [String] = [], total = 0, nodes = 0, queue = [webArea(under: root) ?? root]
        while !queue.isEmpty, nodes < 800, total < 12000 {
            let el = queue.removeFirst(); nodes += 1
            if let ex = exclude, CFEqual(el, ex) { continue }
            if let v = visible, let f = frame(el), !f.intersects(v.insetBy(dx: -2, dy: -2)) { continue }
            let role = AX.attr(el, kAXRoleAttribute as String) as? String ?? ""
            if skipRoles.contains(role) { continue }
            if textRoles.contains(role), let s = AX.attr(el, kAXValueAttribute as String) as? String {
                let t = String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
                if t.count >= 2, out.last != t { out.append(t); total += t.count + 1 }
            }
            if let kids = AX.attr(el, kAXChildrenAttribute as String) as? [AXUIElement] { queue.append(contentsOf: kids.prefix(200)) }
        }
        return out.joined(separator: "\n")
    }

    /// A browser window's page content; the walk starts there instead of at the window.
    private static func webArea(under root: AXUIElement) -> AXUIElement? {
        var queue = [root], nodes = 0
        while !queue.isEmpty, nodes < 300 {
            let el = queue.removeFirst(); nodes += 1
            let role = AX.attr(el, kAXRoleAttribute as String) as? String ?? ""
            if role == "AXWebArea" { return el }
            if skipRoles.contains(role) { continue }
            if let kids = AX.attr(el, kAXChildrenAttribute as String) as? [AXUIElement] { queue.append(contentsOf: kids.prefix(50)) }
        }
        return nil
    }

    private static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = AX.attr(el, kAXPositionAttribute as String), let s = AX.attr(el, kAXSizeAttribute as String) else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &pt), AXValueGetValue(s as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: pt, size: sz)
    }

    private static func axWindow(pid: pid_t, bounds: CGRect, title: String?) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)   // an unresponsive app must not stall the completion
        guard let wins = AX.attr(app, kAXWindowsAttribute as String) as? [AXUIElement] else { return nil }
        if let w = wins.first(where: { frame($0).map { abs($0.minX - bounds.minX) < 4 && abs($0.minY - bounds.minY) < 4 } ?? false }) { return w }
        if let t = title, !t.isEmpty, let w = wins.first(where: { (AX.attr($0, kAXTitleAttribute as String) as? String) == t }) { return w }
        return wins.count == 1 ? wins[0] : nil
    }
}
