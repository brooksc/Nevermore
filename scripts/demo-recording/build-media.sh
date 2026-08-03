#!/bin/bash
# Turn master.mov into the shipping artifacts: a 1080p captioned preview for
# the App Store, and GIF loops for GitHub and the site.
#
# Captions are composited as images rather than drawn by ffmpeg: this build has
# no drawtext (no libfreetype) and no subtitles filter (no libass), so text has
# to arrive as pixels.
set -euo pipefail
cd "$(dirname "$0")"

FONT="/System/Library/Fonts/Supplemental/Arial Bold.ttf"
TRIM_START=1.2
TRIM_END=41.4
SPEED=1.4            # 40s of footage into the App Store's 30s ceiling

mkdir -p out cap

# --- 1. Base cut: trimmed, sped up slightly, 1080p -------------------------
ffmpeg -y -v error -ss "$TRIM_START" -to "$TRIM_END" -i master.mov \
  -vf "setpts=(PTS-STARTPTS)/$SPEED,scale=1920:1080:flags=lanczos,fps=30" \
  -an -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p out/base.mp4
echo "base: $(ffprobe -v error -show_entries format=duration -of csv=p=0 out/base.mp4)s"

# --- 2. Captions -----------------------------------------------------------
# start end text
CAPTIONS=(
  "0.8|5.6|Every newsletter in your mailbox, grouped by sender"
  "5.9|8.4|Sorted by who mails you most — and what you never open"
  "8.6|11.2|One keystroke unsubscribes. No web forms, no service in the middle"
  "11.4|14.5|It tells you what it sent — and what it cannot promise"
  "14.8|19.0|Keep the ones you actually read. Ignore hides the rest"
  "19.2|24.4|Or clear out everything a sender ever sent you"
  "24.7|28.6|And when a sender ignores your unsubscribe, Nevermore catches them"
)

i=0
inputs=()
filter=""
last="[0:v]"
for entry in "${CAPTIONS[@]}"; do
  IFS='|' read -r start end text <<< "$entry"
  png="cap/$i.png"
  # Text on a dark scrim: the app is dark, so a plain white caption would sit
  # on whatever happens to be behind it and become unreadable mid-scene.
  magick -background none -fill white -font "$FONT" -pointsize 40 \
    label:"$text" \
    -bordercolor "rgba(0,0,0,0.78)" -border 34x22 "$png"
  inputs+=(-i "$png")
  n=$((i + 1))
  filter+="${last}[${n}:v]overlay=x=(W-w)/2:y=H-h-64:enable='between(t,$start,$end)'[v$n];"
  last="[v$n]"
  i=$n
done
filter="${filter%;}"

ffmpeg -y -v error -i out/base.mp4 "${inputs[@]}" \
  -filter_complex "$filter" -map "$last" \
  -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p out/nevermore-preview-1080.mp4
echo "preview: $(ffprobe -v error -show_entries format=duration -of csv=p=0 out/nevermore-preview-1080.mp4)s"

# --- 3. GIFs ---------------------------------------------------------------
# Two-pass palette: a single global palette keeps the dark UI from banding, and
# keeps the files small enough for a README to load.
gif() {  # name start duration width
  local name=$1 start=$2 dur=$3 width=$4
  ffmpeg -y -v error -ss "$start" -t "$dur" -i out/nevermore-preview-1080.mp4 \
    -vf "fps=13,scale=$width:-1:flags=lanczos,palettegen=stats_mode=diff" cap/pal-$name.png
  ffmpeg -y -v error -ss "$start" -t "$dur" -i out/nevermore-preview-1080.mp4 -i cap/pal-$name.png \
    -lavfi "fps=13,scale=$width:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
    "out/$name.gif"
  echo "$name.gif: $(du -h "out/$name.gif" | cut -f1)"
}

gif unsubscribe 5.9 8.6 1000    # navigate, then one keystroke to unsubscribe
gif triage     14.8 9.4 1000    # keep one, clear out another
gif reappeared 24.4 4.2 1000    # the senders who came back

ls -la out/
