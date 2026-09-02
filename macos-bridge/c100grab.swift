// c100grab -- root half. Seizes the Keychron C100's keyboard interface and prints
// one line per pad event to stdout:  "+68" on press, "-68" on release (hex keycode).
// Pipe it into c100send, which runs as the normal user and emits the MIDI:
//     sudo ./c100grab | ./c100send
import Foundation
import IOKit
import IOKit.hid

let VENDOR = 0x3434, PRODUCT = 0x042C, KBD_PAGE = 0x0001, KBD_USAGE = 0x06

setvbuf(stdout, nil, _IOLBF, 0)   // line-buffered: the pipe must not hold events back

func iprop(_ d: IOHIDDevice, _ k: String) -> Int { (IOHIDDeviceGetProperty(d, k as CFString) as? Int) ?? -1 }
func err(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

guard getuid() == 0 else {
    err("c100grab must run as root:  sudo ./c100grab | ./c100send")
    exit(1)
}

var held = Set<UInt8>()
let cb: IOHIDReportCallback = { _, _, _, _, _, report, len in
    guard len >= 8 else { return }
    var now = Set<UInt8>()
    for i in 2..<8 where report[i] >= 0x04 { now.insert(report[i]) }
    for kc in now.subtracting(held) { print(String(format: "+%02X", kc)) }
    for kc in held.subtracting(now) { print(String(format: "-%02X", kc)) }
    held = now
}

let opts = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
// Match ONLY the keyboard interface. Opening the manager opens every device it
// matches, with the manager's options -- so matching all three interfaces and then
// asking for a seize on just one does not work: the manager has already opened the
// keyboard un-seized, and the later seize is a no-op. Narrowing the match means the
// manager opens the keyboard and nothing else, and the mouse and the 0xFF60 raw-HID
// channel stay free for Keychron Launcher.
IOHIDManagerSetDeviceMatching(mgr, [
    kIOHIDVendorIDKey: VENDOR,
    kIOHIDProductIDKey: PRODUCT,
    kIOHIDPrimaryUsagePageKey: KBD_PAGE,
    kIOHIDPrimaryUsageKey: KBD_USAGE,
] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let mgrRC = IOHIDManagerOpen(mgr, opts)   // opts == seize

guard let devs = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>,
      let kbd = devs.first(where: { iprop($0, kIOHIDPrimaryUsagePageKey) == KBD_PAGE && iprop($0, kIOHIDPrimaryUsageKey) == KBD_USAGE })
else { err("C100 not found -- is it plugged in?"); exit(1) }

guard mgrRC == kIOReturnSuccess else {
    err(String(format: "could not seize the keyboard (0x%08X) -- keys would still type, refusing to run", mgrRC))
    exit(1)
}
let rc = IOHIDDeviceOpen(kbd, opts)
guard rc == kIOReturnSuccess else { err(String(format: "could not seize the keyboard (0x%08X)", rc)); exit(1) }

let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
IOHIDDeviceRegisterInputReportCallback(kbd, buf, 8, cb, nil)
IOHIDDeviceScheduleWithRunLoop(kbd, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

err("c100grab: keyboard seized -- its keys will not type anything")
CFRunLoopRun()
