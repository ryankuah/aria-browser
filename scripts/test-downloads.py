#!/usr/bin/env python3
"""Run isolated WebKit download checks on macOS; no user profile is opened."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import os
import platform
import plistlib
import shutil
import subprocess
import tempfile
import threading
from urllib.parse import urlparse


class Fixture(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/attachment")
            self.end_headers()
            return
        status, mime, disposition = 200, "text/html", None
        body = b"<title>Download fixture</title><body>Ready</body>"
        if path in ("/attachment", "/pdf", "/binary", "/inline"):
            mime = "application/pdf" if path == "/pdf" else "text/plain"
            disposition = 'AtTaChMeNt; filename="fixture.txt"'
            body = b"download fixture bytes"
            if path == "/binary":
                mime, disposition = "application/octet-stream", None
            elif path == "/inline":
                disposition = 'inline; filename="attachment.txt"'
        elif path == "/error":
            status, body = 403, b"<title>Verification required</title><body>Verify here</body>"
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        if disposition:
            self.send_header("Content-Disposition", disposition)
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Disposition", 'attachment; filename="form.txt"')
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def main():
    root = Path(__file__).resolve().parents[1]
    server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with tempfile.TemporaryDirectory(prefix="aria-download-check-") as directory:
            work = Path(directory)
            app = work / "DownloadsSmoke.app/Contents"
            (app / "MacOS").mkdir(parents=True)
            (app / "Resources").mkdir()
            with (app / "Info.plist").open("wb") as file:
                plistlib.dump({
                    "CFBundleIdentifier": "com.ryankuah.DownloadsSmoke",
                    "CFBundleExecutable": "DownloadsSmoke",
                    "CFBundlePackageType": "APPL",
                    "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
                }, file)
            shutil.copy(root / "Browser/Resources/video-controls.js", app / "Resources")
            app_source = work / "BrowserAppWithoutMain.swift"
            app_source.write_text((root / "Browser/BrowserApp.swift").read_text().replace("@main\n", "", 1))
            sources = sorted(str(p) for p in (root / "Browser").rglob("*.swift") if p.name != "BrowserApp.swift")
            sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
            binary = app / "MacOS/DownloadsSmoke"
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "6", "-target",
                f"{platform.machine()}-apple-macosx15.0", "-sdk", sdk,
                "-o", str(binary), *sources, str(app_source), str(root / "tests/DownloadsSmoke.swift"),
            ], check=True)
            subprocess.run([str(binary)], check=True, timeout=180, env={
                **os.environ,
                "DOWNLOAD_FIXTURE_URL": f"http://127.0.0.1:{server.server_port}",
                "DOWNLOAD_FIXTURE_DIRECTORY": directory,
            })
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
