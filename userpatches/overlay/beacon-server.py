#!/usr/bin/env python3
"""Beacon OS control API (no UI). The separate Beacon OS app talks to this.
Needs root (systemctl, nmcli). Set BEACON_TOKEN. Keep BEACON_BIND=127.0.0.1
and expose it with `tailscale serve` for HTTPS."""
import hmac, json, os, subprocess, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

TOKEN = os.environ.get("BEACON_TOKEN", "")
BIND = os.environ.get("BEACON_BIND", "127.0.0.1")
PORT = int(os.environ.get("BEACON_PORT", "8080"))
ORIGIN = os.environ.get("BEACON_ORIGIN", "*")  # set to your app URL to lock it down
HERE = Path(__file__).resolve().parent

LINKS = {"m1": "modem1", "m2": "modem2", "m3": "modem3", "m4": "modem4", "lan": "wan-eth"}
SERVICES = {"enc": "gst-encoder.service", "rist": "rist-sender.service", "ts": "tailscaled.service"}
AUTO_UNITS = ["gst-encoder.service", "rist-sender.service"]
_last = {}  # iface -> (time, rx+tx bytes)


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    except Exception:
        return subprocess.CompletedProcess(cmd, 1, "", "")


def sysfs(iface, name):
    try:
        return (Path("/sys/class/net") / iface / name).read_text().strip()
    except Exception:
        return ""


def nm_connected():
    out = run("nmcli", "-t", "-f", "DEVICE,STATE", "device").stdout
    return {l.split(":")[0] for l in out.splitlines() if l.endswith(":connected")}


def link_state(iface, connected):
    ip = ""
    for line in run("ip", "-4", "-o", "addr", "show", "dev", iface).stdout.splitlines():
        ip = line.split()[3].split("/")[0]
        break
    up = sysfs(iface, "carrier") == "1" and bool(ip)
    total = int(sysfs(iface, "statistics/rx_bytes") or 0) + int(sysfs(iface, "statistics/tx_bytes") or 0)
    now, mbps = time.time(), 0.0
    if iface in _last and now > _last[iface][0]:
        mbps = max(0, (total - _last[iface][1]) * 8 / 1e6 / (now - _last[iface][0]))
    _last[iface] = (now, total)
    return {"on": iface in connected, "up": up, "ip": ip, "mbps": round(mbps, 2)}


def active(unit):
    return run("systemctl", "is-active", unit).stdout.strip() == "active"


def state():
    conn = nm_connected()
    svc = {k: active(u) for k, u in SERVICES.items()}
    svc["auto"] = run("systemctl", "is-enabled", AUTO_UNITS[1]).stdout.strip() == "enabled"
    return {"links": {k: link_state(i, conn) for k, i in LINKS.items()}, "svc": svc}


def toggle(ident, on):
    if ident in LINKS:
        run("nmcli", "device", "connect" if on else "disconnect", LINKS[ident])
    elif ident in SERVICES:
        run("systemctl", "start" if on else "stop", SERVICES[ident])
    elif ident == "auto":
        run("systemctl", "enable" if on else "disable", *AUTO_UNITS)
    else:
        return False
    return True


def live(on):
    if on:  # sender first so the encoder has somewhere to send
        run("systemctl", "start", SERVICES["rist"]); run("systemctl", "start", SERVICES["enc"])
    else:
        run("systemctl", "stop", SERVICES["enc"]); run("systemctl", "stop", SERVICES["rist"])


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", ORIGIN)
        self.end_headers()
        self.wfile.write(data)

    def _authed(self):
        return hmac.compare_digest(self.headers.get("X-Beacon-Token", ""), TOKEN)

    def do_OPTIONS(self):  # CORS preflight from the app
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", ORIGIN)
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Beacon-Token")
        self.send_header("Access-Control-Max-Age", "600")
        self.end_headers()

    def do_GET(self):
        if self.path == "/api/state":
            self._send(200, state()) if self._authed() else self._send(401, {"error": "auth"})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if not self._authed():
            return self._send(401, {"error": "auth"})
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        except ValueError:
            return self._send(400, {"error": "bad json"})
        if self.path == "/api/toggle" and toggle(str(body.get("id")), bool(body.get("on"))):
            self._send(200, {"ok": True})
        elif self.path == "/api/live":
            live(bool(body.get("on"))); self._send(200, {"ok": True})
        else:
            self._send(400, {"error": "bad request"})


if __name__ == "__main__":
    if not TOKEN:
        sys.exit("Set BEACON_TOKEN to a long random string first.")
    ThreadingHTTPServer((BIND, PORT), H).serve_forever()
