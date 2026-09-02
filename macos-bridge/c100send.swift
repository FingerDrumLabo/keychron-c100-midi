// c100send -- user half of the bridge. Reads "+XX"/"-XX" keycode events on stdin
// (from `sudo ./c100grab`) and publishes them as MIDI on a virtual CoreMIDI source.
// Two pads are reserved as lighting controls: they send no note and instead step the
// keyboard's RGB effect over the QMK/VIA raw-HID channel.
//     sudo ./c100grab | ./c100send
//     ./c100send --test          (no keyboard: sends note 60 once a second)
import Foundation
import CoreMIDI
import IOKit
import IOKit.hid

let MIDI_CHANNEL: UInt8 = 0
let VELOCITY: UInt8 = 127
let SOURCE_NAME = "Keychron C100"

// VIA raw-HID
let VENDOR = 0x3434, PRODUCT = 0x042C, RAW_PAGE = 0xFF60, RAW_USAGE = 0x61
let VIA_SIZE = 32
let VIA_GET: UInt8 = 0x08, VIA_SET: UInt8 = 0x07, VIA_SAVE: UInt8 = 0x09
let CH_RGB_MATRIX: UInt8 = 0x03, VAL_EFFECT: UInt8 = 0x02, VAL_COLOR: UInt8 = 0x04
let EFFECT_MAX = 24            // discovered by writing 0xFF and reading the clamp back

func note(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

// ------------------------------------------------------------------ pad map
func mapPath() -> String {
    if let i = CommandLine.arguments.firstIndex(of: "--map"), i + 1 < CommandLine.arguments.count {
        return CommandLine.arguments[i + 1]
    }
    return URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        .deletingLastPathComponent().appendingPathComponent("keycode_map.json").path
}

var effectList: [Int] = []            // if set, the pad cycles only through these
var hueStep: Int = 0                  // 0 = leave the colour alone
var currentHue: Int = 0
var currentSat: UInt8 = 255
var padToKeycode  = [Int: UInt8]()
var keycodeToNote = [UInt8: UInt8]()
var keycodeToPad  = [UInt8: Int]()
var keycodeToFunc = [UInt8: String]()

if let data = try? Data(contentsOf: URL(fileURLWithPath: mapPath())),
   let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
    for e in (root["map"] as? [[String: Any]]) ?? [] {
        if let kc = e["keycode"] as? Int, let n = e["note"] as? Int, let p = e["pad"] as? Int {
            keycodeToNote[UInt8(kc)] = UInt8(n); keycodeToPad[UInt8(kc)] = p
            padToKeycode[p] = UInt8(kc)
        }
    }
    if let list = root["rgbEffects"] as? [Int], !list.isEmpty { effectList = list }
    if let c = root["colorPerHit"] as? [String: Any], (c["enabled"] as? Bool) == true {
        hueStep = (c["step"] as? Int) ?? 11
    }
    for f in (root["functionPads"] as? [[String: Any]]) ?? [] {
        guard let a = f["action"] as? String else { continue }
        var kc: UInt8? = nil
        if let p = f["pad"] as? Int { kc = padToKeycode[p] }
        if kc == nil, let v = f["keycode"] as? Int { kc = UInt8(v) }
        if let kc = kc {
            keycodeToFunc[kc] = a
            keycodeToNote.removeValue(forKey: kc)   // function pads send no note
        }
    }
}
guard keycodeToNote.count + keycodeToFunc.count == 100 else {
    note("could not read 100 pad mappings from \(mapPath())"); exit(1)
}

// ------------------------------------------------------------------ MIDI out
var client = MIDIClientRef(), source = MIDIEndpointRef()
guard MIDIClientCreate(SOURCE_NAME as CFString, nil, nil, &client) == noErr,
      MIDISourceCreate(client, SOURCE_NAME as CFString, &source) == noErr else {
    note("could not create the virtual MIDI source"); exit(1)
}

func midiSend(_ bytes: [UInt8]) {
    var list = MIDIPacketList()
    withUnsafeMutablePointer(to: &list) { p in
        var pkt = MIDIPacketListInit(p)
        pkt = MIDIPacketListAdd(p, MemoryLayout<MIDIPacketList>.size, pkt, mach_absolute_time(), bytes.count, bytes)
        MIDIReceived(source, p)
    }
}
func noteOn(_ n: UInt8)  { midiSend([0x90 | MIDI_CHANNEL, n, VELOCITY]) }
func noteOff(_ n: UInt8) { midiSend([0x80 | MIDI_CHANNEL, n, 0]) }

// ------------------------------------------------------------------ RGB over VIA
var rawManager: IOHIDManager? = nil   // must outlive openRawHID(); releasing it closes rawDevice
var rawDevice: IOHIDDevice? = nil
var viaResponse: [UInt8]? = nil
var currentEffect: Int = -1

func iprop(_ d: IOHIDDevice, _ k: String) -> Int { (IOHIDDeviceGetProperty(d, k as CFString) as? Int) ?? -1 }

let viaCB: IOHIDReportCallback = { _, _, _, _, _, r, len in
    var a = [UInt8](); for i in 0..<Int(len) { a.append(r[i]) }
    viaResponse = a
    CFRunLoopStop(CFRunLoopGetCurrent())
}

func openRawHID() {
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    rawManager = mgr
    IOHIDManagerSetDeviceMatching(mgr, [
        kIOHIDVendorIDKey: VENDOR, kIOHIDProductIDKey: PRODUCT,
        kIOHIDPrimaryUsagePageKey: RAW_PAGE, kIOHIDPrimaryUsageKey: RAW_USAGE,
    ] as CFDictionary)
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    guard let devs = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>, let d = devs.first else { return }
    guard IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: VIA_SIZE)
    IOHIDDeviceRegisterInputReportCallback(d, buf, VIA_SIZE, viaCB, nil)
    IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    rawDevice = d

    // one round trip at startup to learn which effect is showing
    viaResponse = nil
    if viaSend([VIA_GET, CH_RGB_MATRIX, VAL_EFFECT]) {
        CFRunLoopRunInMode(.defaultMode, 0.5, false)
        if let r = viaResponse, r.count > 3 { currentEffect = Int(r[3]) }
    }
    viaResponse = nil
    if viaSend([VIA_GET, CH_RGB_MATRIX, VAL_COLOR]) {
        CFRunLoopRunInMode(.defaultMode, 0.5, false)
        if let r = viaResponse, r.count > 4 { currentHue = Int(r[3]); currentSat = r[4] }
    }
}

@discardableResult
func viaSend(_ bytes: [UInt8]) -> Bool {
    guard let d = rawDevice else { return false }
    var out = [UInt8](repeating: 0, count: VIA_SIZE)
    for (i, b) in bytes.enumerated() where i < VIA_SIZE { out[i] = b }
    return IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, 0, out, VIA_SIZE) == kIOReturnSuccess
}

let rgbQueue = DispatchQueue(label: "c100.rgb")

// Called on every pad hit. Never saves to EEPROM -- this runs hundreds of times a
// minute and `via_qmk_rgb_matrix_set_value` only touches RAM. The keyboard goes back
// to its saved colour when it loses power.
func bumpHue() {
    guard hueStep > 0, rawDevice != nil else { return }
    currentHue = (currentHue + hueStep) % 256
    let h = UInt8(currentHue), sat = currentSat
    rgbQueue.async { viaSend([VIA_SET, CH_RGB_MATRIX, VAL_COLOR, h, sat]) }
}

// Persist to the keyboard's memory, but only once the user stops pressing, so a fast
// scroll through the effects does not hammer the EEPROM.
var saveGeneration = 0
func scheduleSave() {
    saveGeneration += 1
    let mine = saveGeneration
    DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
        guard mine == saveGeneration else { return }
        viaSend([VIA_SAVE, CH_RGB_MATRIX])
    }
}

func stepEffect(_ delta: Int) {
    guard rawDevice != nil else { note("  (lighting control unavailable)"); return }
    if currentEffect < 0 { currentEffect = 0 }
    if effectList.isEmpty {
        currentEffect = (currentEffect + delta + (EFFECT_MAX + 1)) % (EFFECT_MAX + 1)
    } else {
        // Step within the chosen shortlist. If the keyboard is on something else
        // entirely, the first press jumps to the first entry in the list.
        let i = effectList.firstIndex(of: currentEffect)
        currentEffect = i == nil ? effectList[0]
                                 : effectList[(i! + delta + effectList.count) % effectList.count]
    }
    guard viaSend([VIA_SET, CH_RGB_MATRIX, VAL_EFFECT, UInt8(currentEffect)]) else {
        print("  !! could not reach the keyboard's lighting channel")
        fflush(stdout); return
    }
    print(effectList.isEmpty ? "  lighting effect \(currentEffect) / \(EFFECT_MAX)"
                             : "  lighting effect \(currentEffect)")
    fflush(stdout)
    scheduleSave()
}

// ------------------------------------------------------------------ run
var sounding = Set<UInt8>()
func shutdown() {
    for n in sounding { noteOff(n) }
    midiSend([0xB0 | MIDI_CHANNEL, 123, 0])
    print("\nstopped."); exit(0)
}
signal(SIGINT)  { _ in shutdown() }
signal(SIGTERM) { _ in shutdown() }

print("MIDI source published: \"\(SOURCE_NAME)\"  (as user \(NSUserName()))")

if CommandLine.arguments.contains("--test") {
    print("test mode: sending note 60 once a second. Control-C to stop.")
    while true {
        noteOn(60); sounding.insert(60); print("  note 60 ON")
        Thread.sleep(forTimeInterval: 0.25)
        noteOff(60); sounding.remove(60)
        Thread.sleep(forTimeInterval: 0.75)
    }
}

openRawHID()
if rawDevice != nil {
    print("lighting control ready — current effect \(currentEffect) / \(EFFECT_MAX)")
    if !effectList.isEmpty { print("  cycling only through effects \(effectList)") }
    if hueStep > 0 { print("  colour walks +\(hueStep) hue on every hit (starting at \(currentHue))") }
    for (kc, a) in keycodeToFunc.sorted(by: { $0.value < $1.value }) {
        print("  pad \(keycodeToPad[kc] ?? 0): \(a == "rgb_next" ? "next effect" : "previous effect")")
    }
} else {
    print("lighting control unavailable (the RGB channel is busy — is Keychron Launcher open?)")
}

print("\nplay. Control-C to stop.\n")
while let line = readLine(strippingNewline: true) {
    guard line.count == 3, let kc = UInt8(line.dropFirst(), radix: 16) else { continue }
    let down = line.hasPrefix("+")
    if let action = keycodeToFunc[kc] {
        if down { stepEffect(action == "rgb_next" ? 1 : -1) }
        continue
    }
    guard let n = keycodeToNote[kc] else { continue }
    if down {
        noteOn(n); sounding.insert(n)          // MIDI first, always
        bumpHue()
        print("  pad \(keycodeToPad[kc] ?? 0)  note \(n)  ON"); fflush(stdout)
    } else {
        noteOff(n); sounding.remove(n)
    }
}
shutdown()
