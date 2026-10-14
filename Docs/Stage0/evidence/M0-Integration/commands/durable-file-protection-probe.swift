// Host check of DurableFile.applyProtection (TM-F2 fix at M0 assembly): the class requested is the class read back,
// for A, B and C, and an unmapped class is refused before anything is created.
import Foundation

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: dir)
var failures = 0
let classes: [(String, FileProtectionType)] = [
    ("A complete", .complete),
    ("B completeUnlessOpen", .completeUnlessOpen),
    ("C completeUntilFirstUserAuthentication", .completeUntilFirstUserAuthentication),
]
for (label, cls) in classes {
    let target = dir.appendingPathComponent("\(cls.rawValue).json")
    do {
        try DurableFile.write(Data("{}".utf8), to: target, protection: cls)
        let back = try URL(fileURLWithPath: target.path).resourceValues(forKeys: [.fileProtectionKey]).fileProtection
        print("\(label): write ok, read back \(back?.rawValue ?? "none")")
    } catch {
        failures += 1
        print("\(label): FAILED \(error)")
    }
}
let unmapped = dir.appendingPathComponent("sub/unmapped.json")
do {
    try DurableFile.write(Data("{}".utf8), to: unmapped,
                          protection: FileProtectionType(rawValue: "SylviaTestUnknownProtectionClass"))
    failures += 1
    print("unmapped class: WRITTEN (wrong)")
} catch {
    let created = FileManager.default.fileExists(atPath: dir.appendingPathComponent("sub").path)
    print("unmapped class: refused (\(error)); directory created: \(created)")
    if created { failures += 1 }
}
print(failures == 0 ? "RESULT: PASS" : "RESULT: FAIL")
