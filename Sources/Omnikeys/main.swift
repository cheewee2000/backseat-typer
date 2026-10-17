import AppKit
import SwiftUI
import Carbon.HIToolbox

if CommandLine.arguments.contains("--selftest") { exit(SelfTest.run() ? 0 : 1) }
if let i = CommandLine.arguments.firstIndex(of: "--screenshot"), i + 1 < CommandLine.arguments.count {
    // Renders the settings window to a PNG without needing Screen Recording permission.
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        let tab = CommandLine.arguments.firstIndex(of: "--tab").map { CommandLine.arguments[$0 + 1] } ?? "general"
        let v = NSHostingView(rootView: SettingsRoot(s: Settings.shared, c: Controller.shared, tab: tab))
        v.appearance = NSAppearance(named: .aqua)
        v.frame = NSRect(x: 0, y: 0, width: 820, height: 600)
        let w = NSWindow(contentRect: v.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = v; w.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
        v.cacheDisplay(in: v.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        exit(0)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    let controller = Controller.shared

    // e2e driver: only when launched with --e2e (scripts/e2e.sh). The shell host is not AX-trusted; this app is,
    // so the test script asks the app to type via omnikeys://type?text=… and omnikeys://key?code=…
    let e2e = CommandLine.arguments.contains("--e2e")
    func applicationWillFinishLaunching(_ n: Notification) {
        guard e2e else { return }
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:_:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }
    @objc func handleURL(_ event: NSAppleEventDescriptor, _ reply: NSAppleEventDescriptor) {
        guard e2e, let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URLComponents(string: s) else { return }
        Log.w("e2e url \(s)")
        let q = Dictionary((url.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        switch url.host {
        case "type": controller.tap.simulate(text: q["text"] ?? "")
        case "key":
            if let c = UInt16(q["code"] ?? "") {
                var f = CGEventFlags()
                if q["flags"]?.contains("control") == true { f.insert(.maskControl) }
                if q["flags"]?.contains("option") == true { f.insert(.maskAlternate) }
                if q["flags"]?.contains("command") == true { f.insert(.maskCommand) }
                controller.tap.simulate(key: c, flags: f)
            }
        case "vault": Vault.shared.loadPlain(path: q["file"] ?? "")   // test data, never saved
        case "fill": controller.fillForm()
        case "focusrole":   // give keyboard focus to the first element of a role in the front window (tests: a note's body)
            guard let app = NSWorkspace.shared.frontmostApplication, let win = AX.attr(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute as String) else { Log.w("focusrole: no window"); return }
            let want = q["role"] ?? "AXTextArea"
            var stack: [AXUIElement] = [win as! AXUIElement], n = 0
            while let e = stack.popLast(), n < 3000 {
                n += 1
                if (AX.attr(e, kAXRoleAttribute as String) as? String) == want {
                    let r = AXUIElementSetAttributeValue(e, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                    Log.w("focusrole: \(want) focus -> \(r.rawValue) value=\(((AX.attr(e, kAXValueAttribute as String) as? String) ?? "").prefix(60).debugDescription)"); return
                }
                stack += (AX.attr(e, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
            }
            Log.w("focusrole: no \(want) in \(n) elements")
        case "axfind":   // walk the focused window for caret-shaped elements (Google Docs draws its own caret as a DOM div)
            guard let el = AX.attr(AX.systemWide, kAXFocusedUIElementAttribute as String) else { Log.w("axfind: no focus"); return }
            var pid: pid_t = 0; AXUIElementGetPid(el as! AXUIElement, &pid)
            let app = AXUIElementCreateApplication(pid)
            guard let win = AX.attr(app, kAXFocusedWindowAttribute as String) else { Log.w("axfind: no window"); return }
            var n = 0, hits = 0
            func walk(_ e: AXUIElement, _ depth: Int) {
                n += 1; if n > 20000 || depth > 60 { return }
                let role = AX.attr(e, kAXRoleAttribute as String) as? String ?? "?"
                if let f = AX.attr(e, "AXFrame"), let r = AX.cgRect(f), r.width <= 3, r.height >= 8, r.height <= 60 {
                    hits += 1
                    if hits <= 12 { Log.w("axfind hit role=\(role) sub=\(AX.attr(e, kAXSubroleAttribute as String) as? String ?? "") frame=\(r) desc=\((AX.attr(e, kAXDescriptionAttribute as String) as? String ?? "").prefix(40)) dom=\((AX.attr(e, "AXDOMClassList") as? [String] ?? []).joined(separator: " ").prefix(60))") }
                }
                for k in (AX.attr(e, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] { walk(k, depth + 1) }
            }
            walk(win as! AXUIElement, 0)
            Log.w("axfind walked \(n) elements, \(hits) caret-shaped")
        case "raise":   // raise the window of a process whose title contains the given text
            if let t = q["title"] {
                let pids = q["pid"].flatMap(Int32.init).map { [$0] } ?? NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == (q["bundle"] ?? "com.google.Chrome") }.map(\.processIdentifier)
                for pid in pids {
                    let wins = AX.attr(AXUIElementCreateApplication(pid), kAXWindowsAttribute as String) as? [AXUIElement] ?? []
                    let titles = wins.map { AX.attr($0, kAXTitleAttribute as String) as? String ?? "" }
                    if let i = titles.firstIndex(where: { $0.contains(t) }) {
                        AXUIElementPerformAction(wins[i], kAXRaiseAction as CFString); NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
                    }
                    Log.w("e2e raise \(t.debugDescription) pid \(pid): windows=\(titles.map { String($0.prefix(40)) })")
                }
            }
        case "activate":   // bring a process to the front (the shell host may not)
            if let pid = Int32(q["pid"] ?? ""), let app = NSRunningApplication(processIdentifier: pid) { Log.w("e2e activate \(app.localizedName ?? "?") -> \(app.activate(options: [.activateIgnoringOtherApps]))") }
        case "axprobe":   // geometry diagnostics for the focused element
            guard let el = AX.attr(AX.systemWide, kAXFocusedUIElementAttribute as String) else { Log.w("axprobe: no focus"); return }
            let e = el as! AXUIElement
            let sel = AX.cfRange(AX.attr(e, kAXSelectedTextRangeAttribute as String))
            Log.w("axprobe role=\(AX.attr(e, kAXRoleAttribute as String) as? String ?? "?") sel=\(sel.map { "\($0.location),\($0.length)" } ?? "nil") n=\(AX.attr(e, kAXNumberOfCharactersAttribute as String) as? Int ?? -1)")
            Log.w("axprobe window=\((AX.attr(AXUIElementCreateApplication({ var p: pid_t = 0; AXUIElementGetPid(e, &p); return p }()), kAXFocusedWindowAttribute as String).flatMap { AX.attr($0 as! AXUIElement, kAXTitleAttribute as String) as? String } ?? "?").prefix(60))")
            Log.w("axprobe value=\(((AX.attr(e, kAXValueAttribute as String) as? String) ?? "").suffix(300).debugDescription)")
            if let r = sel {
                for (name, rg) in [("prev", CFRange(location: max(0, r.location - 1), length: 1)), ("next", CFRange(location: r.location, length: 1)), ("caret", CFRange(location: r.location, length: 0))] {
                    let v = AX.param(e, kAXBoundsForRangeParameterizedAttribute as String, AX.rangeValue(rg))
                    Log.w("axprobe bounds \(name) = \(v.map { String(describing: AX.cgRect($0)) } ?? "nil")")
                }
                if let a = AX.param(e, kAXAttributedStringForRangeParameterizedAttribute as String, AX.rangeValue(CFRange(location: max(0, r.location - 1), length: 1))) as? NSAttributedString, a.length > 0 {
                    Log.w("axprobe attrs = \(a.attributes(at: 0, effectiveRange: nil).keys.map(\.rawValue).sorted())")
                } else { Log.w("axprobe attrs = none") }
            }
            var names: CFArray?; AXUIElementCopyParameterizedAttributeNames(e, &names)
            Log.w("axprobe param attrs = \((names as? [String] ?? []).joined(separator: " "))")
            var plain: CFArray?; AXUIElementCopyAttributeNames(e, &plain)
            Log.w("axprobe attrs = \((plain as? [String] ?? []).filter { $0.contains("Marker") || $0.contains("Frame") || $0.contains("Insertion") }.joined(separator: " "))")
            if let mr = AX.attr(e, "AXSelectedTextMarkerRange") {
                let b = AX.param(e, "AXBoundsForTextMarkerRange", mr)
                Log.w("axprobe marker-range bounds = \(b.map { String(describing: AX.cgRect($0)) } ?? "nil")")
            } else { Log.w("axprobe no AXSelectedTextMarkerRange on element") }
        case "importcontacts":
            Task { do { let k = try await Vault.shared.importMeCard(into: Settings.shared.p.fillProfile); Log.w("vault import from Contacts: \(k)") } catch { Log.w("vault import failed: \(error.localizedDescription)") } }
        case "focusfirst":   // focus the first text field of the front window, as a click would
            if let w = FormFill.frontWindow(), let f = FormFill.firstField(in: w, labelled: q["label"]) {
                AXUIElementSetAttributeValue(f, kAXFocusedAttribute as CFString, kCFBooleanTrue); controller.schedule(after: 300)
            } else { Log.w("e2e focusfirst: no field") }
        default: break
        }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        Log.w("launch v\(Settings.shared.version) model=\(Engine.shared.statusText) ax=\(AXIsProcessTrusted()) e2e=\(e2e)")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = CWT.font(14)
        statusItem.button?.title = "¶"
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        controller.start()
        if !Settings.shared.p.firstRunDone { Settings.shared.p.firstRunDone = true; showSettings() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = Settings.shared
        let c = controller
        let front = NSWorkspace.shared.frontmostApplication
        let bundle = front?.bundleIdentifier ?? ""
        let appName = front?.localizedName ?? "this app"
        let on = s.p.enabled && !c.pausedGlobally
        statusItem.button?.title = on ? "¶" : "¶·"
        func item(_ t: String, _ sel: Selector?, _ key: String = "") -> NSMenuItem {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: key); i.target = self
            i.attributedTitle = NSAttributedString(string: t, attributes: [.font: CWT.font(13)]); return i
        }
        menu.addItem(item("OMNIKEYS \(on ? "ON" : "OFF") · \(Engine.shared.statusText)", nil))
        menu.addItem(item(on ? "Pause completions" : "Resume completions", #selector(togglePause)))
        let rule = s.p.apps.first(where: { $0.id == bundle })
        let appOn = rule?.enabled ?? true
        let a = item("\(appOn ? "Disable" : "Enable") in \(appName)", #selector(toggleApp)); a.representedObject = [bundle, appName]; menu.addItem(a)
        if s.p.recording {
            let r = item("Recording in \(appName): \(rule?.recording ?? true ? "ON" : "OFF")", #selector(toggleRecording)); r.representedObject = [bundle, appName]; menu.addItem(r)
        }
        menu.addItem(.separator())
        if !c.accessibilityTrusted { menu.addItem(item("Grant Accessibility permission…", #selector(openAccessibility))) }
        if IsSecureEventInputEnabled() { menu.addItem(item("Secure input is on: another app blocks single-key shortcuts", nil)) }
        menu.addItem(item("Settings…", #selector(showSettings), ","))
        menu.addItem(item("Words completed today: \(s.p.wordsToday)", nil))
        menu.addItem(.separator())
        menu.addItem(item("Version \(s.version)", nil))
        menu.addItem(item("Quit Omnikeys", #selector(NSApplication.terminate(_:)), "q"))
    }
    @objc func togglePause() { controller.pausedGlobally.toggle(); controller.hideAll() }
    @objc func toggleApp(_ sender: NSMenuItem) {
        guard let a = sender.representedObject as? [String], !a[0].isEmpty else { return }
        var r = Settings.shared.rule(for: a[0], name: a[1]); r.enabled.toggle(); Settings.shared.update(r); controller.hideAll()
    }
    @objc func toggleRecording(_ sender: NSMenuItem) {
        guard let a = sender.representedObject as? [String], !a[0].isEmpty else { return }
        var r = Settings.shared.rule(for: a[0], name: a[1]); r.recording.toggle(); Settings.shared.update(r)
    }
    @objc func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Omnikeys"
            w.appearance = NSAppearance(named: .aqua)
            w.contentView = NSHostingView(rootView: SettingsRoot(s: Settings.shared, c: controller))
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ n: Notification) { controller.flushRecording() }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
