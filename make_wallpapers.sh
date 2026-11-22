#!/usr/bin/env bash
# Download the james.sh gallery videos and prep them as iPhone
# wallpaper clips (portrait, short, H.264 .mp4, no audio).
#
# Two variants are written per video:
#   wallpapers/crop/NAME.mp4  full-bleed; cropped to portrait around the
#                             subject (loses ~2/3 of the artwork's width)
#   wallpapers/fit/NAME.mp4   whole artwork at full width, floating on a
#                             blurred, darkened copy of itself
#
# Requires: curl, ffmpeg, ffprobe  (macOS: brew install ffmpeg)
# Usage:    bash make_wallpapers.sh
# Tunables: MIN_SECS=3 W=1290 H=2796 CRF=20 bash make_wallpapers.sh
set -euo pipefail

MIN_SECS="${MIN_SECS:-3}"  # sources are 1.4-5.7s loops; short ones are
                           # repeated whole until at least this long
W="${W:-1290}"             # 1290x2796 = Pro Max / Plus
H="${H:-2796}"             # 1179x2556 = Pro / base
CRF="${CRF:-20}"           # libx264 quality  (lower = bigger/better)
BASE="${BASE:-https://www.james.sh/images}"
SRC="${SRC:-james-src}"
OUT="${OUT:-wallpapers}"

# name:focus -- focus is the horizontal centre of the portrait crop as a
# fraction of the source width (0 = left edge, 0.5 = centre, 1 = right).
CLIPS=(
  drinking-leopard:0.52 rolling-hills:0.55 glovewort:0.42 star-door:0.50
  leaky-bucket:0.55 night-islands:0.45 giant-cat:0.60 chillhop:0.58
  resting-place:0.50 mugface:0.70 house-boat:0.50 portal-appeared:0.50
  dreaming-of-rabbits:0.50 cat-on-a-rock:0.50 night-fishing:0.50
  perfect-view:0.50 submerged:0.50 fox:0.35 daydreaming:0.45
  little-boat:0.50 cottage:0.45
)

# H.264 High in .mp4: the format every iOS version saves to Photos.
VENC=(-c:v libx264 -crf "$CRF" -preset slow -profile:v high
      -color_primaries bt709 -color_trc bt709 -colorspace bt709)

# encode SRC LOOPS FILTERGRAPH OUT
encode() {
  ffmpeg -hide_banner -loglevel error -y \
    -stream_loop "$2" -i "$1" -an -filter_complex "$3" -map "[v]" \
    "${VENC[@]}" -movflags +faststart "$4"
}

mkdir -p "$SRC" "$OUT/crop" "$OUT/fit"

for clip in "${CLIPS[@]}"; do
  name="${clip%%:*}"
  focus="${clip##*:}"
  src="$SRC/$name.mp4"

  if [ ! -s "$src" ] && [ -z "${SKIP_DOWNLOAD:-}" ]; then
    echo "Downloading $name"
    curl -fsSL --retry 3 -o "$src" "$BASE/$name.mp4" || {
      echo "  failed: $name" >&2; rm -f "$src"; continue; }
  fi
  [ -s "$src" ] || continue

  # Extra whole repeats needed to reach MIN_SECS (keeps the loop seamless).
  dur="$(ffprobe -v error -show_entries format=duration \
    -of csv=p=0 "$src")"
  loops="$(awk -v d="$dur" -v m="$MIN_SECS" 'BEGIN {
    n = int(m / d); if (n * d < m) n++; print n - 1 }')"

  echo "Converting $name (x$((loops + 1)))"
  tail="fps=30,format=yuv420p"
  cover="scale=$W:$H:force_original_aspect_ratio=increase:flags=lanczos"

  encode "$src" "$loops" \
    "[0:v]$cover,crop=$W:$H:(iw-ow)*$focus:0,$tail[v]" \
    "$OUT/crop/$name.mp4"

  encode "$src" "$loops" \
    "[0:v]split[a][b];
     [a]$cover,crop=$W:$H,gblur=sigma=40,eq=brightness=-0.12[bg];
     [b]scale=$W:-2:flags=lanczos[fg];
     [bg][fg]overlay=0:(H-h)/2,$tail[v]" \
    "$OUT/fit/$name.mp4"
done

echo "Done: $(find "$OUT" -name '*.mp4' | wc -l | tr -d ' ') clips in $OUT/"
