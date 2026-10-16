// Diagnostic: enumerate IOHID services and (optionally) log events that reach an
// IOHIDEventSystemClient filter callback.
//
//   swift tools/hid-probe.swift [seconds]
//
// Uses private IOKit API through dlsym so nothing has to be linked specially.
import Foundation
import IOKit
import IOKit.hid

typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
typealias CopyServicesFn = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
typealias ScheduleFn = @convention(c) (CFTypeRef, CFRunLoop, CFString) -> Void
typealias RegisterFilterFn = @convention(c) (CFTypeRef,
                                              @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, CFTypeRef?, CFTypeRef?) -> Int32,
                                              UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Bool
typealias ServiceCopyPropertyFn = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
typealias ServiceRegistryIDFn = @convention(c) (CFTypeRef) -> UInt64
typealias EventGetSenderIDFn = @convention(c) (CFTypeRef) -> UInt64
typealias EventGetTypeFn = @convention(c) (CFTypeRef) -> UInt32

let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)!
func load<T>(_ name: String) -> T {
    guard let symbol = dlsym(handle, name) else {
        FileHandle.standardError.write("missing symbol \(name)\n".data(using: .utf8)!)
        exit(2)
    }
    return unsafeBitCast(symbol, to: T.self)
}

let create: CreateFn = load("IOHIDEventSystemClientCreate")
let copyServices: CopyServicesFn = load("IOHIDEventSystemClientCopyServices")
let schedule: ScheduleFn = load("IOHIDEventSystemClientScheduleWithRunLoop")
let registerFilter: RegisterFilterFn = load("IOHIDEventSystemClientRegisterEventFilterCallback")
let serviceCopyProperty: ServiceCopyPropertyFn = load("IOHIDServiceClientCopyProperty")
let serviceRegistryID: ServiceRegistryIDFn = load("IOHIDServiceClientGetRegistryID")
let eventSenderID: EventGetSenderIDFn = load("IOHIDEventGetSenderID")
let eventGetType: EventGetTypeFn = load("IOHIDEventGetType")

guard let client = create(kCFAllocatorDefault)?.takeRetainedValue() else {
    print("client creation failed")
    exit(1)
}

schedule(client, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue as CFString)

func prop(_ service: CFTypeRef, _ key: String) -> Any? {
    serviceCopyProperty(service, key as CFString)?.takeRetainedValue()
}

print("=== IOHID services ===")
var registryNames: [UInt64: String] = [:]
if let services = copyServices(client)?.takeRetainedValue() as? [CFTypeRef] {
    print("count = \(services.count)")
    for service in services {
        let rid = serviceRegistryID(service)
        let product = prop(service, "Product") as? String ?? "?"
        let transport = prop(service, "Transport") as? String ?? "?"
        let builtIn = prop(service, "BuiltIn") ?? "nil"
        let page = prop(service, "PrimaryUsagePage") ?? "nil"
        let usage = prop(service, "PrimaryUsage") ?? "nil"
        registryNames[rid] = product
        print(String(format: "  rid=0x%llX", rid),
              "product=\(product) transport=\(transport) builtIn=\(builtIn) page=\(page) usage=\(usage)")
    }
} else {
    print("CopyServices returned nothing")
}

// Read-only filter: always pass events through, just report who sent them.
var counts: [UInt64: Int] = [:]
let callback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, CFTypeRef?, CFTypeRef?) -> Int32 = { _, _, sender, event in
    guard let sender, let event else { return 1 }
    let rid = serviceRegistryID(sender)
    counts[rid, default: 0] += 1
    if counts[rid]! <= 3 {
        FileHandle.standardError.write(String(format: "event rid=0x%llX type=%u senderID=0x%llX\n",
                                              rid, eventGetType(event), eventSenderID(event)).data(using: .utf8)!)
    }
    return 1
}

let registered = registerFilter(client, callback, nil, nil)
print("=== filter registration: \(registered) ===")

let seconds = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 8 : 8
print("=== observing for \(seconds)s — touch the trackpad / Touch Bar now ===")
let deadline = Date().addingTimeInterval(seconds)
while Date() < deadline {
    CFRunLoopRunInMode(.defaultMode, 0.25, false)
}

print("=== event counts by service ===")
for (rid, count) in counts.sorted(by: { $0.value > $1.value }) {
    print(String(format: "  0x%llX", rid), "\(count)", registryNames[rid] ?? "(unknown)")
}
