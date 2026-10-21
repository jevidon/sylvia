# The M0 final fix's second round: evidence

Logs and commands of the round recorded in `Docs/Stage0/integration-log.md` section 12 (19 and 20 October 2026). Each log names the command in `commands/` that wrote it.

## Two names that say the opposite of what their run showed

*(Added on 20 October 2026, at the toolchain re-pin round: M0 final review round 3, R7-06.)*

`ci-71-g05-recovery-locked.log`, written by `commands/ci-71-allow-missing-class-b.sh`, is the evidence that the class-B readback of G0.5 recovery's report row 10 holds on the code the M0 final fix changed, and that runbook step 0.8 is done for it. Both names were chosen before the run, for the state of every earlier run of that code: the Mac's screen had been locked, the drop-in's class-B tests skip while it is, and its row-10 guard then stops the drop-in after its host tests. The script therefore sets `G05_ALLOW_MISSING_CLASS_B=1`, which turns that stop into a printed "row 10 evidence missing" warning, so that the drop-in's other steps would run whatever the lock state.

The run itself found the screen unlocked, at its start and at its end (the log's two `screen lock (ioreg)` lines: `IOConsoleLocked=False CGSSessionScreenIsLocked=False`). So the class-B tests ran, the guard found their lines and printed `row 10 evidence present`, the relaxed guard was never used, and the drop-in passed every step: class B read back on 53 files and directories, and the SQLite files class B (`g05-recovery/host-tests.log`). Read the log as "G0.5 recovery from clean, with the class-B readback", whatever its name says. The files keep their names because the gate summary, the reports, the ADRs and the integration log cite them by name.
