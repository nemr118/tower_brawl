#!/usr/bin/env python3
"""
Keyboard and mouse input for the Tower Brawl operations deck (v0.0.24).

The story: `rich` only draws. It never reads the keyboard or the mouse. So the
deck reads stdin itself, in raw mode, on a small thread, and turns the bytes
into plain events the deck understands:

    ("key", "q")                     one key: a letter, "+", "-", "left", "right",
                                     "home", "end", "esc", "enter", "up", "down"
    ("wheel", step, ctrl, shift, x, y)   step is -1 (wheel up) or +1 (wheel down);
                                     x, y is the terminal cell under the pointer, 1-based
    ("click", button, x, y)          a mouse button press (0 left, 1 middle, 2 right)

Mouse reporting is the plain xterm protocol: the deck prints ESC[?1000h (send
button presses) and ESC[?1006h (SGR format, so x and y can go past 223). The
terminal then writes ESC[<b;x;yM into stdin for a press and ESC[<b;x;ym for a
release. In b: 0-2 is the button, 64 wheel up, 65 wheel down; +4 Shift, +8 Alt,
+16 Ctrl. Everything is switched back on exit (also on Ctrl+C).

Works without any package. Only used when stdin is a real terminal.
"""
import os
import re
import select
import sys
import threading

MOUSE_ON = "\x1b[?1000h\x1b[?1006h"
MOUSE_OFF = "\x1b[?1006l\x1b[?1000l"
_SGR = re.compile(r"\x1b\[<(\d+);(\d+);(\d+)([Mm])")
_CSI = re.compile(r"\x1b\[(\d*)(?:;(\d+))?([A-Za-z~])")
_SS3 = re.compile(r"\x1bO([A-Za-z])")

_CSI_KEYS = {"A": "up", "B": "down", "C": "right", "D": "left", "H": "home", "F": "end",
             "1~": "home", "4~": "end", "7~": "home", "8~": "end", "5~": "pgup", "6~": "pgdn", "3~": "delete"}
_SS3_KEYS = {"A": "up", "B": "down", "C": "right", "D": "left", "H": "home", "F": "end"}


def parse(buf):
    """Turn raw bytes into (events, leftover). The leftover is an unfinished
    escape sequence to keep for the next read."""
    events = []
    i = 0
    n = len(buf)
    while i < n:
        ch = buf[i]
        if ch != "\x1b":
            if ch in ("\r", "\n"):
                events.append(("key", "enter"))
            elif ch == "\x7f" or ch == "\x08":
                events.append(("key", "backspace"))
            elif ch == "\x03":
                events.append(("key", "ctrl-c"))
            elif ch >= " ":
                events.append(("key", ch))
            i += 1
            continue
        m = _SGR.match(buf, i)
        if m:
            b, x, y, kind = int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4)
            button = b & 3
            shift, alt, ctrl = bool(b & 4), bool(b & 8), bool(b & 16)
            if b & 64:
                events.append(("wheel", -1 if button == 0 else 1, ctrl, shift, x, y))
            elif kind == "M" and not (b & 32):
                events.append(("click", button, x, y))
            i = m.end()
            continue
        m = _CSI.match(buf, i)
        if m:
            key = m.group(1) + m.group(3) if m.group(3) == "~" else m.group(3)
            name = _CSI_KEYS.get(key)
            if name:
                events.append(("key", name))
            i = m.end()
            continue
        m = _SS3.match(buf, i)
        if m:
            name = _SS3_KEYS.get(m.group(1))
            if name:
                events.append(("key", name))
            i = m.end()
            continue
        if i + 1 >= n or (buf[i + 1] in ("[", "O") and n - i < 12):
            # an escape sequence still coming in: keep it for the next read
            return events, buf[i:]
        events.append(("key", "esc"))
        i += 1
    return events, ""


class InputReader:
    """Reads stdin on a thread. `poll()` gives the events since the last call."""

    def __init__(self, mouse=True, stream=None):
        self.stream = stream if stream is not None else sys.stdin
        self.fd = None
        self.mouse = mouse
        self.enabled = False
        self._saved = None
        self._events = []
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread = None

    def start(self):
        try:
            self.fd = self.stream.fileno()
            if not os.isatty(self.fd):
                return self
            import termios
            import tty
            self._saved = termios.tcgetattr(self.fd)
            tty.setcbreak(self.fd)
        except (OSError, ValueError, ImportError):
            return self
        self.enabled = True
        if self.mouse:
            sys.stdout.write(MOUSE_ON)
            sys.stdout.flush()
        self._thread = threading.Thread(target=self._run, daemon=True, name="deck-input")
        self._thread.start()
        return self

    def stop(self):
        self._stop.set()
        if not self.enabled:
            return
        if self.mouse:
            sys.stdout.write(MOUSE_OFF)
            sys.stdout.flush()
        try:
            import termios
            termios.tcsetattr(self.fd, termios.TCSADRAIN, self._saved)
        except (OSError, ValueError, ImportError):
            pass
        self.enabled = False

    def _run(self):
        pending = ""
        while not self._stop.is_set():
            try:
                ready, _, _ = select.select([self.fd], [], [], 0.2)
            except (OSError, ValueError):
                return
            if not ready:
                if pending:                       # a lone ESC key with nothing after it
                    if pending == "\x1b":
                        with self._lock:
                            self._events.append(("key", "esc"))
                    pending = ""
                continue
            try:
                chunk = os.read(self.fd, 256).decode("utf-8", "replace")
            except OSError:
                return
            if not chunk:
                return
            events, pending = parse(pending + chunk)
            with self._lock:
                self._events.extend(events)

    def poll(self):
        with self._lock:
            events, self._events = self._events, []
        return events


if __name__ == "__main__":
    # Self-test of the parser: python tools/deck_input.py
    ev, rest = parse("q+\x1b[A\x1b[D\x1b[H\x1b[F\x1b[1~\x1b[4~\x1bOF\x1b[<64;20;7M\x1b[<80;20;7M\x1b[<69;3;4M\x1b[<0;15;9M\x1b[<0;15;9m\x1b[<32;15;9M\x1b[<")
    want = [("key", "q"), ("key", "+"), ("key", "up"), ("key", "left"), ("key", "home"), ("key", "end"),
            ("key", "home"), ("key", "end"), ("key", "end"),
            ("wheel", -1, False, False, 20, 7), ("wheel", -1, True, False, 20, 7),
            ("wheel", 1, False, True, 3, 4), ("click", 0, 15, 9)]
    assert ev == want, ev
    assert rest == "\x1b[<", repr(rest)
    print("deck_input parser: ok")
