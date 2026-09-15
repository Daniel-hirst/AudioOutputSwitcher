import AppKit
import CoreAudio

/// Owns the NSStatusItem, builds its dropdown menu, and reacts to CoreAudio
/// hardware-change notifications to auto-switch to/from the Dell monitor's
/// USB-C speakers.
final class StatusBarController {

    /// Devices whose name contains one of these (case-insensitive) are
    /// treated as "the Dell monitor" for auto-switch purposes.
    private static let dellNameMatches = ["s2725qc", "dell"]

    private static let autoSwitchDefaultsKey = "autoSwitchOnConnect"
    /// Delay before switching to a newly-connected device: a USB audio
    /// device sometimes appears in the device list slightly before CoreAudio
    /// has it fully ready to become the default output.
    private static let connectSwitchDelay: TimeInterval = 0.75

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let audioManager = AudioDeviceManager()
    private var knownDeviceUIDs: Set<String> = []

    private var autoSwitchEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.autoSwitchDefaultsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: Self.autoSwitchDefaultsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoSwitchDefaultsKey) }
    }

    init() {
        configureStatusItemIcon()
        knownDeviceUIDs = Set(audioManager.outputDevices().map(\.uid))
        rebuildMenu()

        audioManager.startListeningForDeviceListChanges { [weak self] in
            self?.handleDeviceListChanged()
        }
        audioManager.startListeningForDefaultDeviceChanges { [weak self] in
            self?.rebuildMenu()
        }
    }

    deinit {
        audioManager.stopListeningForDeviceListChanges()
        audioManager.stopListeningForDefaultDeviceChanges()
    }

    // MARK: - UI

    private func configureStatusItemIcon() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "hifispeaker.fill", accessibilityDescription: "Audio Output")
        image?.isTemplate = true
        button.image = image
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let currentDefaultID = audioManager.defaultOutputDeviceID()
        let devices = audioManager.outputDevices()

        let header = NSMenuItem(title: "Output Device", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if devices.isEmpty {
            let empty = NSMenuItem(title: "No output devices found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for device in devices {
            let item = NSMenuItem(
                title: device.name,
                action: #selector(selectDevice(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device.id
            item.state = (device.id == currentDefaultID) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let autoItem = NSMenuItem(
            title: "Auto-Switch to Dell Monitor on Connect",
            action: #selector(toggleAutoSwitch(_:)),
            keyEquivalent: ""
        )
        autoItem.target = self
        autoItem.state = autoSwitchEnabled ? .on : .off
        menu.addItem(autoItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func selectDevice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? AudioDeviceID else { return }
        audioManager.setDefaultOutputDevice(id)
        rebuildMenu()
    }

    @objc private func toggleAutoSwitch(_ sender: NSMenuItem) {
        autoSwitchEnabled.toggle()
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Auto-switch logic

    private func isDellMonitor(_ device: AudioDevice) -> Bool {
        let name = device.name.lowercased()
        return Self.dellNameMatches.contains { name.contains($0) }
    }

    private func handleDeviceListChanged() {
        let currentDevices = audioManager.outputDevices()
        let currentUIDs = Set(currentDevices.map(\.uid))
        let addedUIDs = currentUIDs.subtracting(knownDeviceUIDs)
        let removedUIDs = knownDeviceUIDs.subtracting(currentUIDs)
        knownDeviceUIDs = currentUIDs

        defer { rebuildMenu() }

        guard autoSwitchEnabled else { return }

        if let connectedDell = currentDevices.first(where: { addedUIDs.contains($0.uid) && isDellMonitor($0) }) {
            let deviceID = connectedDell.id
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectSwitchDelay) { [weak self] in
                self?.audioManager.setDefaultOutputDevice(deviceID)
                self?.rebuildMenu()
            }
            return
        }

        if !removedUIDs.isEmpty {
            let dellStillPresent = currentDevices.contains { isDellMonitor($0) }
            if !dellStillPresent, let builtIn = audioManager.builtInOutputDevice() {
                audioManager.setDefaultOutputDevice(builtIn.id)
            }
        }
    }
}
