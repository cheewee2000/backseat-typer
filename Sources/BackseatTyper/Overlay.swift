import AppKit

enum CWT {
    static let gray = NSColor(srgbRed: 0xdc/255, green: 0xdc/255, blue: 0xdc/255, alpha: 1)
    static func font(_ size: CGFloat) -> NSFont {
        NSFont(name: "SpaceMono-Regular", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

/// A click-through panel that follows the caret. One for ghost text, one for numbered lists.
final class OverlayPanel {
    let panel: NSPanel
    let label = NSTextField(labelWithString: "")
    init(bordered: Bool) {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .aqua)   // ghost colours come from the field itself, never from the system theme
        let v = NSView()
        v.wantsLayer = true
        if bordered { v.layer?.backgroundColor = NSColor.white.cgColor; v.layer?.borderColor = NSColor.black.cgColor; v.layer?.borderWidth = 1 }
        label.textColor = .black
        label.backgroundColor = .clear
        label.isBezeled = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byClipping
        v.addSubview(label)
        panel.contentView = v
    }
    func show(_ text: String, font: NSFont, color: NSColor, origin: CGPoint, lineHeight: CGFloat? = nil, rtl: Bool = false) {
        label.font = font
        label.textColor = color
        // A halo of the opposite luminance keeps the ghost legible when the background guess is wrong
        // (dark terminals, dark web pages, empty fields with no text colour of their own).
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let lum = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        // Mid grey (the no-colour fallback) reads on either background and a halo would only smear it.
        let halo = NSShadow(); halo.shadowColor = (lum > 0.5 ? NSColor.black : NSColor.white).withAlphaComponent(0.85); halo.shadowBlurRadius = 2; halo.shadowOffset = .zero
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if abs(lum - 0.5) > 0.2 { attrs[.shadow] = halo }
        label.attributedStringValue = NSAttributedString(string: text, attributes: attrs)
        label.baseWritingDirection = rtl ? .rightToLeft : .natural
        label.alignment = rtl ? .right : .left
        label.sizeToFit()
        let padX: CGFloat = 4, padY: CGFloat = 1
        let h = max(label.frame.height + padY * 2, lineHeight ?? 0)
        let w = label.frame.width + padX * 2
        label.frame.origin = CGPoint(x: padX, y: (h - label.frame.height) / 2)
        var frame = CGRect(x: rtl ? origin.x - w : origin.x, y: origin.y - (h - (lineHeight ?? h)) / 2, width: w, height: h)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: origin.x, y: origin.y + 1)) }) ?? NSScreen.main {
            let vis = screen.visibleFrame
            if frame.maxX > vis.maxX { frame.origin.x = vis.maxX - w }
            if frame.minX < vis.minX { frame.origin.x = vis.minX }
            if frame.minY < vis.minY { frame.origin.y = vis.minY }
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil) }
    var isVisible: Bool { panel.isVisible }
}
