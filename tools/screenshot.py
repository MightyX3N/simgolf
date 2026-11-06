#!/usr/bin/env python3
"""Build the LÖVE version and save a screenshot of the course view, without opening a window for long.

    python tools/screenshot.py out.png [--view X,Z,ZOOM,ROT] [--seed 7] [--slot N] [--sandbox] [--demo]

Needs LÖVE 11.4+ (`love` on the PATH). On Linux without a display it runs under xvfb-run (package xvfb).
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main(argv) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    out = Path(argv[1]).resolve()
    extra = argv[2:]

    subprocess.run([sys.executable, str(ROOT / "tools" / "build.py"), "love"], check=True)

    love = shutil.which("love")
    if not love:
        print("love not found on the PATH", file=sys.stderr)
        return 1
    cmd = [love, str(ROOT / "dist" / "love"), "--screenshot", str(out), *extra]
    if sys.platform.startswith("linux") and not os.environ.get("DISPLAY") and shutil.which("xvfb-run"):
        cmd = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24", *cmd]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    for line in result.stdout.splitlines():
        if line.startswith("[simgolf]") or line.startswith("screenshot:"):
            print(line)
    if not out.exists():
        print(result.stderr[-2000:], file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
