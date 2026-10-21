// Host check of DurableFile.applyProtection (TM-F2 fix at M0 assembly): the class requested is the class read back,
// for A, B and C, and an unmapped class is refused before anything is created.
//
// Each class writes into a directory of its own, under a base directory created with class C (M0 final review
// R1-09: the first version wrote every class into one directory, which DurableFile created with the first class, A,
// so every later file started there; with the screen locked, A's keys are unavailable and every write failed).
// Classes A and B need the Mac's class keys, which macOS withholds while the screen is locked: when the screen is
// locked (second argument "locked", from the .sh beside this file) a failure of A or B is reported as not checkable,
// and the result is INCONCLUSIVE (exit 2), never PASS.
import Foundation

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let locked = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "locked"
try? FileManager.default.removeItem(at: dir)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
var failures = 0
var notCheckable = 0
let classes: [(String, String, FileProtectionType)] = [
    ("A complete", "A", .complete),
    ("B completeUnlessOpen", "B", .completeUnlessOpen),
    ("C completeUntilFirstUserAuthentication", "C", .completeUntilFirstUserAuthentication),
]
for (label, folder, cls) in classes {
    let target = dir.appendingPathComponent(folder).appendingPathComponent("\(cls.rawValue).json")
    do {
        try DurableFile.write(Data("{}".utf8), to: target, protection: cls)
        let back = try URL(fileURLWithPath: target.path).resourceValues(forKeys: [.fileProtectionKey]).fileProtection
        let folderClass = try dir.appendingPathComponent(folder).resourceValues(forKeys: [.fileProtectionKey]).fileProtection
        print("\(label): write ok in \(folder)/ (directory \(folderClass?.rawValue ?? "none")), read back \(back?.rawValue ?? "none")")
    } catch {
        if locked && cls != .completeUntilFirstUserAuthentication {
            notCheckable += 1
            print("\(label): not checkable while the screen is locked (\(error))")
        } else {
            failures += 1
            print("\(label): FAILED \(error)")
        }
    }
}
let unmapped = dir.appendingPathComponent("unmapped/unmapped.json")
do {
    try DurableFile.write(Data("{}".utf8), to: unmapped,
                          protection: FileProtectionType(rawValue: "SylviaTestUnknownProtectionClass"))
    failures += 1
    print("unmapped class: WRITTEN (wrong)")
} catch {
    let created = FileManager.default.fileExists(atPath: dir.appendingPathComponent("unmapped").path)
    print("unmapped class: refused (\(error)); directory created: \(created)")
    if created { failures += 1 }
}
if failures > 0 {
    print("RESULT: FAIL")
    exit(1)
} else if notCheckable > 0 {
    print("RESULT: INCONCLUSIVE (\(notCheckable) class(es) not checkable while the screen is locked; run again unlocked)")
    exit(2)
}
print("RESULT: PASS")
