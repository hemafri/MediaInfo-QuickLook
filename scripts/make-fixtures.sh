#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
FFMPEG="${FFMPEG:-/opt/homebrew/bin/ffmpeg}"
OUT=".build/fixtures"
mkdir -p "$OUT"
"$FFMPEG" -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=320x180:rate=30000/1001:duration=0.3' -an -c:v libx265 -preset ultrafast -x265-params 'log-level=error:pools=1:colorprim=9:transfer=18:colormatrix=9' -pix_fmt yuv420p10le -color_primaries bt2020 -color_trc arib-std-b67 -colorspace bt2020nc -tag:v hvc1 "$OUT/中文 HLG 10bit.mp4"
"$FFMPEG" -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=0.3' -an -c:v libx265 -preset ultrafast -x265-params 'log-level=error:pools=1:colorprim=9:transfer=16:colormatrix=9' -pix_fmt yuv420p10le -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc -tag:v hvc1 "$OUT/中文 PQ 10bit.mov"
"$FFMPEG" -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=320x180:rate=25:duration=0.3' -an -c:v libx264 -preset ultrafast -pix_fmt yuv420p -x264-params 'colorprim=bt709:transfer=bt709:colormatrix=bt709' -color_primaries bt709 -color_trc bt709 -colorspace bt709 "$OUT/中文 SDR 8bit.mp4"
"$FFMPEG" -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=320x180:rate=30:duration=0.3' -an -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$OUT/中文 未标记.mov"
printf 'this is not a valid video\n' > "$OUT/中文 损坏.mp4"
printf 'Created four tagged/untagged synthetic videos and one corrupt file in %s\n' "$OUT"
