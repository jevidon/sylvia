// Reads, without changing anything, which output device the build Mac plays through and the presentation latency
// CoreAudio reports for it (M0 final review round 2, CC2-01). The iOS Simulator plays through the Mac's default
// output device, and an AVPlayer's clock includes that device's output latency, so G0.4's tests that compare the
// player's clock with the rendered audio or with wall time fail when the latency is long (an AirPlay output: about 2 s).
// Scripts/ci.d/60-g04-audio.sh compiles this file, runs it before its tests and samples it with the host load.
//
//   host-audio-output          one line per output device: name, transport, sample rate, the latency parts in frames
//                              and the presentation latency in seconds, the default output marked; then the default
//   host-audio-output --tsv    the default output's name, transport and presentation latency in seconds, tab-separated
//
// Presentation latency = (device latency + safety offset + the largest output stream latency + buffer frame size) /
// nominal sample rate: the parts CoreAudio adds between the time a frame is handed to the device and the time it plays.
// Only property reads (AudioObjectGetPropertyData): the device, its volume, its mute state and its settings are never
// changed. Exit status 0, or 2 when the system reports no default output device.
import CoreAudio
import Foundation

func propertyAddress(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func scalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope,
               _ initial: T) -> T? {
    var address = propertyAddress(selector, scope)
    guard AudioObjectHasProperty(object, &address) else { return nil }
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
    return status == noErr ? value : nil
}

func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                _ scope: AudioObjectPropertyScope) -> [AudioObjectID] {
    var address = propertyAddress(selector, scope)
    var size: UInt32 = 0
    guard AudioObjectHasProperty(object, &address),
          AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    let status = ids.withUnsafeMutableBytes { buffer in
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer.baseAddress!)
    }
    return status == noErr ? Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size)) : []
}

func deviceName(_ device: AudioObjectID) -> String {
    var address = propertyAddress(kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0) }
    guard status == noErr, let text = value?.takeRetainedValue() else { return "unnamed device \(device)" }
    return text as String
}

func transportName(_ device: AudioObjectID) -> String {
    guard let code = scalar(device, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, UInt32(0)) else {
        return "unknown"
    }
    let known: [UInt32: String] = [
        kAudioDeviceTransportTypeBuiltIn: "Built-in", kAudioDeviceTransportTypeAirPlay: "AirPlay",
        kAudioDeviceTransportTypeBluetooth: "Bluetooth", kAudioDeviceTransportTypeBluetoothLE: "Bluetooth LE",
        kAudioDeviceTransportTypeUSB: "USB", kAudioDeviceTransportTypeHDMI: "HDMI",
        kAudioDeviceTransportTypeDisplayPort: "DisplayPort", kAudioDeviceTransportTypeThunderbolt: "Thunderbolt",
        kAudioDeviceTransportTypeVirtual: "Virtual", kAudioDeviceTransportTypeAggregate: "Aggregate",
        kAudioDeviceTransportTypeAutoAggregate: "Aggregate (automatic)",
    ]
    if let label = known[code] { return label }
    let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xff) }
    return "'" + String(decoding: bytes, as: UTF8.self) + "'"
}

struct Output {
    let device: AudioObjectID
    let name: String
    let transport: String
    let sampleRate: Double
    let deviceLatency: UInt32
    let safetyOffset: UInt32
    let streamLatency: UInt32
    let bufferFrames: UInt32
    var frames: UInt32 { deviceLatency + safetyOffset + streamLatency + bufferFrames }
    var seconds: Double? { sampleRate > 0 ? Double(frames) / sampleRate : nil }
}

func outputDevice(_ device: AudioObjectID) -> Output? {
    let streams = objectList(device, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
    guard !streams.isEmpty else { return nil }  // an input-only device
    let scope = kAudioObjectPropertyScopeOutput
    let global = kAudioObjectPropertyScopeGlobal
    return Output(
        device: device, name: deviceName(device), transport: transportName(device),
        sampleRate: scalar(device, kAudioDevicePropertyNominalSampleRate, global, Float64(0)) ?? 0,
        deviceLatency: scalar(device, kAudioDevicePropertyLatency, scope, UInt32(0)) ?? 0,
        safetyOffset: scalar(device, kAudioDevicePropertySafetyOffset, scope, UInt32(0)) ?? 0,
        streamLatency: streams.compactMap { scalar($0, kAudioStreamPropertyLatency, global, UInt32(0)) }.max() ?? 0,
        bufferFrames: scalar(device, kAudioDevicePropertyBufferFrameSize, global, UInt32(0)) ?? 0)
}

func secondsText(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "unknown" }

let system = AudioObjectID(kAudioObjectSystemObject)
let global = kAudioObjectPropertyScopeGlobal
let defaultID = scalar(system, kAudioHardwarePropertyDefaultOutputDevice, global, AudioObjectID(0)) ?? 0
let systemID = scalar(system, kAudioHardwarePropertyDefaultSystemOutputDevice, global, AudioObjectID(0)) ?? 0
let outputs = objectList(system, kAudioHardwarePropertyDevices, global).compactMap(outputDevice)
let defaultOutput = defaultID == 0 ? nil : (outputs.first { $0.device == defaultID } ?? outputDevice(defaultID))

if CommandLine.arguments.dropFirst().first == "--tsv" {
    guard let out = defaultOutput else {
        print(["none", "none", "unknown"].joined(separator: "\t"))
        exit(2)
    }
    print([out.name, out.transport, secondsText(out.seconds)].joined(separator: "\t"))
    exit(0)
}

for out in outputs {
    var roles: [String] = []
    if out.device == defaultID { roles.append("default output (the iOS Simulator plays through it)") }
    if out.device == systemID { roles.append("default system output (alerts)") }
    print("output device: \(out.name); transport \(out.transport); \(Int(out.sampleRate)) Hz; latency in frames: "
          + "device \(out.deviceLatency), safety offset \(out.safetyOffset), stream \(out.streamLatency), "
          + "buffer \(out.bufferFrames); presentation latency \(secondsText(out.seconds)) s"
          + (roles.isEmpty ? "" : "; " + roles.joined(separator: ", ")))
}
guard let out = defaultOutput else {
    print("default output: none reported")
    exit(2)
}
print("default output: \(out.name); transport \(out.transport); presentation latency \(secondsText(out.seconds)) s")
