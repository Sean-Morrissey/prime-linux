#!/usr/bin/env bash
# concept-sheet.sh — renders layer/branding/concepts/concepts-sheet.png: every
# concept large, at 32 px and 16 px (1x and 4x), on dark and light, with a verdict.
set -eu
BR="$(cd "$(dirname "$0")/.." && pwd)"
C="$BR/concepts"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
FONT=DejaVu-Sans; FONTB=DejaVu-Sans-Bold

declare -A TITLE=(
  [1-p-prime]="A · P-prime (P′)"
  [2-prime-disc]="B · Prime symbol"
  [3-first-light]="C · First light"
  [4-orbit-p]="D · Orbit P"
  [5-bar-and-bowl]="E · Bar + bowl"
  [6-split-tile]="F · Split tile  ★ recommended"
)
declare -A NOTE=(
  [1-p-prime]="Clever on paper (P-prime, as in maths) but it reads as a font letter plus an apostrophe. The tick merges into the bowl at 16 px. Generic."
  [2-prime-disc]="Literal 'prime' symbol. Strong at 16 px, but people read '!' or a matchstick. No P, no story about the desktop."
  [3-first-light]="Warm idea (Prime = first light of day) but it is a sunset icon. Weather apps and retro-wave already own it. Mush at 16 px."
  [4-orbit-p]="Clean geometry, but a ring plus a stem is the most common P mark there is (payments, podcasts, crowdfunding). Not ownable."
  [5-bar-and-bowl]="Friendly and bold, but a bar next to a round shape is too close to an existing crowdfunding brand's mark. Rejected for that reason."
  [6-split-tile]="One rounded tile, split the way Hyprland splits a screen: a tall window plus one beside it. The split spells P. It tells the product story, every corner is an exact arc, and the gap survives at 16 px (a small-size cut widens it)."
)

cols=()
for s in "$C"/[0-9]-*.svg; do
  n="$(basename "$s" .svg)"
  rsvg-convert -w 220 -h 220 "$s" -o "$tmp/big.png"
  rsvg-convert -w 32 -h 32 "$s" -o "$tmp/32.png"
  src="$s"; [ "$n" = 6-split-tile ] && src="$BR/mark-small.svg"
  rsvg-convert -w 16 -h 16 "$src" -o "$tmp/16.png"
  magick "$tmp/16.png" -filter point -resize 64x64 "$tmp/16x4.png"
  for bg in '#15151b' '#f4f4f6'; do
    magick -size 300x330 "xc:$bg" \
      "$tmp/big.png" -geometry +40+16 -composite \
      "$tmp/32.png"  -geometry +56+262 -composite \
      "$tmp/16.png"  -geometry +118+270 -composite \
      "$tmp/16x4.png" -geometry +170+246 -composite \
      "$tmp/p-${bg#\#}.png"
  done
  hl='#2a2a33'; [ "$n" = 6-split-tile ] && hl='#f87171'
  magick -size 300x46 xc:'#0c0c10' -font "$FONTB" -pointsize 17 -fill '#f4f4f6' \
    -gravity west -annotate +14+0 "${TITLE[$n]}" "$tmp/t.png"
  magick -size 272x112 -background '#0c0c10' -fill '#b4b4bc' -font "$FONT" -pointsize 13 \
    caption:"${NOTE[$n]}" -bordercolor '#0c0c10' -border 14x10 "$tmp/n.png"
  magick "$tmp/t.png" "$tmp/p-15151b.png" "$tmp/p-f4f4f6.png" "$tmp/n.png" -append \
    -bordercolor "$hl" -border 3 "$tmp/col-$n.png"
  cols+=("$tmp/col-$n.png")
done
magick "${cols[@]}" -background '#0c0c10' -splice 14x0 +append -gravity east -splice 14x0 "$tmp/row.png"
magick -size 1900x70 xc:'#0c0c10' -font "$FONTB" -pointsize 26 -fill '#f4f4f6' -gravity west \
  -annotate +24-6 "Prime Linux — emblem concepts" -font "$FONT" -pointsize 14 -fill '#8a8a94' \
  -annotate +24+22 "each: large · 32 px · 16 px · 16 px enlarged 4× — on dark and on light. Accent shown: Rose (#f87171); every mark takes the user's accent." \
  "$tmp/head.png"
magick "$BR/png/lockup-dark.png" -resize 700x "$tmp/lk.png"
magick -size 1900x170 xc:'#15151b' "$tmp/lk.png" -gravity center -composite "$tmp/lock.png"
magick "$tmp/head.png" "$tmp/row.png" "$tmp/lock.png" -background '#0c0c10' -gravity center -append \
  -bordercolor '#0c0c10' -border 0x14 "$C/concepts-sheet.png"
echo "$C/concepts-sheet.png"
