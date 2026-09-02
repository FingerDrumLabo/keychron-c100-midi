// c100setup -- prepares a Keychron C100 8K for use as a MIDI pad controller.
//
//   c100setup status              show what is on the keyboard right now
//   c100setup backup [file]       save the current keymap (all layers) to JSON
//   c100setup install [--layout mf64|launchpad]
//                                 back up, then give all 100 keys distinct keycodes
//                                 and write keycode_map.json for the bridge
//   c100setup restore <file>      put a saved keymap back
//
// Talks to the keyboard over the QMK/VIA raw-HID channel (usage page 0xFF60). That
// channel is the same one Keychron Launcher uses, so nothing here is a private hack --
// but it does rewrite your keymap, which is why `install` always backs up first.
import Foundation
import IOKit
import IOKit.hid

let VENDOR = 0x3434, PRODUCT = 0x042C, RAW_PAGE = 0xFF60, RAW_USAGE = 0x61
let SIZE = 32, ROWS = 10, COLS = 10, CHUNK = 28

let CMD_GET_KEYCODE: UInt8 = 0x04, CMD_SET_KEYCODE: UInt8 = 0x05
let CMD_LAYER_COUNT: UInt8 = 0x11, CMD_GET_BUFFER: UInt8 = 0x12

func die(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }
func iprop(_ d: IOHIDDevice, _ k: String) -> Int { (IOHIDDeviceGetProperty(d, k as CFString) as? Int) ?? -1 }

// ---------------------------------------------------------------- transport
var response: [UInt8]? = nil
let cb: IOHIDReportCallback = { _, _, _, _, _, r, len in
    var a = [UInt8](); for i in 0..<Int(len) { a.append(r[i]) }
    response = a; CFRunLoopStop(CFRunLoopGetCurrent())
}

let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(mgr, [
    kIOHIDVendorIDKey: VENDOR, kIOHIDProductIDKey: PRODUCT,
    kIOHIDPrimaryUsagePageKey: RAW_PAGE, kIOHIDPrimaryUsageKey: RAW_USAGE,
] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))

guard let devs = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>, let raw = devs.first else {
    die("Keychron C100 not found.\n  - is it plugged in with a USB cable?\n  - close Keychron Launcher if it is open, it holds this channel")
}
guard IOHIDDeviceOpen(raw, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
    die("could not open the keyboard's config channel. Close Keychron Launcher and try again.")
}
let inBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: SIZE)
IOHIDDeviceRegisterInputReportCallback(raw, inBuf, SIZE, cb, nil)
IOHIDDeviceScheduleWithRunLoop(raw, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

@discardableResult
func ask(_ bytes: [UInt8], wait: Double = 0.4) -> [UInt8]? {
    var out = [UInt8](repeating: 0, count: SIZE)
    for (i, b) in bytes.enumerated() where i < SIZE { out[i] = b }
    response = nil
    guard IOHIDDeviceSetReport(raw, kIOHIDReportTypeOutput, 0, out, SIZE) == kIOReturnSuccess else { return nil }
    CFRunLoopRunInMode(.defaultMode, wait, false)
    return response
}

func layerCount() -> Int { Int(ask([CMD_LAYER_COUNT])?[1] ?? 4) }

func readKeymap() -> [UInt8] {
    let total = layerCount() * ROWS * COLS * 2
    var buf = [UInt8](); var off = 0
    while off < total {
        let n = min(CHUNK, total - off)
        guard let r = ask([CMD_GET_BUFFER, UInt8((off >> 8) & 0xFF), UInt8(off & 0xFF), UInt8(n)]) else {
            die("lost contact with the keyboard while reading (offset \(off))")
        }
        buf.append(contentsOf: r[4..<(4 + n)]); off += n
    }
    return buf
}

func setKeycode(_ layer: Int, _ row: Int, _ col: Int, _ kc: UInt16) -> Bool {
    _ = ask([CMD_SET_KEYCODE, UInt8(layer), UInt8(row), UInt8(col), UInt8(kc >> 8), UInt8(kc & 0xFF)], wait: 0.25)
    guard let v = ask([CMD_GET_KEYCODE, UInt8(layer), UInt8(row), UInt8(col)], wait: 0.25), v.count > 5 else { return false }
    return (UInt16(v[4]) << 8 | UInt16(v[5])) == kc
}

// ---------------------------------------------------------------- layouts
// Pad numbers 1-100 laid out on the physical 10x10 grid, row 0 = top row.
// The 8x8 block at the bottom-left is the MIDI Fighter 64 area.
let mf64Pads: [[Int]] = [
    [69,70,71,72, 77,78,79,80, 100,98],
    [65,66,67,68, 73,74,75,76,  99,97],
    [29,30,31,32, 61,62,63,64,  96,92],
    [25,26,27,28, 57,58,59,60,  95,91],
    [21,22,23,24, 53,54,55,56,  94,90],
    [17,18,19,20, 49,50,51,52,  93,89],
    [13,14,15,16, 45,46,47,48,  88,84],
    [ 9,10,11,12, 41,42,43,44,  87,83],
    [ 5, 6, 7, 8, 37,38,39,40,  86,82],
    [ 1, 2, 3, 4, 33,34,35,36,  85,81],
]
// pads 1-80 -> notes 36-115, pads 81-100 -> notes 16-35.
// The four 4x4 banks land on 36-51 / 52-67 / 68-83 / 84-99, i.e. exactly one
// Ableton Drum Rack page each.
func mf64Note(_ pad: Int) -> Int { pad <= 80 ? pad + 35 : pad - 65 }

// Plain left-to-right, bottom-to-top over the same regions.
func launchpadGrid() -> [[Int]] {
    var g = [[Int]](repeating: [Int](repeating: 0, count: COLS), count: ROWS)
    var n = 36
    for r in stride(from: 9, through: 2, by: -1) { for c in 0..<8 { g[r][c] = n; n += 1 } }   // 8x8 -> 36-99
    n = 100
    for r in stride(from: 1, through: 0, by: -1) { for c in 0..<8 { g[r][c] = n; n += 1 } }   // top rows -> 100-115
    n = 16
    for r in stride(from: 9, through: 0, by: -1) { for c in 8..<10 { g[r][c] = n; n += 1 } }  // right cols -> 16-35
    return g
}

// 100 distinct keycodes, most-harmless-first. Everything here is a plain HID usage
// that QMK transmits as-is (0x04-0xA4). The first 47 do nothing at all on macOS, so
// if the bridge is not running the damage is as small as possible.
func keycodePool() -> [UInt16] {
    var p = [UInt16]()
    func add(_ a: Int, _ b: Int) { for v in a...b { p.append(UInt16(v)) } }
    add(0x68, 0x73)   // F13-F24
    add(0x99, 0xA4)   // Alternate Erase .. ExSel
    add(0x87, 0x8F)   // International 1-9
    add(0x90, 0x98)   // LANG 1-9
    add(0x82, 0x86)   // locking keys, keypad comma, keypad equal
    add(0x04, 0x1D)   // a-z
    add(0x1E, 0x27)   // 1-0
    add(0x2D, 0x38)   // punctuation
    add(0x59, 0x62)   // keypad 1-0
    return Array(p.prefix(100))
}

// ---------------------------------------------------------------- files
func here() -> URL {
    URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
}
func stamp() -> String {
    ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
}

func writeBackup(to path: String?) -> String {
    let buf = readKeymap(), layers = layerCount()
    let p = path ?? here().appendingPathComponent("backup-\(stamp()).json").path
    var rows = [String]()
    for l in 0..<layers {
        var rs = [String]()
        for r in 0..<ROWS {
            let cs = (0..<COLS).map { c -> String in
                let i = ((l * ROWS * COLS) + (r * COLS) + c) * 2
                return String(UInt16(buf[i]) << 8 | UInt16(buf[i + 1]))
            }
            rs.append("      [" + cs.joined(separator: ", ") + "]")
        }
        rows.append("    [\n" + rs.joined(separator: ",\n") + "\n    ]")
    }
    let json = """
    {
      "device": "Keychron C100 8K",
      "rows": \(ROWS), "cols": \(COLS), "layers": \(layers),
      "savedAt": "\(ISO8601DateFormatter().string(from: Date()))",
      "keymap": [
    \(rows.joined(separator: ",\n"))
      ]
    }

    """
    try? json.write(toFile: p, atomically: true, encoding: .utf8)
    return p
}

// ---------------------------------------------------------------- commands
let args = Array(CommandLine.arguments.dropFirst())
let cmd = args.first ?? "status"

switch cmd {

case "status":
    let buf = readKeymap()
    print("Keychron C100 8K found. \(layerCount()) layers, \(ROWS)x\(COLS) keys.\n")
    print("layer 0 keycodes:")
    var distinct = Set<UInt16>()
    for r in 0..<ROWS {
        var line = "  "
        for c in 0..<COLS {
            let i = (r * COLS + c) * 2
            let kc = UInt16(buf[i]) << 8 | UInt16(buf[i + 1])
            distinct.insert(kc); line += String(format: "%04X ", kc)
        }
        print(line)
    }
    print("\n\(distinct.count) distinct keycodes out of 100.")
    print(distinct.count == 100 ? "Looks set up for MIDI." : "Not set up yet -- run: c100setup install")

case "backup":
    let p = writeBackup(to: args.count > 1 ? args[1] : nil)
    print("saved: \(p)")

case "install":
    var layout = "mf64"
    if let i = args.firstIndex(of: "--layout"), i + 1 < args.count { layout = args[i + 1] }
    guard ["mf64", "launchpad"].contains(layout) else { die("unknown layout '\(layout)' -- use mf64 or launchpad") }

    print("backing up the current keymap first...")
    print("  saved: \(writeBackup(to: nil))\n")

    let pads = layout == "mf64" ? mf64Pads : nil
    let lpGrid = layout == "launchpad" ? launchpadGrid() : nil
    let pool = keycodePool()

    var entries = [String]()
    var failures = 0
    var lightPad = 0        // top-right corner doubles as the lighting button
    print("writing 100 keycodes (layout: \(layout))...")
    for r in 0..<ROWS {
        for c in 0..<COLS {
            let pad: Int, note: Int
            if let pads = pads { pad = pads[r][c]; note = mf64Note(pad) }
            else { note = lpGrid![r][c]; pad = r * COLS + c + 1 }
            let kc = pool[(layout == "mf64" ? pad : note - 15) - 1]
            if r == 0 && c == COLS - 1 { lightPad = pad }
            if !setKeycode(0, r, c, kc) { failures += 1; print("  !! (\(r),\(c)) was rejected") }
            entries.append("""
                { "pad": \(pad), "note": \(note), "row": \(r), "col": \(c), "keycode": \(Int(kc)) }
            """)
        }
        print("  row \(r + 1)/10 done")
    }

    let mapJSON = """
    {
      "device": "Keychron C100 8K",
      "vendorId": "0x3434", "productId": "0x042C",
      "layout": "\(layout)",
      "midiChannel": 1,
      "velocity": 127,
      "map": [
    \(entries.joined(separator: ",\n"))
      ],

      "//functionPads": "These pads send no note. Delete this list to get all 100 notes back.",
      "functionPads": [
        { "pad": \(lightPad), "action": "rgb_next", "where": "top-right corner" }
      ],

      "//rgbEffects": "Add e.g. [16, 20] to step through only those effects (0-24).",

      "//colorPerHit": "Shifts the keyboard's colour a little on every hit. RAM only -- the keyboard forgets it at power off. Set enabled to false to turn it off.",
      "colorPerHit": { "enabled": true, "step": 4 }
    }

    """
    let mp = here().appendingPathComponent("keycode_map.json").path
    try? mapJSON.write(toFile: mp, atomically: true, encoding: .utf8)
    print("\nwrote \(mp)")
    print(failures == 0 ? "\nDone. 100/100 keys set." : "\n\(failures) key(s) were rejected -- run install again.")

case "restore":
    guard args.count > 1 else { die("usage: c100setup restore <backup file>") }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: args[1])),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let layers = root["keymap"] as? [[[Int]]] else { die("could not read that backup file") }
    var failures = 0
    print("restoring \(layers.count) layer(s)...")
    for (l, rows) in layers.enumerated() {
        for (r, cols) in rows.enumerated() {
            for (c, kc) in cols.enumerated() where !setKeycode(l, r, c, UInt16(kc)) { failures += 1 }
        }
        print("  layer \(l + 1)/\(layers.count) done")
    }
    print(failures == 0 ? "\nDone. The keyboard is back to how it was." : "\n\(failures) key(s) failed -- run restore again.")

default:
    print("""
    c100setup -- prepare a Keychron C100 8K for MIDI

      c100setup status                          what is on the keyboard now
      c100setup backup [file]                   save the current keymap
      c100setup install [--layout mf64|launchpad]
                                                back up, then set it up for MIDI
      c100setup restore <file>                  put a saved keymap back
    """)
}
