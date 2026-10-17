import SwiftUI
import Carbon.HIToolbox

// CW&T design system: Space Mono 400 only, all text #000000, zero radius, 2px input borders, one button style.
extension Font {
    static func mono(_ size: CGFloat) -> Font { .custom("SpaceMono-Regular", size: size) }
}
struct CWTButton: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.mono(12)).textCase(.uppercase).tracking(0.5)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(hover ? Color.black : Color.white)
            .background(hover ? Color.white : Color.black)
            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            .onHover { hover = $0 }
    }
}
struct CWTToggle: ToggleStyle {
    func makeBody(configuration c: Configuration) -> some View {
        Button { c.isOn.toggle() } label: {
            HStack(spacing: 10) {
                Rectangle().fill(c.isOn ? Color.black : Color.white).frame(width: 14, height: 14).overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                c.label.font(.mono(14)).foregroundStyle(.black)
                Spacer(minLength: 0)
            }
        }.buttonStyle(.plain)
    }
}
struct Field: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.mono(14)).textFieldStyle(.plain).padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.white).overlay(Rectangle().stroke(Color.black, lineWidth: 2))
    }
}
struct Segments<T: Hashable>: View {
    @Binding var value: T
    let options: [(T, String)]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { o in
                Button { value = o.0 } label: {
                    Text(o.1).font(.mono(12)).textCase(.uppercase).tracking(0.5).padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(value == o.0 ? Color.white : Color.black)
                        .background(value == o.0 ? Color.black : Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
    }
}
struct Row<Content: View>: View {
    let label: String; let content: Content
    init(_ label: String, @ViewBuilder _ c: () -> Content) { self.label = label; content = c() }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).font(.mono(14)).frame(width: 260, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}
struct H: View { let t: String; init(_ t: String) { self.t = t }
    var body: some View { Text(t).font(.mono(12)).textCase(.uppercase).tracking(0.6).padding(.top, 18).padding(.bottom, 2) }
}
struct Rule: View { var body: some View { Rectangle().fill(Color(red: 0xdc/255, green: 0xdc/255, blue: 0xdc/255)).frame(height: 1) } }

struct ShortcutRecorder: View {
    let title: String
    @Binding var shortcut: Shortcut?
    @Bindable var c: Controller
    @State private var recording = false
    var body: some View {
        Row(title) {
            Button(recording ? "PRESS KEYS…" : (shortcut?.label ?? "UNASSIGNED")) {
                recording = true
                c.recorder = { s in shortcut = s; recording = false }
            }.buttonStyle(CWTButton())
            if shortcut != nil { Button("clear") { shortcut = nil; c.recorder = nil; recording = false }.buttonStyle(.plain).font(.mono(12)).textCase(.uppercase) }
        }
    }
}

struct SettingsRoot: View {
    @Bindable var s: Settings
    @Bindable var c: Controller
    @State var tab = "general"
    @State private var selectedApp: String?
    @State private var newDomain = ""
    @State private var confirmDelete = false
    let tabs = ["general", "shortcuts", "apps", "personalization", "vault", "labs", "about"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("OMNIKEYS").font(.mono(14)).tracking(0.6).foregroundStyle(.white).padding(.horizontal, 20)
                ForEach(tabs, id: \.self) { t in
                    Button { tab = t } label: {
                        Text(t).font(.mono(14)).textCase(.uppercase).foregroundStyle(tab == t ? .black : .white)
                            .padding(.horizontal, 14).frame(height: 45).background(tab == t ? Color.white : Color.black)
                    }.buttonStyle(.plain)
                }
                Spacer()
            }.frame(height: 45).background(Color.black)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case "general": general
                    case "shortcuts": shortcuts
                    case "apps": apps
                    case "personalization": personalization
                    case "vault": VaultView(s: s)
                    case "labs": labs
                    default: about
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }.background(Color.white).foregroundStyle(.black).tint(.black)
        .onDisappear { c.recorder = nil }
    }

    var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CWT_STENGW9_2609").font(.mono(14)).tracking(0.84).textCase(.uppercase)
                Text("(S)oft (T)iny (E)lectrons (N)/a di(G)ital (W)rite (9)infinity · 2609 = date").font(.mono(12))
            }
            Spacer()
            Text("v\(s.version)").font(.mono(12))
        }.padding(.horizontal, 24).padding(.vertical, 14).background(Color(red: 0xdc/255, green: 0xdc/255, blue: 0xdc/255))
    }

    var general: some View {
        Group {
            Toggle("Completions on", isOn: $s.p.enabled).toggleStyle(CWTToggle())
            H("Suggestions")
            Row("Completion length") { Segments(value: $s.p.completionLength, options: [(.short, "short"), (.medium, "medium"), (.long, "long")]) }
            Row("Suggest after a pause of (ms)") { TextField("", value: $s.p.debounceMs, format: .number).modifier(Field()).frame(width: 100) }
            Row("Minimum context (characters)") { TextField("", value: $s.p.minContextChars, format: .number).modifier(Field()).frame(width: 100) }
            Toggle("Mid-line completion (suggest with text after the cursor)", isOn: $s.p.midLine).toggleStyle(CWTToggle())
            Toggle("Form fill (an empty field whose label matches your vault shows the answer; Tab fills it)", isOn: $s.p.formFill).toggleStyle(CWTToggle())
            Toggle("Include sensitive fields (ID numbers, medical lists) when filling a whole form", isOn: $s.p.fillSensitive).toggleStyle(CWTToggle())
            Toggle("Screen context (read the rest of the window and the windows beside it, via Accessibility)", isOn: $s.p.screenContext).toggleStyle(CWTToggle())
            Toggle("Clipboard awareness (the clipboard informs suggestions)", isOn: $s.p.clipboardAwareness).toggleStyle(CWTToggle())
            Toggle("Emoji suggestions (type : then a shortcode)", isOn: $s.p.emojiSuggestions).toggleStyle(CWTToggle())
            Toggle("Full autocorrect (Tab applies the typo fix)", isOn: $s.p.fullAutocorrect).toggleStyle(CWTToggle())
            Toggle("Trailing space after single-word completions", isOn: $s.p.trailingSpaceAfterWord).toggleStyle(CWTToggle())
            H("Where")
            Toggle("Complete in code editors (VS Code, Cursor, Windsurf)", isOn: $s.p.completeInCodeEditors).toggleStyle(CWTToggle())
            Toggle("Complete in terminals for regular shell typing (AI agent prompts always work)", isOn: $s.p.completeInTerminals).toggleStyle(CWTToggle())
            Toggle("Launch at login", isOn: Binding(get: { s.launchAtLogin }, set: { s.launchAtLogin = $0 })).toggleStyle(CWTToggle())
            H("Model")
            Row("Model") { Segments(value: $s.p.model, options: Models.options) }
            Row("Status") { Text(Engine.shared.statusText).font(.mono(14)) }
            Text("Apple is the Apple Intelligence model built into macOS. Gemma 4 (Cotypist\u{2019}s default) and Qwen are open-weight models, downloaded once from Hugging Face on first use (1 to 3 GB) and run on-device by MLX. Nothing you type leaves this Mac.").font(.mono(12)).frame(maxWidth: 560, alignment: .leading)
        }
    }

    var shortcuts: some View {
        Group {
            ShortcutRecorder(title: "Complete the next word", shortcut: $s.p.nextWord, c: c)
            ShortcutRecorder(title: "Accept the full completion", shortcut: $s.p.acceptAll, c: c)
            ShortcutRecorder(title: "Dismiss suggestion", shortcut: $s.p.dismiss, c: c)
            ShortcutRecorder(title: "Fill every empty field in this window from the vault", shortcut: $s.p.fillForm, c: c)
            ShortcutRecorder(title: "Force-activate completions here", shortcut: $s.p.forceActivate, c: c)
            ShortcutRecorder(title: "Temporarily toggle in current app", shortcut: $s.p.toggleApp, c: c)
            ShortcutRecorder(title: "Toggle completions globally", shortcut: $s.p.toggleGlobal, c: c)
            H("Tab")
            Toggle("Tab accepts the next word (Option+Tab always sends a plain Tab)", isOn: $s.p.tabEnabled).toggleStyle(CWTToggle())
            H("Esc")
            Row("When Esc dismisses a suggestion") {
                Segments(value: $s.p.escBehavior, options: [(.pauseBriefly, "pause briefly"), (.offUntilAppSwitch, "off until app switch"), (.passThrough, "pass through")])
            }
            Text("Click a key field and press the keys you want. The physical key counts, not its label.").font(.mono(12))
        }
    }

    var apps: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(s.p.apps) { a in
                    Button { selectedApp = a.id } label: {
                        HStack { Text(a.name).font(.mono(14)); Spacer(); Text(a.enabled ? "" : "OFF").font(.mono(12)) }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(selectedApp == a.id ? .white : .black)
                            .background(selectedApp == a.id ? Color.black : Color.white)
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 8) {
                    TextField("domain or bundle id", text: $newDomain).modifier(Field())
                    Button("add") {
                        let d = newDomain.trimmingCharacters(in: .whitespaces)
                        if !d.isEmpty { s.update(AppRule(id: d, name: d)); selectedApp = d; newDomain = "" }
                    }.buttonStyle(CWTButton())
                }.padding(.top, 12)
                Text("Apps appear here the first time you type in them.").font(.mono(12)).padding(.top, 8)
            }.frame(width: 300)
            if let id = selectedApp, let i = s.p.apps.firstIndex(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(s.p.apps[i].name).font(.mono(18))
                    Text(id).font(.mono(12))
                    Toggle("Enabled", isOn: $s.p.apps[i].enabled).toggleStyle(CWTToggle())
                    Toggle("Tab accepts here", isOn: $s.p.apps[i].tabEnabled).toggleStyle(CWTToggle())
                    Toggle("Record my writing here", isOn: $s.p.apps[i].recording).toggleStyle(CWTToggle())
                    Toggle("Improve compatibility with this app", isOn: $s.p.apps[i].improveCompatibility).toggleStyle(CWTToggle())
                    H("Custom instructions for this app")
                    TextEditor(text: $s.p.apps[i].instructions).font(.mono(14)).frame(height: 110).scrollContentBackground(.hidden).modifier(Field())
                    Text("Appended after your global instructions when you type here. Example: terse and casual, no greetings.").font(.mono(12))
                    Text("Recorded texts: \(History.shared.count(for: id))").font(.mono(12))
                    Button("remove") { s.p.apps.remove(at: i); selectedApp = nil }.buttonStyle(.plain).font(.mono(12)).textCase(.uppercase)
                }
            } else { Text("Select an app.").font(.mono(14)) }
        }
    }

    var personalization: some View {
        Group {
            Toggle("Record your writing for personalization", isOn: $s.p.recording).toggleStyle(CWTToggle())
            Toggle("Record text even when you accept no suggestion", isOn: $s.p.recordAll).toggleStyle(CWTToggle())
            Text("Recorded text stays on this Mac, in ~/Library/Application Support/Omnikeys. Texts under 80 characters are skipped.").font(.mono(12))
            H("Personalize word choice")
            Segments(value: $s.p.personalization, options: [(0, "off"), (1, "1"), (2, "2"), (3, "3"), (4, "4"), (5, "max")])
            Text("How strongly your typing history steers suggestions. Only has an effect once some history exists. Start around 3.").font(.mono(12))
            H("Custom AI instructions")
            TextEditor(text: $s.p.customInstructions).font(.mono(14)).frame(height: 110).scrollContentBackground(.hidden).modifier(Field()).frame(maxWidth: 620)
            HStack {
                Text("A few sentences about you, the writing you do, and your style. Longer dilutes it.").font(.mono(12))
                Spacer()
                Button("reset to default") { s.p.customInstructions = Prefs.defaultInstructions() }.buttonStyle(.plain).font(.mono(12)).textCase(.uppercase)
            }.frame(maxWidth: 620)
            H("Existing data")
            HStack(spacing: 16) {
                Text("\(History.shared.samples.count) recorded texts").font(.mono(14))
                if confirmDelete {
                    Button("yes, delete everything") { History.shared.deleteAll(); confirmDelete = false }.buttonStyle(CWTButton())
                    Button("cancel") { confirmDelete = false }.buttonStyle(.plain).font(.mono(12)).textCase(.uppercase)
                } else { Button("delete all…") { confirmDelete = true }.buttonStyle(CWTButton()) }
            }
        }
    }

    var labs: some View {
        Group {
            Text("Experimental features. They may change or go away.").font(.mono(12))
            H("Word alternatives")
            Toggle("Show a numbered list of other words the model considered; press the number to insert", isOn: $s.p.wordAlternatives).toggleStyle(CWTToggle())
            Row("Show them") { Segments(value: $s.p.altTrigger, options: [(.pause, "after a short pause"), (.shortcut, "only on shortcut")]) }
            ShortcutRecorder(title: "Reveal alternatives", shortcut: $s.p.revealAlternatives, c: c)
            H("Synonyms for selected words")
            Toggle("Select a word and get synonyms that fit the sentence; press the number to replace", isOn: $s.p.synonyms).toggleStyle(CWTToggle())
            Row("Show them") { Segments(value: $s.p.synTrigger, options: [(.afterSelection, "after selecting"), (.shortcut, "only on shortcut")]) }
            Row("Wait after selecting (ms)") { TextField("", value: $s.p.synDelayMs, format: .number).modifier(Field()).frame(width: 100) }
            ShortcutRecorder(title: "Show synonyms now", shortcut: $s.p.showSynonyms, c: c)
            H("Language")
            Toggle("British English", isOn: $s.p.britishEnglish).toggleStyle(CWTToggle())
            Toggle("Right-to-left support (Arabic, Hebrew)", isOn: $s.p.rtl).toggleStyle(CWTToggle())
            H("Sync between your Macs")
            Text("NOT AVAILABLE · settings live in this Mac's defaults").font(.mono(12))
        }
    }

    var about: some View {
        Group {
            Text("Omnikeys").font(.mono(30))
            Text("Predictive text for every Mac text field. Private and on-device: your words never leave this Mac. macOS blocks reading password fields.").font(.mono(14)).frame(maxWidth: 600, alignment: .leading)
            H("Permissions")
            Row("Accessibility") {
                Text(c.accessibilityTrusted ? "GRANTED" : "REQUIRED").font(.mono(14))
                if !c.accessibilityTrusted { Button("open system settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }.buttonStyle(CWTButton()) }
            }
            Row("Event tap") { Text(c.tapRunning ? "RUNNING" : "WAITING FOR PERMISSION").font(.mono(14)) }
            Row("Secure input") { Text(IsSecureEventInputEnabled() ? "ON · another app blocks single-key shortcuts" : "OFF").font(.mono(14)) }
            H("Stats")
            Row("Words completed today") { Text("\(s.p.wordsToday)").font(.mono(14)) }
            Row("Words completed total") { Text("\(s.p.wordsTotal)").font(.mono(14)) }
            H("Log")
            Text(Log.url.path).font(.mono(12))
            Rule()
            Text("Version \(s.version) · CW&T").font(.mono(12))
        }
    }
}


/// The vault tab: one profile per person, Form Filler's schema, import of its encrypted backups.
struct VaultView: View {
    @Bindable var s: Settings
    @Bindable var v = Vault.shared
    @State private var newField = ""
    @State private var status = ""
    var profile: Profile? { v.data.profile(s.p.fillProfile) }
    var body: some View {
        Group {
            H("Profile used for filling")
            HStack(spacing: 8) {
                Segments(value: $s.p.fillProfile, options: v.data.profiles.map { ($0.id, $0.name) })
                Button("add person") {
                    let id = "P\(v.data.nextP)"; v.data.nextP += 1
                    v.data.profiles.append(Profile(id: id, name: "Person \(v.data.profiles.count + 1)")); s.p.fillProfile = id; v.save()
                }.buttonStyle(CWTButton())
            }
            if let pr = profile {
                Row("Name of this profile") { TextField("", text: Binding(get: { pr.name }, set: { n in if let i = v.data.profiles.firstIndex(where: { $0.id == pr.id }) { v.data.profiles[i].name = n; v.save() } })).modifier(Field()).frame(width: 260) }
                ForEach(v.data.groups, id: \.self) { g in
                    H(g)
                    ForEach(v.data.allFields.filter { $0.group == g }) { f in
                        Row(f.label + (f.sensitive ? " ·" : "")) {
                            TextField(f.kind == .date ? "YYYY-MM-DD" : "", text: Binding(get: { v.data.value(pr.id, f.key) }, set: { v.data.setValue(pr.id, f.key, $0); v.save() }))
                                .modifier(Field()).frame(width: f.kind == .list ? 460 : 300)
                        }
                    }
                }
                H("Custom field")
                HStack(spacing: 8) {
                    TextField("Label, e.g. Frequent flyer number", text: $newField).modifier(Field()).frame(width: 300)
                    Button("add") { guard !newField.isEmpty else { return }; _ = v.data.addCustomField(label: newField, kind: .text, sensitive: false); newField = ""; v.save() }.buttonStyle(CWTButton())
                }
            }
            H("Backup")
            HStack(spacing: 8) {
                Button("import form filler backup…") { importBackup() }.buttonStyle(CWTButton())
                Button("export backup…") { exportBackup() }.buttonStyle(CWTButton())
                Button("erase vault") { v.erase(); status = "Vault erased." }.buttonStyle(CWTButton())
            }
            Text("Same encrypted file as the iPhone and web versions of Form Filler. Everything here is AES-256-GCM encrypted at rest with a key in this Mac's keychain, and never leaves this Mac. Fields marked · are sensitive: shown masked in the ghost text, skipped by whole-form fill unless enabled in General.").font(.mono(12)).frame(maxWidth: 560, alignment: .leading)
            if !status.isEmpty { Text(status).font(.mono(12)) }
            if let e = v.loadError { Text(e).font(.mono(12)) }
        }
    }
    func importBackup() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]; p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let url = p.url, let pass = askPassphrase("Passphrase for this backup") else { return }
        do { try v.importBackup(url: url, passphrase: pass); status = "Imported \(v.data.profiles.count) profile(s)." } catch { status = error.localizedDescription }
    }
    func exportBackup() {
        guard let pass = askPassphrase("Choose a passphrase for the backup") else { return }
        let p = NSSavePanel(); p.nameFieldStringValue = "omnikeys-vault-backup.json"
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try Backup.export(v.data, passphrase: pass).write(to: url); status = "Backup written." } catch { status = error.localizedDescription }
    }
    func askPassphrase(_ title: String) -> String? {
        let a = NSAlert(); a.messageText = title
        let f = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24)); a.accessoryView = f
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn && !f.stringValue.isEmpty ? f.stringValue : nil
    }
}
