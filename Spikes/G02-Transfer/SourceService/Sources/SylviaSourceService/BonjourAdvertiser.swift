import Foundation
import Synchronization
import dnssd

/// Advertises the source on the local network with DNS-SD (plan 15.1). The service type is
/// product-specific; the TXT record carries only the protocol major version and the source ID (no
/// library data, no user name). An advertisement is untrusted input to the phone: it is only a hint
/// where to connect, and the SPKI pin decides trust.
public final class BonjourAdvertiser: Sendable {
    public static let serviceType = "_sylvia-src._tcp"

    /// The registration's DNSServiceRef, kept as its bit pattern so the class stays Sendable without
    /// unchecked conformances; it is only used on `queue` and when deallocating.
    private let reference = Mutex<Int>(0)
    private let queue = DispatchQueue(label: "SylviaSourceService.bonjour")

    public init() {}

    /// Registers `name` on `port` in the default domain. Returns the DNS-SD error code (0 on success).
    /// `localOnly` registers on this Mac only (kDNSServiceInterfaceIndexLocalOnly): used when the service
    /// is bound to loopback, so the network never sees an advertisement for a port it cannot reach.
    @discardableResult
    public func start(name: String, port: Int, sourceID: String, protocolMajor: Int, localOnly: Bool) -> Int32 {
        var txt = [UInt8]()
        for entry in ["pv=\(protocolMajor)", "sid=\(sourceID)"] {
            let bytes = Array(entry.utf8)
            txt.append(UInt8(bytes.count))
            txt.append(contentsOf: bytes)
        }
        var ref: DNSServiceRef?
        let error = txt.withUnsafeBytes { buffer in
            DNSServiceRegister(
                &ref, 0, localOnly ? kDNSServiceInterfaceIndexLocalOnly : 0, name, Self.serviceType, nil, nil, UInt16(port).bigEndian, UInt16(buffer.count),
                buffer.baseAddress, nil, nil)
        }
        guard error == kDNSServiceErr_NoError, let ref else { return error }
        DNSServiceSetDispatchQueue(ref, queue)
        reference.withLock { $0 = Int(bitPattern: ref) }
        return error
    }

    public func stop() {
        let bits = reference.withLock { stored -> Int in
            defer { stored = 0 }
            return stored
        }
        guard let ref = DNSServiceRef(bitPattern: bits) else { return }
        queue.sync { DNSServiceRefDeallocate(ref) }
    }

    deinit { stop() }
}
