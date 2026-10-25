#!/usr/bin/env python3
"""The links page for a Tower Brawl night (the ROG's Super+Space "Tower Brawl Server", tools/rog_server.sh).

Writes one HTML page: the links phones and PCs open (the new game and the old one) on
each network this laptop is on, each with a QR code to scan (qrencode), the server's
state (version, the lobby or a match, power-ups, bots, people) and the host page's link.

    python3 tools/rog_links.py --out ~/.cache/tower-brawl/links.html --dash URL
"""
import argparse
import html
import json
import subprocess
import urllib.request

ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
ap.add_argument("--out", required=True)
ap.add_argument("--dash", default="http://100.69.199.3:8088/data/perspective/client/TowerBrawlServer")
ap.add_argument("--host", default="http://127.0.0.1:8092", help="the game server's host port")
ap.add_argument("--port", type=int, default=8443, help="the pages' port")
a = ap.parse_args()

SKIP = ("lo", "tailscale", "docker", "br-", "veth", "virbr")


def addresses():
    """[(interface, ip)] of this laptop's networks (not the tailnet, not docker)."""
    out = subprocess.run(["ip", "-4", "-o", "addr", "show", "scope", "global"], capture_output=True, text=True).stdout
    found = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 4 and not parts[1].startswith(SKIP):
            found.append((parts[1], parts[3].split("/")[0]))
    return found


def qr_svg(text):
    try:
        return subprocess.run(["qrencode", "-t", "SVG", "-m", "2", "-s", "8", "-o", "-", text],
                              capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def state():
    try:
        with urllib.request.urlopen(a.host + "/state", timeout=3) as r:
            return json.loads(r.read())
    except Exception:
        return {}


s = state()
nets = addresses()
if s:
    people = sum(1 for x in s.get("seats", []) if x.get("who") == "person")
    status = (f"Running <b>{html.escape(str(s.get('version', '?')))}</b> · {html.escape(str(s.get('phase_name', '?')).title())}"
              f" · power-ups <b>{'ON' if s.get('powerups', s.get('power_arrows')) else 'OFF'}</b>"
              f" · bots {s.get('bots_wanted', '?')} ({html.escape(str(s.get('bot_level_name', '?')))})"
              f" · people {people}")
    ok = True
else:
    status = "The game server does not answer yet. Give it a few seconds, then open this again (Super+Space, Tower Brawl Server)."
    ok = False
cards = []
for i, (dev, ip) in enumerate(nets):
    url = f"https://{ip}:{a.port}/v2/"
    kind = "Wi-Fi" if dev.startswith("w") else ("cable" if dev.startswith(("e", "en")) else dev)
    cards.append(f"""
  <section class="card">
    <div class="qr">{qr_svg(url)}</div>
    <div class="txt">
      <div class="lbl">Phones and tablets on this {html.escape(kind)} network ({html.escape(dev)})</div>
      <a class="big" href="{url}">{url}</a>
      <div class="sub">The old game: <a href="https://{ip}:{a.port}/play">https://{ip}:{a.port}/play</a></div>
    </div>
  </section>""")
if not cards:
    cards.append('<section class="card"><div class="txt">This laptop is on no network yet: join the Wi-Fi, then open this again.</div></section>')
page = f"""<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tower Brawl links</title>
<style>
  :root {{ color-scheme: dark; }}
  body {{ margin: 0; font-family: system-ui, sans-serif; background: #0f1220; color: #e8ebf5; }}
  main {{ max-width: 980px; margin: 0 auto; padding: 24px 16px 40px; }}
  h1 {{ margin: 0 0 4px; font-size: 34px; color: #ffd36b; letter-spacing: 1px; }}
  .status {{ margin: 0 0 20px; padding: 10px 14px; border-radius: 8px; background: {'#14301c' if ok else '#3a1717'}; border: 1px solid {'#2f7a45' if ok else '#8a2c2c'}; }}
  .card {{ display: flex; gap: 22px; align-items: center; padding: 18px; margin-bottom: 16px; border-radius: 8px; background: #181c30; border: 1px solid #2a3150; }}
  .qr svg {{ width: 200px; height: 200px; background: #fff; border-radius: 6px; display: block; }}
  .lbl {{ font-size: 15px; color: #9aa3c4; margin-bottom: 6px; }}
  .big {{ font-size: 30px; font-weight: 700; color: #7fd1ff; word-break: break-all; }}
  .sub {{ margin-top: 10px; font-size: 16px; color: #b9c0dc; }}
  a {{ color: #7fd1ff; }}
  .note {{ font-size: 15px; color: #9aa3c4; line-height: 1.5; }}
  @media (max-width: 640px) {{ .card {{ flex-direction: column; align-items: flex-start; }} .big {{ font-size: 22px; }} }}
</style></head>
<body><main>
  <h1>TOWER BRAWL</h1>
  <p class="status">{status}</p>
  {''.join(cards)}
  <p class="note">Scan a code with the phone's camera, or type the link. The first time, the phone warns about the
  certificate: tap Advanced, then Proceed. Everyone must be on the same Wi-Fi as this laptop.<br>
  The host page (bots, arena, power-ups, kick, stats): <a href="{a.dash}">{a.dash}</a></p>
</main></body></html>
"""
with open(a.out, "w") as f:
    f.write(page)
print(f"links page: {a.out} ({len(nets)} networks, server {'up' if ok else 'not answering'})")
