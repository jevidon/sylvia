#!/usr/bin/env python3
"""Plain-HTTP control server for the App Transport Security probe (G0.2 part 2).

Binds the given address on an ephemeral port (port 0), writes the port to PORT_FILE, and answers every GET
with a fixed 2-byte body "ok". It exists only so the simulator can show which address forms ATS blocks for
cleartext HTTP; Sylvia itself never uses cleartext to the Mac.

    cleartext-server.py ADDRESS PORT_FILE

The script that starts it kills it when the run ends (sim-sources.sh, g02_stop_all). As a second line of
defense it also exits by itself once its parent process is gone (re-parented), so a run that is killed
without cleaning up never leaves a cleartext listener behind on the LAN or tailnet (review finding R1-03).
"""
import http.server
import os
import socket
import sys
import threading
import time


def exit_when_orphaned(parent: int) -> None:
    while os.getppid() == parent:
        time.sleep(1)
    os._exit(0)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802 (http.server naming)
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, format, *args):  # noqa: A002
        sys.stdout.write("cleartext request %s %s\n" % (self.address_string(), format % args))
        sys.stdout.flush()


class Server(http.server.HTTPServer):
    address_family = socket.AF_INET


class Server6(http.server.HTTPServer):
    address_family = socket.AF_INET6


def main():
    address, port_file = sys.argv[1], sys.argv[2]
    threading.Thread(target=exit_when_orphaned, args=(os.getppid(),), daemon=True).start()
    server_class = Server6 if ":" in address else Server
    server = server_class((address, 0), Handler)
    with open(port_file, "w") as handle:
        handle.write(str(server.server_address[1]))
    server.serve_forever()


if __name__ == "__main__":
    main()
