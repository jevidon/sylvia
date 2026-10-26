# M0 device fixes: the ATS probe's address (G0.5 AI step 1, runbook 1.3)

Branch `m0-device-fixes-ats`, made from `m0-decisions` at `c72247a6`, which holds the owner's records of 26 October 2026 NZDT. The fix is `907538f5`. It changes only `Spikes/G05-AI/ATSProbe/Tests/ATSProbeTests.swift`. The checks are run by [`commands/run-checks.sh`](commands/run-checks.sh), and their logs are in this folder.

Every run recorded here was on the build Mac (macOS 26.6.2 (25G83), Apple M5 Max, Xcode 27.1 (27A9275)) and on this job's own simulator, Sylvia-M0-devfix-ats (iPhone 17, iOS 26.5). **Nothing here ran on a phone.** None of it is a device result. G0.5 AI row D1 stays as the owner recorded it, failed, until the owner runs runbook 1.3 again.

## 1. What the owner's run showed

The owner ran runbook 1.3 on phone B: iPhone 17 Pro (iPhone18,1), iOS 27.0.1 (24A446), built from `d5336111` (session log row 3d; [`step-01-ats.txt`](../../G05-AI/device/step-01-ats.txt) and [`step-01-ats.log`](../../G05-AI/device/step-01-ats.log)).

- **Private address (10.71.x.x):** the load timed out (URLError -1001) in all three variants (`step-01-ats.log` lines 398, 505 and 604). The probe expects an ATS block in the default variant, and a local refusal (-1004, `cannotConnectToHost`) in `local_networking` and `cidr_exception`.
- **Public IP literal:** blocked by ATS in all three variants.
- **`localhost`:** loaded in all three variants.

## 2. Diagnosis: the probe chose an address that is not on the phone's Wi-Fi

This confirms the orchestrating session's diagnosis 3, with two refinements (below).

**The code.** At `c72247a6`, `hostPrivateIPv4()` (`ATSProbeTests.swift:45-61`, with its comment) returned the first IPv4 address that was up, not loopback, and in 10/8, 172.16/12 or 192.168/16. It took addresses in `getifaddrs` order, from any interface. Its comment shows it was written for the simulator: "This Mac's own private IPv4 address (the simulator shares the host's interfaces). A load to it on a port with no listener is refused by the local kernel if ATS lets it through, so nothing leaves the machine." On a phone, nothing made it prefer Wi-Fi.

**The phone's log.**

- en0 is phone B's Wi-Fi interface: `interface: en0[802.11], ipv4, dns, uses wifi` (`step-01-ats.log:394`).
- Phone B's cellular interface was up as well: `fallback: {interface: pdp_ip0, …}` ([`step-01-ats-initial.log:2571`](../../G05-AI/device/step-01-ats-initial.log)).
- The phone did not refuse the load to 10.71.x.x. In every variant, the load went to iCloud Private Relay over Wi-Fi. On a flow to `mask.icloud.com:443 … interface: en0[802.11]`, the relay answered `Received response code 502 for 10.71.x.x:58688, unreachable through proxy`:
  - `step-01-ats.log:393-394`, then 500-501 and 599-600 for the other two variants;
  - the same in the first attempt: `step-01-ats-initial.log:2364-2365`, 2471-2472 and 2570-2571.

  The request then ran to its 5-second timeout. Apple's page names this kind of traffic as the relay's: "Private Relay protects users’ web browsing in Safari, DNS resolution queries, and insecure http app traffic." ([Prepare your network or web server for iCloud Private Relay](https://developer.apple.com/icloud/prepare-your-network-for-icloud-private-relay/), read 26 October 2026.)
- On the simulator, the same test loads the Mac's own LAN address (en0's, in this job's run), and the Mac refuses it at once (-1004) in all three variants. This held in the G0.5 run ([`simulator-ats-keychain-probe.log`](../../G05-AI/simulator-ats-keychain-probe.log)) and in this job's run ([`simulator-probe-test.log`](simulator-probe-test.log)).

So 10.71.x.x was not phone B's Wi-Fi address but a private address on another of its interfaces. If that interface is cellular or a VPN tunnel (refinement 1), it is no local network at all: "A local network is an IP network associated with a broadcast-capable network interface. Such interfaces include Wi-Fi and Ethernet, but not cellular (WWAN) or VPN." ([TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), read 26 October 2026.)

**Refinements.**

1. **The interface is not named.** No log says which interface held 10.71.x.x. The cellular interface is the likelier one, since the log shows it up. A tunnel (utun\*, ipsec\*) is also possible. The re-run's new `private-ipv4-interfaces=` line will name it.
2. **The load went to Private Relay, not to the phone's own network stack.** The phone did not refuse the load: it handed the destination address and port to Apple's relay, which could not reach them (502). So the old comment's "nothing leaves the machine" did not hold on a phone. The probe's request reached no server: `#expect(server.requests.isEmpty)` held. In each variant, the test's one issue was its ATS or refusal expectation. What the request did during the rest of the five seconds is not in the log.

## 3. The fix (`907538f5`)

All changes are in `Spikes/G05-AI/ATSProbe/Tests/ATSProbeTests.swift`.

- **Choosing the address.** `privateIPv4Addresses()` lists every private IPv4 address with its interface's name, using the old function's filters unchanged. `probeAddress(from:onDevice:)` chooses the address to load:
  - **Simulator:** the first address of any interface, as before. This is the Mac's own address; in this job's runs, en0 held the Mac's only private address.
  - **Device:** the address of the Wi-Fi interface, en0, and nothing else. It never takes the address of a cellular (pdp_ip\*), tunnel (utun\*, ipsec\*) or other interface.
- **Logging.** Each variant now logs two lines:
  - `ATS-PROBE variant=<variant> private-ipv4-interfaces=<interface>:<a.b>.x.x,… rule=device: en0 (Wi-Fi) only` (on the simulator, the rule reads `rule=simulator: the first of any interface`);
  - the result line, which now names the interface: `ATS-PROBE variant=<variant> private-ip=<a.b>.x.x interface=en0 result=…`.
- **No Wi-Fi address.** If en0 has no private address, the test loads nothing and stops at its precondition, not at an ATS result. It logs `ATS-PROBE variant=<variant> private-ip=none precondition-not-met (ATS not probed; not an ATS result): the phone needs a private IPv4 address (10/8, 172.16/12 or 192.168/16) on its Wi-Fi interface, en0: join such a Wi-Fi network and run again`. It then fails at its `#require` with "precondition not met, so ATS was not probed (not an ATS result): …".
- **New test.** `onADeviceOnlyTheWiFiAddressIsProbed()` checks the choice on made-up interface lists: cellular, tunnel, IPsec, a second Ethernet interface and en0, in either order. It runs in every variant, on the simulator and on a phone. Each variant's run now has 14 tests (13 before): 42 in the three hosted bundles (39 before), besides the UI test.
- **Unchanged:**
  - every variant's expectations, including the default variant's device expectation of Apple's documented block (now at `ATSProbeTests.swift:164`; a comment there records that the first device run was not blocked);
  - every other test;
  - `project.yml` and the Info.plists (no ATS key changed);
  - `EndpointPolicy`;
  - Codex's `Spikes/G05-Recovery/DeviceTests` files.

## 4. Checks run here (build Mac and simulator; not a phone)

`commands/run-checks.sh` ran steps 1-3 from clean on `0b0e1e65`, with no uncommitted file. It first deleted the spike's build products. `commands/run-checks.sh audit` ran step 4 after this README was written.

| Step | What ran | Result | Log |
| --- | --- | --- | --- |
| 1 | The probe's scheme for a generic iOS device: `xcodebuild build-for-testing`, unsigned, build only. The fix's device branch compiles only for a device; the fix changes no signing setting, and this job uses no signing identity. | As expected. `** TEST BUILD SUCCEEDED **`, 0 errors. `ATSProbeTests.swift` compiled for arm64 in all three test targets. No warning in `Spikes/G05-AI` code: the build's 11 warnings are Xcode's AppIntents metadata notices, plus the three probe apps' interface-orientation warning, which the owner's device build also has (`step-01-ats.log:201`, 361 and 366). | [`device-build-for-testing.log`](device-build-for-testing.log) |
| 2 | The probe's tests in each variant on the simulator: the checklist's step 1 command with the simulator as destination and no signing flags, as the G0.5 AI drop-in runs it | As expected. Each variant: `✔ Test run with 14 tests in 2 suites passed`, `private-ipv4-interfaces=en0:192.168.x.x rule=simulator: the first of any interface`, and `private-ip=192.168.x.x interface=en0 result=URLError -1004 classified=host_unreachable`, as in the G0.5 run. The public IP literal was blocked (-1022) and `localhost` loaded in each variant. The suspension UI test passed: `** TEST SUCCEEDED **`. | [`simulator-probe-test.log`](simulator-probe-test.log) |
| 3 | `Scripts/ci.sh g05-ai hard-rules`: the Git LFS check, the hard-rules audit, and the whole G0.5 AI drop-in (host build and tests, the live-test dry run, the contracts, the simulator package tests and the probe again) | As expected: `all 3 steps passed`. The audit reported `PASS (0 finding(s), 49 allowed, 0 stale allowlist entries, 0 allowlist error(s))`. The drop-in reported 250 host tests, 250 simulator package tests and 42 probe tests (14 in each variant), with the same `ATS-PROBE` lines as step 2. | [`ci-run.log`](ci-run.log), [`ci-70-g05-ai-sim-probe-test.log`](ci-70-g05-ai-sim-probe-test.log) |
| 4 | `Scripts/ci.sh hard-rules` again, after this README and the logs were written | See the log's last line: `# result: as expected` with `all 2 steps passed`, and the audit's `PASS` line. | [`ci-hard-rules-final.log`](ci-hard-rules-final.log) |

These checks show three things: the simulator still chooses the same address, every expectation is unchanged, and the device code builds. They cannot show what a phone does with its Wi-Fi address; only the owner's re-run can.

An earlier run at `e5e1cede` reported step 2 as not as expected, although all its tests had passed. Its check looked for an address with four numeric octets, while the probe prints the address masked. `0b0e1e65` corrected the check; the logs here come from the run that followed it.

## 5. What the owner's re-run of 1.3 should show

Run runbook 1.3 as written, from a commit that holds `907538f5`.

**Before the run:**

- Phone B is on Wi-Fi with a private IPv4 address (10/8, 172.16/12 or 192.168/16; Settings › Wi-Fi › the network › IP Address).
- Local Network is on for "ATS default", "ATS local" and "ATS CIDR" (Settings › Privacy & Security › Local Network).

The load now goes to an address on the phone's local network. TN3179 says: "Outgoing traffic to a local network address requires local network access." It does not say whether a load to the phone's own address counts. It also warns that a load may be denied while the alert is showing: "If the system presents a local network alert in response to one of your local network operations, it may deny the operation immediately, before the user has responded to the alert." If an alert appears, allow it and run the command again, as 1.3 says.

**Expected in each variant.** These are the probe's expectations, unchanged since `d5336111`:

| Variant | `private-ip` line | `plainHTTPToAPrivateLANAddress()` | The variant's run |
| --- | --- | --- | --- |
| `default` (no ATS key) | `private-ip=<a.b>.x.x interface=en0 result=URLError -1004 …`, if ATS lets the load through, as in the first run, and the phone refuses it, as the Mac does for the simulator | Fails at `ATSProbeTests.swift:164`: "documented iOS 17+ behaviour: ATS blocks cleartext to an IP literal without an exception". This failure is the device finding and is recorded as such (section 6). | `✘ Test run with 14 tests in 2 suites failed … with 1 issue` |
| `local_networking` | `private-ip=<a.b>.x.x interface=en0 result=URLError -1004 …` | Passes: ATS does not block the load, and the phone refuses it. | `✔ Test run with 14 tests in 2 suites passed` |
| `cidr_exception` | The same | Passes | `✔ Test run with 14 tests in 2 suites passed` |

On the simulator, the `classified=` value after -1004 is `host_unreachable`. If the default variant shows -1022 instead, ATS blocked the Wi-Fi address and the test passes. Record that: it differs from the first run, which was not blocked (section 6).

- **The address** is the phone's own Wi-Fi address: 192.168.x.x if the phone is on the Mac's network.
- **The new line.** Before each `private-ip` line, a `private-ipv4-interfaces=` line lists every interface with a private address. It should name en0 and the interface that held 10.71.x.x. Record it: it settles which interface the first run used.
- **Everything else is as in the first run:**
  - `public-ip=192.0.2.1 result=URLError -1022 ats-blocked=true` in all three variants (the first run's file shows it masked, as 192.0.x.x);
  - `localhost=success(200)` in all three;
  - `plainHTTPToAnotherDeviceOnTheLAN()` skipped;
  - the suspension UI test, which is step 4's.
- **Record** what 1.3 says, plus the three `private-ipv4-interfaces=` lines.

**Results that are not ATS results:**

| Result | Meaning | What to do |
| --- | --- | --- |
| `private-ip=none precondition-not-met …` | en0 had no private address. | Join a Wi-Fi network that gives one, and run again. |
| `classified=local_network_permission_denied` | Local Network was off for that app, or its alert denied the first load. | Turn Local Network on (or allow the alert), and run again. |
| -1001 again, with a `[privacy_proxy] … for <a.b>.x.x:…` line for the Wi-Fi address | Private Relay carried the load to the phone's own address, so the address was not the whole cause. | Record it and ask an agent. |
| Any other result | Not foreseen here. | Record it and ask an agent. |

## 6. The default variant has already answered its question

**The question.** The default variant has no ATS key. It asks whether ATS on the phone blocks cleartext HTTP to a private IP literal. Apple documents that it does from iOS 17: "In iOS 17, iPadOS 17, and macOS 14, ATS no longer allows connections to IP addresses by default." ([NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking), Discussion, read 26 October 2026.)

**The answer.** The first run answered it, though with the wrong address: ATS did not block the load.

- When ATS blocks a load, the phone logs `Cannot start load of Task <…> since it does not conform to ATS policy`, and the load fails at once with -1022.
- In each variant, that line appears for the public IP literal and for the qualified name (`step-01-ats.log:416` and 424, 515 and 523, 614 and 622). It never appears for the private address.
- Instead, the private-address load started a connection, to Private Relay (393-394), and ended at its timeout.

So on iOS 27.0.1 (24A446), ATS let cleartext HTTP to a private IP literal through without an exception. The iOS 26.5 simulator did the same (finding F1 in `Docs/Stage0/G05-AI.md`).

**What follows:**

- This agrees with decision D-9 (b), which makes Sylvia's own `EndpointPolicy` the cleartext gate on every OS version.
- The reading assumes that ATS judges the URL's host (an IP literal), not the route to it. The re-run's default line, for the Wi-Fi address, will show that directly.
- The default variant's device expectation stays Apple's documented behaviour. The phone's contrary behaviour is therefore recorded as a failure of it, not edited away.

## 7. Left to the records

This branch changes only the ATS probe's test file, its own commands and this folder. The owner's records, the runbook, the device checklists, the gate report and summary, the integration log and the Stage 0 README are as committed. Another run updates them on `m0-records-update`. This branch asks that run to describe in 1.3 and checklist step 1:

- the new interface field and line;
- the precondition;
- the 14 tests per variant;
- the expected re-run results above;
- a pointer from row D1 to this folder.
