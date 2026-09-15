import CoreAudio
import Foundation

struct AudioDevice: Equatable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// Thin wrapper around the CoreAudio HAL for enumerating output devices,
/// reading/setting the system default output device, and subscribing to
/// hardware change notifications (device plug/unplug, default device change).
/// No polling: everything is driven by AudioObjectPropertyListenerBlock.
final class AudioDeviceManager {

    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

    private var deviceListListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    // MARK: - Enumeration

    private func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &size, &deviceIDs)
        guard status == noErr else { return [] }

        return deviceIDs
    }

    private func deviceName(_ id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr -> OSStatus in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else { return "Unknown Device" }
        return name as String
    }

    private func deviceUID(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &uid) { ptr -> OSStatus in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else { return nil }
        return uid as String
    }

    private func transportType(_ id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        guard status == noErr else { return 0 }
        return value
    }

    /// Sum of output channels for a device, used to filter to devices that
    /// can actually play audio (as opposed to input-only devices).
    private func outputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return 0 }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, bufferListPointer)
        guard status == noErr else { return 0 }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// All devices capable of audio output, sorted by name.
    func outputDevices() -> [AudioDevice] {
        allDeviceIDs()
            .filter { outputChannelCount($0) > 0 }
            .map { AudioDevice(id: $0, uid: deviceUID($0) ?? "\($0)", name: deviceName($0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The built-in speakers, identified by transport type rather than name
    /// so this keeps working across different Mac models.
    func builtInOutputDevice() -> AudioDevice? {
        outputDevices().first { device in
            transportType(device.id) == kAudioDeviceTransportTypeBuiltIn
        }
    }

    // MARK: - Default device

    func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &size, &deviceID)
        guard status == noErr else { return nil }
        return deviceID
    }

    /// Sets both the default output device and the default *system* output
    /// device (used for alert sounds), matching what Control Center / Sound
    /// settings do when you pick a device there.
    @discardableResult
    func setDefaultOutputDevice(_ id: AudioDeviceID) -> Bool {
        var deviceID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)

        var outputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let outputStatus = AudioObjectSetPropertyData(systemObjectID, &outputAddress, 0, nil, size, &deviceID)

        var systemAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(systemObjectID, &systemAddress, 0, nil, size, &deviceID)

        return outputStatus == noErr
    }

    // MARK: - Change notifications

    /// Fires whenever hardware is added/removed (e.g. the Dell monitor's
    /// USB-C audio device connects or disconnects).
    func startListeningForDeviceListChanges(_ handler: @escaping () -> Void) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        deviceListListenerBlock = block
        AudioObjectAddPropertyListenerBlock(systemObjectID, &address, DispatchQueue.main, block)
    }

    func stopListeningForDeviceListChanges() {
        guard let block = deviceListListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(systemObjectID, &address, DispatchQueue.main, block)
        deviceListListenerBlock = nil
    }

    /// Fires whenever the default output device changes, including changes
    /// made outside this app (e.g. via Control Center).
    func startListeningForDefaultDeviceChanges(_ handler: @escaping () -> Void) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        defaultDeviceListenerBlock = block
        AudioObjectAddPropertyListenerBlock(systemObjectID, &address, DispatchQueue.main, block)
    }

    func stopListeningForDefaultDeviceChanges() {
        guard let block = defaultDeviceListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(systemObjectID, &address, DispatchQueue.main, block)
        defaultDeviceListenerBlock = nil
    }
}
