#!/usr/bin/env bash
# preview.sh <out.png> <svg>... — each SVG large + 32px + 16px (shown 1x and 4x
# nearest-neighbour), on dark and on light. Needs rsvg-convert + ImageMagick.
set -eu
out="$1"; shift
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cols=()
for s in "$@"; do
  n="$(basename "$s" .svg)"
  for bg in '#15151b' '#f4f4f6'; do
    tag="${bg#\#}"
    rsvg-convert -w 240 -h 240 "$s" -o "$tmp/$n-big.png"
    rsvg-convert -w 32 -h 32 "$s" -o "$tmp/$n-32.png"
    rsvg-convert -w 16 -h 16 "$s" -o "$tmp/$n-16.png"
    magick "$tmp/$n-16.png" -filter point -resize 64x64 "$tmp/$n-16x4.png"
    magick -size 280x400 "xc:$bg" \
      "$tmp/$n-big.png" -geometry +20+20 -composite \
      "$tmp/$n-32.png" -geometry +24+300 -composite \
      "$tmp/$n-16.png" -geometry +76+308 -composite \
      "$tmp/$n-16x4.png" -geometry +112+284 -composite \
      "$tmp/$n-$tag.png"
  done
  magick "$tmp/$n-15151b.png" "$tmp/$n-f4f4f6.png" -append \
    -gravity south -background '#0c0c10' -fill '#d4d4d8' -font DejaVu-Sans -pointsize 18 \
    -splice 0x36 -annotate +0+8 "$n" "$tmp/col-$n.png"
  cols+=("$tmp/col-$n.png")
done
magick "${cols[@]}" -background '#0c0c10' -splice 8x0 +append "$out"
echo "$out"
