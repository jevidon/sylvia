#!/usr/bin/env python3
"""A deterministic fake OpenAI-compatible server on 127.0.0.1 and an ephemeral port (G0.5 AI spike).

It exists only to dry-run the gated live tests (Tests/LiveProviderTests) end to end, so a person running them
against a real server later knows the test code itself works. It is not a model and proves nothing about any
real provider. Prints "PORT <n>" on stdout once listening; serves until killed.

  POST /v1/chat/completions      -> an SSE chat.completion.chunk stream citing [c1], ending with [DONE]
  POST /v1/audio/transcriptions  -> {"text": ...} (multipart body is read and discarded)
  anything else                  -> 404 with an OpenAI-shaped error body
"""
from __future__ import annotations

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:  # one line per request on stderr, no bodies
        sys.stderr.write("fake-server %s %s\n" % (self.command, self.path))

    def _read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def do_POST(self) -> None:
        body = self._read_body()
        if self.path == "/v1/chat/completions":
            request = json.loads(body or b"{}")
            chunks = [
                {"id": "fake-1", "object": "chat.completion.chunk", "model": request.get("model", "fake"),
                 "choices": [{"index": 0, "delta": {"role": "assistant", "content": "It describes living deliberately "}, "finish_reason": None}]},
                {"id": "fake-1", "object": "chat.completion.chunk",
                 "choices": [{"index": 0, "delta": {"content": "[c1]. OK"}, "finish_reason": "stop"}]},
            ]
            payload = "".join("data: %s\n\n" % json.dumps(chunk) for chunk in chunks) + "data: [DONE]\n\n"
            self._send(200, "text/event-stream", payload.encode())
        elif self.path == "/v1/audio/transcriptions":
            self._send(200, "application/json", json.dumps({"text": "Fake transcript from a loopback test server."}).encode())
        else:
            error = {"error": {"message": "Unexpected endpoint or method. (POST %s)" % self.path, "type": "invalid_request_error"}}
            self._send(404, "application/json", json.dumps(error).encode())

    def _send(self, status: int, content_type: str, payload: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def main() -> None:
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    print("PORT %d" % server.server_address[1], flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
