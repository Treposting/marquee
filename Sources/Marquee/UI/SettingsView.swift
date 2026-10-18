import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsView: View {
    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Settings", subtitle: "Captures, recording, Measure, clipboard and shortcuts")
            TabView {
                CaptureSettings().tabItem { Label("Capture", systemImage: "camera.viewfinder") }
                RecordingSettings().tabItem { Label("Recording", systemImage: "record.circle") }
                MeasureSettings().tabItem { Label("Measure", systemImage: "ruler") }
                ClipboardSettings().tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
                ShortcutsSettings().tabItem { Label("Shortcuts", systemImage: "keyboard") }
            }
            .padding(.horizontal, Page.gutter - 8)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
    }
}

@MainActor
private struct CaptureSettings: View {
    @AppStorage(Preferences.Key.showOverlay.rawValue) private var showOverlay = true
    @AppStorage(Preferences.Key.copyAfterCapture.rawValue) private var copyAfterCapture = true
    @AppStorage(Preferences.Key.saveAfterCapture.rawValue) private var saveAfterCapture = false
    @AppStorage(Preferences.Key.playSound.rawValue) private var playSound = true
    @AppStorage(Preferences.Key.copyPasteSound.rawValue) private var copyPasteSound = true
    @AppStorage(Preferences.Key.windowShadow.rawValue) private var windowShadow = true
    @AppStorage(Preferences.Key.overlayTimeout.rawValue) private var overlayTimeout = 0
    @AppStorage(Preferences.Key.saveFolder.rawValue) private var saveFolder = Preferences.defaultSaveFolder.path

    var body: some View {
        Form {
            Section("After capture") {
                Toggle("Show Quick Access overlay", isOn: $showOverlay)
                Picker("Hide overlay after", selection: $overlayTimeout) {
                    Text("Never").tag(0)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                }
                .disabled(!showOverlay)
                Toggle("Copy to clipboard", isOn: $copyAfterCapture)
                Toggle("Save to folder", isOn: $saveAfterCapture)
            }
            Section("General") {
                Toggle("Play shutter sound", isOn: $playSound)
                Toggle("Play sound on copy and paste", isOn: $copyPasteSound)
                Toggle("Include window shadow", isOn: $windowShadow)
                HStack {
                    Text("Save to")
                    Spacer()
                    Text((saveFolder as NSString).abbreviatingWithTildeInPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…", action: chooseFolder)
                }
                LaunchAtLoginToggle()
            }
            MenuBarIconSection()
            UpdatesSection()
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: saveFolder)
        if panel.runModal() == .OK, let url = panel.url {
            saveFolder = url.path
        }
    }
}

@MainActor
struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("Marquee: launch at login failed: \(error)")
                }
                enabled = SMAppService.mainApp.status == .enabled
            }
        ))
    }
}

@MainActor
private struct ClipboardSettings: View {
    @AppStorage(Preferences.Key.historyLimit.rawValue) private var historyLimit = 500
    @AppStorage(Preferences.Key.autoPaste.rawValue) private var autoPaste = true
    @AppStorage(Preferences.Key.monitorPaused.rawValue) private var paused = false
    @AppStorage(Preferences.Key.linkPreviews.rawValue) private var linkPreviews = true
    @State private var trusted = Paster.isTrusted
    @State private var access = PasteboardAccess.status

    var body: some View {
        Form {
            if access != .allowed {
                Section("Clipboard access") {
                    Label {
                        Text(access == .asks
                             ? "macOS asks before Marquee reads the clipboard, so copies may not be recorded."
                             : "macOS may block Marquee from reading the clipboard, so copies may not be recorded.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Text("In System Settings → Privacy & Security, find the clipboard (Paste) setting and choose Always Allow for Marquee.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Privacy & Security") { PasteboardAccess.openPrivacySettings() }
                }
            }
            Section("History") {
                Toggle("Record clipboard history", isOn: Binding(get: { !paused }, set: { paused = !$0 }))
                Picker("Keep", selection: $historyLimit) {
                    Text("100 items").tag(100)
                    Text("500 items").tag(500)
                    Text("1,000 items").tag(1000)
                    Text("5,000 items").tag(5000)
                }
                Text("Pinned items are never removed. Items marked as concealed by password managers are never recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            IgnoredAppsSection()
            Section("Links") {
                Toggle("Show link previews", isOn: $linkPreviews)
                Text("Shows the page's title and image for copied links. Marquee loads them from the website when the link appears in your history. Links to your own network (like 192.168.x.x or .local) are never loaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Pasting") {
                Toggle("Paste directly into the active app", isOn: $autoPaste)
                HStack {
                    Text(trusted ? "Accessibility access granted" : "Needs Accessibility access")
                        .foregroundStyle(trusted ? Color.secondary : Color.orange)
                    Spacer()
                    if !trusted {
                        Button("Grant…") {
                            Paster.requestAccess()
                            trusted = Paster.isTrusted
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            trusted = Paster.isTrusted
            access = PasteboardAccess.status
        }
    }
}

/// Pick the menu-bar icon: a built-in symbol or an image of your own.
@MainActor
private struct MenuBarIconSection: View {
    @AppStorage(Preferences.Key.menuBarIcon.rawValue) private var choice = MenuBarIcon.defaultSymbol
    @AppStorage(Preferences.Key.menuBarIconTemplate.rawValue) private var template = true
    @State private var customImage = MenuBarIcon.customImage()
    @State private var loadFailed = false

    private let columns = [GridItem(.adaptive(minimum: 38, maximum: 44), spacing: 8)]

    var body: some View {
        Section("Menu bar icon") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(MenuBarIcon.presets) { preset in
                    tile(selected: choice == preset.symbol, help: preset.title) {
                        MenuBarIcon.select(preset.symbol)
                    } content: {
                        Image(systemName: preset.symbol).font(.system(size: 15))
                    }
                }
                if let customImage {
                    tile(selected: choice == MenuBarIcon.customChoice, help: "Your image") {
                        MenuBarIcon.select(MenuBarIcon.customChoice)
                    } content: {
                        Image(nsImage: customImage)
                            .renderingMode(template ? .template : .original)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 30, maxHeight: 16)
                    }
                }
            }
            .padding(.vertical, 2)
            HStack {
                Text(loadFailed ? "That file couldn't be read as an image." : "Or use your own image.")
                    .foregroundStyle(loadFailed ? Color.orange : Color.secondary)
                Spacer()
                Button("Choose Image…", action: chooseImage)
            }
            if customImage != nil {
                Toggle("Match the menu bar's color", isOn: Binding(
                    get: { template },
                    set: { newValue in
                        template = newValue
                        customImage = MenuBarIcon.customImage()
                        MenuBarIcon.select(choice)
                    }
                ))
                Text("Best for a simple shape on a transparent background. Turn it off to keep the image's own colors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tile(selected: Bool, help: String, action: @escaping @MainActor () -> Void,
                      @ViewBuilder content: () -> some View) -> some View {
        Button(action: action) {
            content()
                .frame(width: 38, height: 30)
                .contentShape(Rectangle())
                .background(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image for the menu bar. It's shown 18 points tall."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFailed = !MenuBarIcon.useCustomImage(from: url)
        customImage = MenuBarIcon.customImage()
    }
}

@MainActor
private struct UpdatesSection: View {
    @AppStorage(Preferences.Key.autoCheckUpdates.rawValue) private var autoCheck = true
    @AppStorage(Preferences.Key.notifyUpdates.rawValue) private var notify = true
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $autoCheck)
            Toggle("Notify me when an update is available", isOn: $notify)
                .disabled(!autoCheck)
            Text("Marquee looks for a new version every hour. When there is one, the menu bar icon gets a red dot.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text("Version \(updater.currentVersion)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(updater.isReadyToInstall ? "Restart to Update" : "Check Now") {
                    if updater.isReadyToInstall {
                        updater.restartToUpdate()
                    } else {
                        updater.check(userInitiated: true)
                    }
                }
            }
        }
    }
}

@MainActor
private struct MeasureSettings: View {
    @AppStorage(Preferences.Key.measureTolerance.rawValue) private var tolerance = 12

    private struct KeyRow: Identifiable {
        let action: String
        let keys: String
        var id: String { action }
    }

    private let keys: [KeyRow] = [
        KeyRow(action: "Distances to the nearest edges", keys: "Move the pointer"),
        KeyRow(action: "Snap to an element", keys: "Drag around it"),
        KeyRow(action: "Add a horizontal or vertical guide", keys: "H / V"),
        KeyRow(action: "Move a guide", keys: "Drag it"),
        KeyRow(action: "Nudge the selected guide", keys: "Arrow keys (⇧: 10 pt)"),
        KeyRow(action: "Select the next guide", keys: "Tab"),
        KeyRow(action: "Keep a measurement on screen", keys: "Space"),
        KeyRow(action: "Remove the guide, or clear kept measurements", keys: "⌫"),
        KeyRow(action: "Show pixels instead of points", keys: "Hold ⇧"),
        KeyRow(action: "Copy the last measurement", keys: "⌘C"),
        KeyRow(action: "Capture the screen with measurements", keys: "⌘S"),
        KeyRow(action: "Stop measuring", keys: "Esc"),
    ]

    var body: some View {
        Form {
            Section("Edge detection") {
                Slider(value: Binding(get: { Double(tolerance) }, set: { tolerance = Int($0.rounded()) }),
                       in: 0...48, step: 1) {
                    Text("Tolerance")
                }
                Text("\(tolerance). Raise it to ignore soft shadows and smoothed edges; lower it to stop at the faintest line.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("While measuring") {
                ForEach(keys) { row in
                    HStack {
                        Text(row.action)
                        Spacer()
                        Text(row.keys).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Measure needs macOS 14 Sonoma or later.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

@MainActor
private struct RecordingSettings: View {
    @AppStorage(Preferences.Key.recordFPS.rawValue) private var fps = 30
    @AppStorage(Preferences.Key.recordResolution.rawValue) private var resolution = RecordResolution.original.rawValue
    @AppStorage(Preferences.Key.recordShowCursor.rawValue) private var showCursor = true
    @AppStorage(Preferences.Key.recordAudio.rawValue) private var desktopAudio = false
    @AppStorage(Preferences.Key.recordMicrophone.rawValue) private var micEnabled = false
    @AppStorage(Preferences.Key.recordMicrophoneID.rawValue) private var micID = ""
    @AppStorage(Preferences.Key.recordCountdownSeconds.rawValue) private var countdown = 3
    @AppStorage(Preferences.Key.recordVoiceSeparately.rawValue) private var separateVoice = false
    @State private var devices: [MicrophoneCapture.Device] = []

    /// "" = off, "default" = system default input, otherwise a device ID.
    private var micSelection: Binding<String> {
        Binding(
            get: { micEnabled ? (micID.isEmpty ? "default" : micID) : "" },
            set: { value in
                micEnabled = !value.isEmpty
                micID = value == "default" ? "" : value
            }
        )
    }

    var body: some View {
        Form {
            Section("Audio") {
                Picker("Microphone", selection: micSelection) {
                    Text("None").tag("")
                    Text("System default").tag("default")
                    if !devices.isEmpty { Divider() }
                    ForEach(devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                Toggle("Record desktop audio", isOn: $desktopAudio)
                Toggle("Also save my voice as a separate file", isOn: $separateVoice)
                Text("Desktop audio is what your Mac plays: videos, calls, music. When both are on, they're mixed into one soundtrack. Your voice can also be saved on its own for editing: the video and the voice (.m4a) go into one folder in your screenshots folder, named alike. You can change all of this on the recording toolbar too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            CameraSettingsSection()
            Section("Start") {
                Picker("Start recording", selection: $countdown) {
                    Text("Instantly").tag(0)
                    Text("After 3 seconds").tag(3)
                    Text("After 5 seconds").tag(5)
                    Text("After 10 seconds").tag(10)
                }
                Text(countdown == 0
                     ? "Recording starts as soon as you press Record."
                     : "Counts down from \(countdown), shows Go, then starts recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Video") {
                Picker("Resolution", selection: $resolution) {
                    ForEach(RecordResolution.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Text(resolution == RecordResolution.original.rawValue
                     ? "Recordings keep your display's full sharpness (Retina is twice the size in points)."
                     : "Recordings are scaled down to fit \(RecordResolution(rawValue: resolution)?.title ?? ""). Smaller files, still sharp for sharing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Frame rate", selection: $fps) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                Toggle("Show mouse cursor", isOn: $showCursor)
            }
            Text("Recordings are saved as H.264 MP4. Use \u{201C}Save as GIF\u{201D} in the overlay to export a GIF. Stop from the toolbar, the menu bar, or by pressing the record shortcut again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { devices = MicrophoneCapture.devices() }
    }
}

@MainActor
private struct ShortcutsSettings: View {
    var body: some View {
        Form {
            ForEach(ShortcutAction.Category.allCases) { category in
                Section(category.rawValue) {
                    ForEach(category.actions) { action in
                        HStack(spacing: 10) {
                            Image(systemName: action.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(action.title)
                            Spacer()
                            ShortcutRecorder(action: action)
                        }
                    }
                }
            }
            HStack {
                Text("Only All-in-One and Clipboard History have shortcuts at first. Click \u{201C}Record Shortcut\u{201D} to add one, \u{232B} to remove it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") { ShortcutStore.resetAll() }
            }
        }
        .formStyle(.grouped)
    }
}

/// Settings → Recording → Camera: on or off, which camera, and the bubble's look, with a
/// small diagram of where it sits in the recording.
@MainActor
private struct CameraSettingsSection: View {
    @AppStorage(Preferences.Key.recordCamera.rawValue) private var enabled = false
    @AppStorage(Preferences.Key.recordCameraID.rawValue) private var cameraID = ""
    @AppStorage(Preferences.Key.cameraShape.rawValue) private var shape = CameraStyle.Shape.circle.rawValue
    @AppStorage(Preferences.Key.cameraSize.rawValue) private var size = CameraStyle.Size.medium.rawValue
    @AppStorage(Preferences.Key.cameraPosition.rawValue) private var position = CameraStyle.Position.bottomLeft.rawValue
    @AppStorage(Preferences.Key.cameraBorder.rawValue) private var border = CameraStyle.Border.white.rawValue
    @AppStorage(Preferences.Key.cameraMirror.rawValue) private var mirror = true
    @State private var cameras: [CameraDevices.Device] = []

    var body: some View {
        Section("Camera") {
            Toggle("Show my camera in recordings", isOn: $enabled)
            Picker("Camera", selection: $cameraID) {
                Text("System default").tag("")
                ForEach(cameras) { Text($0.name).tag($0.id) }
                // A saved camera that's unplugged keeps its place; the default is used meanwhile.
                if !cameraID.isEmpty, !cameras.contains(where: { $0.id == cameraID }) {
                    Text("Saved camera (not connected)").tag(cameraID)
                }
            }
            .disabled(!enabled)
            if cameras.isEmpty {
                Text("No camera is connected. Built-in, USB, capture-card, virtual and iPhone cameras all show up here when connected.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Shape", selection: $shape) {
                        ForEach(CameraStyle.Shape.allCases) { Label($0.title, systemImage: $0.symbol).tag($0.rawValue) }
                    }
                    Picker("Size", selection: $size) {
                        ForEach(CameraStyle.Size.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("Position", selection: $position) {
                        ForEach(CameraStyle.Position.allCases) { Label($0.title, systemImage: $0.symbol).tag($0.rawValue) }
                    }
                    Picker("Border", selection: $border) {
                        ForEach(CameraStyle.Border.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Toggle("Mirror", isOn: $mirror)
                }
                CameraLayoutPreview(
                    shape: CameraStyle.Shape(rawValue: shape) ?? .circle,
                    size: CameraStyle.Size(rawValue: size) ?? .medium,
                    position: CameraStyle.Position(rawValue: position) ?? .bottomLeft,
                    border: CameraStyle.Border(rawValue: border) ?? .white
                )
            }
            .disabled(!enabled)
            Text("The camera shows in a bubble inside the recording area, recorded exactly as you see it. Drag it anywhere, even while recording. The Camera menu on the recording toolbar has the same options.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            CameraDevices.startWatching()
            cameras = CameraDevices.all()
        }
        .onReceive(NotificationCenter.default.publisher(for: CameraDevices.didChange)) { _ in
            cameras = CameraDevices.all()
        }
    }
}

/// A miniature recording area showing the bubble's shape, size, corner and border.
private struct CameraLayoutPreview: View {
    let shape: CameraStyle.Shape
    let size: CameraStyle.Size
    let position: CameraStyle.Position
    let border: CameraStyle.Border

    var body: some View {
        let frame = CGSize(width: 200, height: 125)
        // The recording area is drawn at about 1/7 scale.
        let height = size.points / 7
        let bubble = CGSize(width: height * shape.aspect, height: height)
        let radius = shape.cornerRadius(for: bubble)
        ZStack(alignment: alignment) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color.blue.opacity(0.25), Color.purple.opacity(0.18)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.gray.opacity(0.55))
                .overlay(Image(systemName: "person.fill").font(.system(size: height * 0.5)).foregroundStyle(.white.opacity(0.9)))
                .overlay(ring(radius: radius))
                .frame(width: bubble.width, height: bubble.height)
                .shadow(color: border.glows ? Color(nsColor: border.color ?? .white).opacity(0.9) : .black.opacity(0.25),
                        radius: border.glows ? 5 : 2, y: border.glows ? 0 : 1)
                .padding(8)
        }
        .frame(width: frame.width, height: frame.height)
        .animation(.easeOut(duration: 0.2), value: position)
        .animation(.easeOut(duration: 0.2), value: shape)
        .animation(.easeOut(duration: 0.2), value: size)
        .animation(.easeOut(duration: 0.2), value: border)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: \(shape.title) camera, \(size.title), \(position.title)")
    }

    @ViewBuilder
    private func ring(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if border == .rainbow {
            shape.strokeBorder(AngularGradient(colors: CameraStyle.Border.rainbowColors.map { Color(nsColor: $0) },
                                               center: .center), lineWidth: 1.5)
        } else {
            shape.strokeBorder(border.color.map { Color(nsColor: $0) } ?? .clear, lineWidth: border == .none ? 0 : 1.5)
        }
    }

    private var alignment: Alignment {
        switch position {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }
}

/// Settings → Clipboard → Ignored apps: password managers (on by default) and apps you add.
@MainActor
private struct IgnoredAppsSection: View {
    @State private var ignorePasswordManagers = IgnoredApps.ignorePasswordManagers
    @State private var custom = IgnoredApps.custom
    @State private var installed = IgnoredApps.installedPasswordManagers()
    @State private var running: [IgnoredApps.App] = []

    var body: some View {
        Section("Ignored apps") {
            Toggle("Ignore password managers and Keychain", isOn: Binding(
                get: { ignorePasswordManagers },
                set: { IgnoredApps.ignorePasswordManagers = $0 }
            ))
            Text(passwordManagerNote)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(custom, id: \.self) { bundleID in
                HStack(spacing: 10) {
                    if let icon = IgnoredApps.icon(for: bundleID) {
                        Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "app.dashed").frame(width: 20, height: 20)
                    }
                    Text(IgnoredApps.name(for: bundleID))
                    Spacer()
                    Button {
                        IgnoredApps.remove(bundleID)
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Save copies from this app again")
                    .accessibilityLabel("Stop ignoring \(IgnoredApps.name(for: bundleID))")
                }
            }

            HStack {
                Text(custom.isEmpty ? "Copies from these apps are never saved." : "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu("Add Running App") {
                    if running.isEmpty {
                        Text("No other apps are open")
                    }
                    ForEach(running) { app in
                        Button(app.name) { IgnoredApps.add(app.bundleID) }
                    }
                }
                .fixedSize()
                .onHover { if $0 { running = IgnoredApps.runningCandidates() } }
                Button("Choose App…", action: chooseApp)
            }
        }
        .onAppear { running = IgnoredApps.runningCandidates() }
        .onReceive(NotificationCenter.default.publisher(for: IgnoredApps.didChange)) { _ in
            ignorePasswordManagers = IgnoredApps.ignorePasswordManagers
            custom = IgnoredApps.custom
            running = IgnoredApps.runningCandidates()
        }
    }

    private var passwordManagerNote: String {
        let names = installed.map(\.name)
        let found = names.isEmpty ? "" : " On this Mac: \(names.joined(separator: ", "))."
        return "Passwords, Keychain Access, 1Password, Bitwarden, LastPass, Dashlane, Keeper, NordPass, Proton Pass, Enpass, KeePassXC and Strongbox.\(found)"
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.message = "Choose apps whose copies Marquee shouldn't save."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { IgnoredApps.add(id) }
        }
    }
}
