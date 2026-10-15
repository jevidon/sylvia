#!/usr/bin/env python3
"""Process-kill trial on the simulator (G0.4 review R1-08; plan 10.1 and 19.2: crash position loss at most 5 s).

Run by Scripts/ci.d/60-g04-audio.sh after the tests:

    process_kill_trial.py <simulator udid> <G04AudioHarness.app> <multi-file book dir> <output file>

It installs the harness app, gives it the four-file MP3 book in Documents/G04Book with no saved state, and then,
for each trial: launches the app with `-g04AutoPlay YES` (the harness plays after loading and logs the player's
position every 0.5 s), lets it play, kills the process with SIGKILL (nothing can be written after that), relaunches
it normally and reads the position the relaunched harness loaded from its durable checkpoint. The true position at
the kill is the last logged position plus the wall time from that log line to the kill (playback is at 1x).
The harness plays at 1 % volume unless SYLVIA_AUDIBLE_PLAYBACK=1 in this script's environment: every launch passes
`-g04AudiblePlayback NO` (or YES), which overrides the harness's persisted full-volume toggle, and every launch must
log `output volume=0.01` (or 1.0); the volume does not change the positions measured here.
Exits non-zero if any trial fails or loses more than 5 s, or if a launch did not log the expected output state.
"""
import datetime
import json
import os
import shutil
import signal
import subprocess
import sys
import time

BUNDLE = "com.jevidon.sylvia.spike.g04audio"
PLAY_SECONDS = [7.3, 12.4, 9.6, 4.2]
BUDGET_MS = 5000
# The true position is extrapolated from a log line written up to 0.5 s before the kill; a checkpoint written in
# that interval can be slightly ahead of the extrapolation (output latency, timer jitter).
AHEAD_TOLERANCE_MS = 250
AUDIBLE = os.environ.get("SYLVIA_AUDIBLE_PLAYBACK") == "1"
OUTPUT_ARGS = ["-g04AudiblePlayback", "YES" if AUDIBLE else "NO"]
EXPECTED_OUTPUT = "volume=1.0 preview_volume=1.0 " if AUDIBLE else "volume=0.01 preview_volume=0.01 "


def simctl(*args, check=True):
    """Runs `xcrun simctl` (with DEVELOPER_DIR from Scripts/lib/env.sh); on failure prints its output and exits."""
    result = subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True)
    if check and result.returncode != 0:
        sys.exit(f"simctl {' '.join(args)} failed ({result.returncode}): {result.stderr.strip() or result.stdout.strip()}")
    return result


def parse_time(stamp):
    return datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()


def fields(line):
    """'2026-...Z event k=v k=v' -> (time, event, {k: v})."""
    parts = line.split()
    values = {}
    for p in parts[2:]:
        if "=" in p:
            k, v = p.split("=", 1)
            values[k] = v
    return parse_time(parts[0]), parts[1], values


def main():
    udid, app, book, out_path = sys.argv[1:5]
    simctl("terminate", udid, BUNDLE, check=False)
    simctl("install", udid, app)
    data = simctl("get_app_container", udid, BUNDLE, "data").stdout.strip()
    docs = os.path.join(data, "Documents")
    log_path = os.path.join(docs, "g04-harness.log")
    # Fresh state: no book, no log, no checkpoint or captures from an earlier run.
    shutil.rmtree(os.path.join(docs, "G04Book"), ignore_errors=True)
    shutil.rmtree(os.path.join(data, "Library", "Application Support", "G04Harness"), ignore_errors=True)
    if os.path.exists(log_path):
        os.remove(log_path)
    os.makedirs(os.path.join(docs, "G04Book"))
    members = sorted(f for f in os.listdir(book) if f.endswith(".mp3"))
    for f in members:
        shutil.copy2(os.path.join(book, f), os.path.join(docs, "G04Book", f))

    devices = json.loads(simctl("list", "devices", "-j").stdout)["devices"]
    runtime, model = "unknown runtime", "unknown device"
    for rt, ds in devices.items():
        for d in ds:
            if d["udid"] == udid:
                runtime, model = rt.rsplit(".", 1)[-1], d.get("deviceTypeIdentifier", "").rsplit(".", 1)[-1]

    def log_lines():
        if not os.path.exists(log_path):
            return []
        with open(log_path, encoding="utf-8") as f:
            return [l.rstrip("\n") for l in f if l.strip()]

    def wait_for(start, predicate, timeout):
        deadline = time.time() + timeout
        while time.time() < deadline:
            for line in log_lines()[start:]:
                if predicate(line):
                    return line
            time.sleep(0.1)
        return None

    def launch(*args):
        result = simctl("launch", udid, BUNDLE, *args, *OUTPUT_ARGS)
        return int(result.stdout.strip().rsplit(":", 1)[1])

    rows, failures = [], []
    for trial, play_s in enumerate(PLAY_SECONDS):
        simctl("terminate", udid, BUNDLE, check=False)
        start = len(log_lines())
        pid = launch("-g04AutoPlay", "YES")
        autoplay = wait_for(start, lambda l: " autoplay " in l, 90)
        if autoplay is None or "status=playing" not in autoplay:
            failures.append(f"trial {trial}: harness did not start playing ({autoplay})")
            continue
        _, _, a = fields(autoplay)
        time.sleep(play_s)
        killed_at = time.time()
        os.kill(pid, signal.SIGKILL)
        for _ in range(100):  # wait until the process is gone
            try:
                os.kill(pid, 0)
                time.sleep(0.05)
            except ProcessLookupError:
                break
        positions = [fields(l) for l in log_lines()[start:] if " position " in l]
        positions = [p for p in positions if p[0] <= killed_at and p[2].get("status") == "playing"]
        if not positions:
            failures.append(f"trial {trial}: no position logged while playing")
            continue
        logged_at, _, last = positions[-1]
        truth = int(last["global_ms"]) + int((killed_at - logged_at) * 1000)
        relaunch_start = len(log_lines())
        launch()
        loaded = wait_for(relaunch_start, lambda l: " loaded " in l, 90)
        if loaded is None:
            failures.append(f"trial {trial}: relaunched harness did not load")
            continue
        _, _, r = fields(loaded)
        resumed = int(r["position_ms"])
        loss = truth - resumed
        rows.append((trial, play_s, int(a["position_ms"]), int(last["global_ms"]), killed_at - logged_at, truth, resumed, loss,
                     int(r.get("furthest_ms", "-1"))))
        if loss > BUDGET_MS or loss < -AHEAD_TOLERANCE_MS:
            failures.append(f"trial {trial}: loss {loss} ms")
    simctl("terminate", udid, BUNDLE, check=False)

    # Every launch logged its output state right after `launch`; all must be the expected one.
    lines = log_lines()
    launches = sum(1 for l in lines if " launch " in l)
    outputs = [l for l in lines if " output " in l]
    wrong = [l for l in outputs if EXPECTED_OUTPUT not in l + " "]
    if len(outputs) < launches or wrong or launches == 0:
        failures.append(f"output state: {launches} launches, {len(outputs)} output lines, expected '{EXPECTED_OUTPUT.strip()}', wrong: {wrong[:3]}")

    # How the harness opened the members (its `member` lines at each load): the import's per-file timing mode
    # (ADR-0006 decision 2), estimated timing for these constant-bit-rate MP3 files.
    timings = [fields(l)[2].get("timing", "-") for l in lines if " member " in l]
    if not timings:
        failures.append("the harness logged no member lines (timing mode unknown)")

    losses = [r[7] for r in rows]
    with open(out_path, "w", encoding="utf-8") as out:
        out.write(f"# Process-kill trial: harness app on the simulator {model}, {runtime} (udid {udid}); SIGKILL from the host, then a normal relaunch.\n")
        out.write("# Book: the four-file MP3 book in Documents/G04Book (importer order). Each trial resumes from where the previous relaunch loaded.\n")
        out.write("# true_ms = last position the harness logged while playing + wall time from that log line to the kill (1x); resumed_ms = position the relaunched harness loaded from its durable checkpoint.\n")
        out.write("# members opened as the import decided (the harness's `member` lines, every load): %s\n" % (", ".join(sorted(set(timings))) or "none logged"))
        out.write("trial\tplayed_s\tstarted_ms\tlast_logged_ms\tlog_to_kill_s\ttrue_ms\tresumed_ms\tloss_ms\tfurthest_after_relaunch_ms\n")
        for r in rows:
            out.write("%d\t%.1f\t%d\t%d\t%.3f\t%d\t%d\t%d\t%d\n" % r)
        if losses:
            out.write("loss: n=%d min=%d ms max=%d ms (budget %d ms)\n" % (len(losses), min(losses), max(losses), BUDGET_MS))
        if launches and not wrong and len(outputs) >= launches:
            why = "SYLVIA_AUDIBLE_PLAYBACK=1" if AUDIBLE else "quiet test runs; the volume does not change the positions measured here"
            out.write(f"harness output: {launches} launches, every one logged output {EXPECTED_OUTPUT.strip()} ({why})\n")
        for f in failures:
            out.write(f"FAILED: {f}\n")
    with open(out_path, encoding="utf-8") as f:
        sys.stdout.write(f.read())
    if failures or len(rows) != len(PLAY_SECONDS):
        sys.exit(1)


if __name__ == "__main__":
    main()
