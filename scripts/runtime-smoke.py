#!/usr/bin/env python3
"""Launch the built app on real fixtures and catch startup/preview crashes.
This is process survival coverage; it does not assert pixels or physical hotkeys.
Close other MediaInfo QuickLook instances first to avoid hotkey conflicts.
"""
from pathlib import Path
import subprocess
import time

root = Path(__file__).resolve().parents[1]
app = root / 'dist/MediaInfo QuickLook.app/Contents/MacOS/MediaInfoQuickLook'
fixtures = root / '.build/fixtures'
for names in [['中文 HLG 10bit.mp4'], ['中文 HLG 10bit.mp4', '中文 PQ 10bit.mov', '中文 SDR 8bit.mp4', '中文 未标记.mov', '中文 损坏.mp4']]:
    log = root / '.build' / f'runtime-{len(names)}.log'
    with log.open('w') as stream:
        process = subprocess.Popen([str(app), '--open', *[str(fixtures / name) for name in names]], stdout=stream, stderr=stream)
        try:
            time.sleep(3)
            if process.poll() is not None:
                raise RuntimeError(f'App exited early ({process.returncode}): {log.read_text()}')
            print(f'PASS: native app remained running for {len(names)}-file preview/list startup')
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
