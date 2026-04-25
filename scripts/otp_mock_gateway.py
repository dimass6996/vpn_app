#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


class OtpHandler(BaseHTTPRequestHandler):
    output_path: Path
    expected_token: str

    def do_POST(self) -> None:  # noqa: N802 (BaseHTTPRequestHandler API)
        if self.path != "/send":
            self._json_response(404, {"error": "not_found"})
            return

        if self.expected_token:
            expected_value = f"Bearer {self.expected_token}"
            if self.headers.get("Authorization", "") != expected_value:
                self._json_response(401, {"error": "unauthorized"})
                return

        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length)
        try:
            payload = json.loads(raw_body.decode("utf-8"))
        except json.JSONDecodeError:
            self._json_response(400, {"error": "invalid_json"})
            return

        login = payload.get("login")
        code = payload.get("code")
        device_id = payload.get("device_id")
        if not login or not code:
            self._json_response(400, {"error": "invalid_payload"})
            return

        current = {}
        if self.output_path.exists():
            try:
                current = json.loads(self.output_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                current = {}

        current[str(login)] = {
            "code": str(code),
            "device_id": str(device_id or ""),
        }
        self.output_path.write_text(
            json.dumps(current, ensure_ascii=True, indent=2),
            encoding="utf-8",
        )
        self._json_response(200, {"accepted": True})

    def do_GET(self) -> None:  # noqa: N802 (BaseHTTPRequestHandler API)
        if self.path == "/health":
            self._json_response(200, {"status": "ok"})
            return
        self._json_response(404, {"error": "not_found"})

    def log_message(self, format: str, *args: object) -> None:
        _ = (format, args)

    def _json_response(self, status_code: int, payload: dict[str, object]) -> None:
        response = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Mock OTP delivery gateway for local smoke tests.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8010)
    parser.add_argument("--out", required=True, help="Path to JSON file where received OTPs are stored.")
    parser.add_argument("--token", default="", help="Optional bearer token expected in Authorization header.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    OtpHandler.output_path = Path(args.out)
    OtpHandler.output_path.parent.mkdir(parents=True, exist_ok=True)
    OtpHandler.output_path.write_text("{}", encoding="utf-8")
    OtpHandler.expected_token = args.token
    server = HTTPServer((args.host, args.port), OtpHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
