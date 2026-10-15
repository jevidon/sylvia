import Foundation

// Host probe for ADR-0015: raw values of the two protection enums, and what setResourceValue does when it is
// given a FileProtectionType (as G0.4's DurableFile does) instead of a URLFileProtection for .fileProtectionKey.
print("FileProtectionType.completeUntilFirstUserAuthentication.rawValue = \(FileProtectionType.completeUntilFirstUserAuthentication.rawValue)")
print("URLFileProtection.completeUntilFirstUserAuthentication.rawValue  = \(URLFileProtection.completeUntilFirstUserAuthentication.rawValue)")
print("FileProtectionType.completeUnlessOpen.rawValue = \(FileProtectionType.completeUnlessOpen.rawValue)")
print("URLFileProtection.completeUnlessOpen.rawValue  = \(URLFileProtection.completeUnlessOpen.rawValue)")

let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
func probe(_ label: String, _ value: Any) {
    let url = dir.appendingPathComponent("probe-\(label)")
    try? FileManager.default.removeItem(at: url)
    FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
    let before = (try? url.resourceValues(forKeys: [.fileProtectionKey]).fileProtection)?.rawValue ?? "nil"
    do {
        try (url as NSURL).setResourceValue(value, forKey: .fileProtectionKey)
        var fresh = url; fresh.removeAllCachedResourceValues()
        let after = (try? fresh.resourceValues(forKeys: [.fileProtectionKey]).fileProtection)?.rawValue ?? "nil"
        print("\(label): before=\(before) setResourceValue=ok after=\(after)")
    } catch {
        print("\(label): before=\(before) setResourceValue threw \(error)")
    }
}
probe("FileProtectionType.completeUnlessOpen", FileProtectionType.completeUnlessOpen)
probe("URLFileProtection.completeUnlessOpen", URLFileProtection.completeUnlessOpen)
probe("FileProtectionType.completeUntilFirstUserAuthentication", FileProtectionType.completeUntilFirstUserAuthentication)
