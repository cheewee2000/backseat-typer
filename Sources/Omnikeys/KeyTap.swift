import AppKit

final class KeyTap {
    static let magic: Int64 = 0x4F4D4E49  // "OMNI": marks our own synthetic events
    var onKey: ((CGEvent, UInt16, CGEventFlags) -> Bool)?   // true = swallow
    var onMouse: (() -> Void)?
    private var tap: CFMachPort?
    private lazy var source: CGEventSource? = {
        let s = CGEventSource(stateID: .combinedSessionState); s?.userData = KeyTap.magic; return s
    }()

    func start() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.scrollWheel.rawValue)
        let cb: CGEventTapCallBack = { _, type, event, info in
            let me = Unmanaged<KeyTap>.fromOpaque(info!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if event.getIntegerValueField(.eventSourceUserData) == KeyTap.magic { return Unmanaged.passUnretained(event) }
            if type == .keyDown {
                let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                if me.onKey?(event, code, event.flags) == true { return nil }
            } else { me.onMouse?() }
            return Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: cb, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func type(_ text: String) {
        var chunk: [UniChar] = []
        func flush() {
            guard !chunk.isEmpty else { return }
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                e?.post(tap: .cghidEventTap)
            }
            chunk.removeAll()
        }
        for ch in text { chunk += Array(String(ch).utf16); if chunk.count >= 10 { flush() } }
        flush()
    }
    func press(_ code: UInt16, flags: CGEventFlags = [], times: Int = 1) {
        for _ in 0..<times {
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
                e?.flags = flags
                e?.post(tap: .cghidEventTap)
            }
        }
    }
    func backspace(_ n: Int) { press(51, times: n) }

    // Test driver only (app launched with --e2e): unmarked events the tap treats as real user input.
    private lazy var userSource = CGEventSource(stateID: .combinedSessionState)
    func simulate(text: String) {
        DispatchQueue.global().async {
            for ch in text {
                var u = Array(String(ch).utf16)
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: self.userSource, virtualKey: 0, keyDown: down)
                    e?.keyboardSetUnicodeString(stringLength: u.count, unicodeString: &u)
                    e?.post(tap: .cghidEventTap)
                }
                usleep(15_000)
            }
        }
    }
    func simulate(key code: UInt16, flags: CGEventFlags = []) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: userSource, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }
    func char(of event: CGEvent) -> String {
        var len = 0; var buf = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &len, unicodeString: &buf)
        return String(utf16CodeUnits: buf, count: len)
    }
}
