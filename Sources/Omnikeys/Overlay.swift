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
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = CWT.gray.cgColor
        if bordered { v.layer?.borderColor = NSColor.black.cgColor; v.layer?.borderWidth = 1 }
        label.textColor = .black
        label.backgroundColor = .clear
        label.isBezeled = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byClipping
        v.addSubview(label)
        panel.contentView = v
    }
    func show(_ text: String, fontSize: CGFloat, origin: CGPoint, lineHeight: CGFloat? = nil, rtl: Bool = false) {
        label.font = CWT.font(fontSize)
        label.stringValue = text
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
