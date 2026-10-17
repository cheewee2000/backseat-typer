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

    func applicationDidFinishLaunching(_ n: Notification) {
        Log.w("launch v\(Settings.shared.version) model=\(Engine.shared.statusText) ax=\(AXIsProcessTrusted())")
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
