#!/usr/bin/env python3
"""Runs the device checklist's "logging source" command line on a pseudo-terminal (G0.2; review finding R3-03).

    logging-source-recipe-check.py SYLVIA_TEST_SOURCE SYLVIA_FETCH WORK_DIR LOG

The checklist starts the Mac source for steps that need a request log with (Docs/Stage0/device-checklists/
G02-Transfer.md, "Before you start"):

    sylvia-test-source --root <folder> --lan --test-log-requests --qr 2>&1 | tee /dev/tty \\
      | sed -l -E 's/(SYLVIA1-|sylvia:\\/\\/pair\\/v1#)[A-Za-z0-9_-]+/[pairing code redacted]/g' > source.log

so the person sees the code, the fingerprint and the approval prompt on the terminal and can answer it, while
source.log gets every line with the code and link redacted, and never the QR code (drawn on /dev/tty only).
This script runs that line (bound to 127.0.0.1 here instead of --lan) under a pseudo-terminal, pairs and
downloads with sylvia-fetch (standing in for the phone), answers "y" on the terminal, and checks both sides.
LOG gets verdicts and counts only; the terminal capture holds the code and is deleted.
"""
import os
import pty
import re
import select
import shlex
import shutil
import subprocess
import sys
import time

REDACT = r"s/(SYLVIA1-|sylvia:\/\/pair\/v1#)[A-Za-z0-9_-]+/[pairing code redacted]/g"
BLOCKS = ("▀", "▄", "█")


class Terminal:
    def __init__(self, fd):
        self.fd = fd
        self.data = b""

    def pump(self, seconds):
        ready, _, _ = select.select([self.fd], [], [], seconds)
        if ready:
            try:
                chunk = os.read(self.fd, 65536)
            except OSError:
                return False
            if not chunk:
                return False
            self.data += chunk
        return True

    def wait_for(self, pattern, seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            match = re.search(pattern, self.data)
            if match:
                return match
            if not self.pump(0.2):
                break
        return re.search(pattern, self.data)


def main():
    test_source, fetch, work, log_path = sys.argv[1:5]
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(os.path.join(work, "library"))
    with open(os.path.join(work, "library", "book.bin"), "wb") as handle:
        handle.write(os.urandom(3 * 1024 * 1024 + 123))
    source_log = os.path.join(work, "source.log")
    pipeline = "%s --root %s --state %s --ephemeral-identity --test-log-requests --qr 2>&1 | tee /dev/tty | sed -l -E %s > %s" % (
        shlex.quote(test_source), shlex.quote(os.path.join(work, "library")), shlex.quote(os.path.join(work, "state")),
        shlex.quote(REDACT), shlex.quote(source_log))
    lines = [
        "environment: host (macOS %s); the checklist's logging-source command line under a pseudo-terminal; sylvia-fetch stands in for the phone"
        % subprocess.run(["sw_vers", "-productVersion"], capture_output=True, text=True).stdout.strip(),
        "command line (as in the checklist, bound to 127.0.0.1 instead of --lan, with --ephemeral-identity): "
        "sylvia-test-source --root <folder> --state <dir> --ephemeral-identity --test-log-requests --qr 2>&1 | tee /dev/tty | sed -l -E '%s' > source.log" % REDACT,
    ]
    failures = []

    def check(name, ok):
        lines.append("  %s: %s" % ("ok" if ok else "FAILED", name))
        if not ok:
            failures.append(name)

    pid, master = pty.fork()
    if pid == 0:
        os.execv("/bin/bash", ["/bin/bash", "-c", pipeline])
    terminal = Terminal(master)
    code = terminal.wait_for(rb"pairing code: (SYLVIA1-[A-Za-z0-9_-]+)\r?\n", 90)  # whole line: output arrives in chunks
    ready = terminal.wait_for(rb"\nready\r?\n", 60)
    fetch_status = None
    prompt = None
    if code and ready:
        out = os.path.join(work, "fetched")
        fetcher = subprocess.Popen([fetch, "--out", out, "--title", "book", "--device-name", "Recipe check"],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        fetcher.stdin.write(code.group(1) + b"\n")
        fetcher.stdin.close()
        prompt = terminal.wait_for(rb"approve\? \[y/N\]", 60)
        if prompt:
            os.write(master, b"y\n")
        deadline = time.monotonic() + 120
        while fetcher.poll() is None and time.monotonic() < deadline:
            terminal.pump(0.2)
        if fetcher.poll() is None:
            fetcher.kill()
        fetch_status = fetcher.wait()
        fetch_output = fetcher.stdout.read().decode("utf-8", errors="replace")
        if fetch_status != 0:
            # sylvia-fetch never prints the code; its last lines say why it stopped.
            lines.append("sylvia-fetch output (last lines): " + " | ".join(fetch_output.strip().splitlines()[-5:]))
        terminal.wait_for(rb"/content range=bytes=", 10)
        time.sleep(0.6)  # the request log is printed every 200 ms
        terminal.pump(0.2)
    os.write(master, b"quit\n")
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline and terminal.pump(0.2):
        pass
    _, status = os.waitpid(pid, 0)
    tty = terminal.data.decode("utf-8", errors="replace")
    with open(source_log, encoding="utf-8", errors="replace") as handle:
        logged = handle.read()

    lines.append("on the terminal (what the person sees and answers):")
    check("the pairing code, unredacted", code is not None)
    check("the approval prompt with the Mac's fingerprint", prompt is not None and "compare with the fingerprint shown on the phone" in tty)
    check("the QR code drawing", sum(1 for line in tty.splitlines() if any(b in line for b in BLOCKS)) >= 20)
    check("the answer \"y\" reached the source (\"approved ...\")", "\napproved " in tty)
    lines.append("sylvia-fetch (stands in for the phone): exit status %s" % fetch_status)
    check("paired and downloaded", fetch_status == 0)
    lines.append("in source.log (what is attached to the step record):")
    check("no pairing code or link (grep -cE 'SYLVIA1-|sylvia://pair/v1#' prints 0)", not re.search(r"SYLVIA1-|sylvia://pair/v1#", logged))
    check("the code and link lines, redacted (%d)" % logged.count("[pairing code redacted]"), logged.count("[pairing code redacted]") == 2)
    check("the approval prompt and the answer", "approve? [y/N]" in logged and "\napproved " in logged)
    content_requests = len(re.findall(r"^request \S+ GET /v1/assets/[0-9a-f-]+/content range=bytes=", logged, re.M))
    check("the request log with timestamps (%d content requests)" % content_requests, content_requests >= 1)
    check("no QR code drawing", not any(b in logged for b in BLOCKS) and "\x1b[" not in logged)
    check("the source stopped on \"quit\"", "\nstopped\n" in logged and os.WIFEXITED(status))

    shutil.rmtree(work, ignore_errors=True)
    lines.append("terminal capture and source.log (the run's code was single use and is spent) deleted: %s" % (not os.path.exists(work)))
    lines.append("RESULT: %s" % ("PASS" if not failures else "FAIL (%s)" % "; ".join(failures)))
    with open(log_path, "w") as handle:
        handle.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
