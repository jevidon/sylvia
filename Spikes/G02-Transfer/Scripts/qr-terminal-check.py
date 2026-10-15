#!/usr/bin/env python3
"""Checks where `sylvia-source --qr` draws the pairing QR code (G0.2; round 3 review gate gap).

    qr-terminal-check.py SYLVIA_SOURCE WORK_DIR LOG

The QR code carries the invitation secret, like the code and link. The source draws it only on its controlling
terminal (/dev/tty), never on standard output, so output redirected into a file or a log never holds it.

Run 1: the source runs on a pseudo-terminal (its controlling terminal) with standard output redirected to a file.
  Expected: the QR drawing (half-block lines, black on white) appears on the terminal and not in the file; the
  file has the code line and "qr: drawn on the terminal only".
Run 2: the source runs in a new session without a controlling terminal, standard output to a file.
  Expected: no drawing anywhere; the file says "qr: not drawn: no controlling terminal".

LOG gets counts and verdicts only. The captured terminal and output files hold a pairing code, so they stay in
WORK_DIR and are deleted at the end; the invitations expire after one minute and are never presented.
"""
import os
import pty
import select
import shutil
import subprocess
import sys
import time

BLOCKS = ("▀", "▄", "█")
ANSI_BLACK_ON_WHITE = "\x1b[30;47m"


def read_until(fd, needle, seconds):
    data = b""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if not ready:
            if needle is not None and needle in data:
                return data, True
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        data += chunk
        if needle is not None and needle in data:
            return data, True
    return data, needle is not None and needle in data


def wait_for_file_text(path, needle, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                if needle in handle.read():
                    return True
        except FileNotFoundError:
            pass
        time.sleep(0.1)
    return False


def drawing_lines(text):
    return [line for line in text.splitlines() if ANSI_BLACK_ON_WHITE in line and any(b in line for b in BLOCKS)]


def main():
    source, work, log_path = sys.argv[1], sys.argv[2], sys.argv[3]
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(os.path.join(work, "library"))
    with open(os.path.join(work, "library", "book.bin"), "wb") as handle:
        handle.write(b"sylvia qr check\n")
    common = ["--root", os.path.join(work, "library"), "--ephemeral-identity", "--qr", "--invitation-minutes", "1"]
    lines = [
        "environment: host (macOS %s); %s" % (subprocess.run(["sw_vers", "-productVersion"], capture_output=True, text=True).stdout.strip(),
                                            os.path.basename(source)),
        "command: qr-terminal-check.py <sylvia-source> <work> <log> (Spikes/G02-Transfer/Scripts); source options: --ephemeral-identity --qr --invitation-minutes 1",
    ]
    failures = []

    # Run 1: controlling terminal = a pseudo-terminal; standard output redirected to a file.
    out1 = os.path.join(work, "run1-stdout.txt")
    pid, master = pty.fork()
    if pid == 0:
        fd = os.open(out1, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        os.dup2(fd, 1)
        os.execv(source, [source] + common + ["--state", os.path.join(work, "state1")])
    terminal, drawn = read_until(master, b"terminal columns", 60)
    ready = wait_for_file_text(out1, "\nready\n", 60)
    os.write(master, b"quit\n")
    rest, _ = read_until(master, None, 5)
    terminal += rest
    _, status = os.waitpid(pid, 0)
    tty_text = terminal.decode("utf-8", errors="replace")
    with open(out1, encoding="utf-8", errors="replace") as handle:
        out_text = handle.read()
    tty_drawing = drawing_lines(tty_text)
    out_drawing = drawing_lines(out_text) + [line for line in out_text.splitlines() if any(b in line for b in BLOCKS)]
    checks1 = {
        "source became ready": ready,
        "QR drawing on the terminal (%d lines)" % len(tty_drawing): drawn and len(tty_drawing) >= 20,
        "no QR drawing and no block character in standard output": not out_drawing and ANSI_BLACK_ON_WHITE not in out_text,
        "standard output has the code line": "pairing code: SYLVIA1-" in out_text,
        "standard output says \"qr: drawn on the terminal only\"": "qr: drawn on the terminal only" in out_text,
        "the code line is not on the terminal": "SYLVIA1-" not in tty_text,
        "exited after quit": os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0,
    }
    lines.append("run 1: controlling terminal = pseudo-terminal, standard output redirected to a file")
    for name, ok in checks1.items():
        lines.append("  %s: %s" % ("ok" if ok else "FAILED", name))
        if not ok:
            failures.append("run 1: " + name)

    # Run 2: no controlling terminal (new session), standard output to a file.
    out2 = os.path.join(work, "run2-stdout.txt")
    with open(out2, "w") as handle:
        process = subprocess.Popen(
            [source] + common + ["--state", os.path.join(work, "state2")], stdin=subprocess.PIPE, stdout=handle,
            stderr=subprocess.STDOUT, start_new_session=True)
    ready2 = wait_for_file_text(out2, "\nready\n", 60)
    process.stdin.write(b"quit\n")
    process.stdin.flush()
    try:
        code2 = process.wait(timeout=30)
    except subprocess.TimeoutExpired:
        process.kill()
        code2 = -1
    with open(out2, encoding="utf-8", errors="replace") as handle:
        out2_text = handle.read()
    checks2 = {
        "source became ready": ready2,
        "standard output says \"qr: not drawn: no controlling terminal\"": "qr: not drawn: no controlling terminal" in out2_text,
        "no QR drawing and no block character in standard output": ANSI_BLACK_ON_WHITE not in out2_text and not any(b in out2_text for b in BLOCKS),
        "exited after quit": code2 == 0,
    }
    lines.append("run 2: no controlling terminal (new session), standard output to a file")
    for name, ok in checks2.items():
        lines.append("  %s: %s" % ("ok" if ok else "FAILED", name))
        if not ok:
            failures.append("run 2: " + name)

    shutil.rmtree(work, ignore_errors=True)
    lines.append("captured terminal and output files (they hold pairing codes) deleted: %s" % (not os.path.exists(work)))
    lines.append("RESULT: %s" % ("PASS" if not failures else "FAIL (%s)" % "; ".join(failures)))
    with open(log_path, "w") as handle:
        handle.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
