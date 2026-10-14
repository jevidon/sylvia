# M0 threat model evidence (ADR-0015)

Outputs of the commands run for `Docs/ADRs/0015-threat-model.md`. Host: macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.0 (27A266a), Swift 6.4, `/usr/bin/python3` 3.9.6. No simulator or physical device was used. Each log names the commit it ran on.

| File | Command | What it shows |
| --- | --- | --- |
| `audit-self-test.log` | `Scripts/audit-hard-rules.sh self-test` | The audit finds exactly the planted violations (one or more per rule) in a temporary directory under `.build/scratch`, as a plain directory and as a git work tree; lookalikes are not reported; stale and forbidden allowlist entries fail; no credential is printed |
| `audit-repository.log` | `Scripts/audit-hard-rules.sh` | The audit over this branch: findings, allowed hits with their reasons, counts per rule |
| `audit-g04-audio.log` | `git archive 943d5e778de2b58f47343f0e146f9e3ed7baa70e` extracted to `.build/scratch/g04-tree`, then `Scripts/audit-hard-rules.sh --root .build/scratch/g04-tree --allow-stale` | The audit over the G0.4 branch (`m0-g04-audio`, not merged), read with git only |
| `ci-hard-rules.log` | `Scripts/ci.sh hard-rules` after deleting `.build/ci-logs` | The CI drop-in `Scripts/ci.d/13-hard-rules.sh` from clean, with its own copies of the two logs above |
| `protection-key-probe.swift`, `protection-key-probe.log` | `xcrun swiftc -swift-version 6 -o .build/scratch/protprobe/probe protection-key-probe.swift`, then `.build/scratch/protprobe/probe .build/scratch/protprobe/out` | On the macOS host, `setResourceValue(_:forKey: .fileProtectionKey)` accepts a `FileProtectionType` value without error and leaves the class unchanged, while a `URLFileProtection` value changes it (finding TM-F2) |
