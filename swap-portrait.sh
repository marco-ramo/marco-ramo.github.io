#!/usr/bin/env bash
#
# swap-portrait.sh — swap the portrait embedded in index.html.
#
# The portrait ships base64-encoded inside index.html so the page stays a single
# self-contained file. That makes changing it fiddly by hand: the data sits on one
# 150,000-character line, and the width/height attributes beside it have to match the
# new image or the layout shifts while the page loads. This script does both.
#
# Usage:
#   ./swap-portrait.sh --list              show the available portraits and the active one
#   ./swap-portrait.sh blue-duotone        make portraits/blue-duotone.jpg the live portrait
#
# The files in portraits/ are stored at display size and embedded byte-for-byte, with no
# re-compression, so switching back and forth is lossless however often you do it.
# Adding a new portrait means resizing it to roughly 760px tall and saving it into
# portraits/ first — the script warns rather than silently shrinking an oversized file,
# because re-compressing on every swap would degrade the image a little each time.

set -euo pipefail

cd "$(dirname "$0")"

HTML="index.html"
DIR="portraits"
MAX_HEIGHT=1000        # above this, the image is too big to embed comfortably
MAX_BYTES=250000       # ditto — index.html grows by ~4/3 of this

die() { printf 'error: %s\n' "$1" >&2; exit 1; }

# The sha256 of the image currently embedded in index.html, so --list can mark it.
# The regex assumes the portrait <img> writes class before src and starts its class list
# with "portrait". If the markup ever moves, print a sentinel rather than nothing: an
# empty result would silently match no portrait and --list would render every file
# unmarked under a legend promising a mark, which reads as "nothing is live".
UNKNOWN="unknown"
active_hash() {
  python3 - "$HTML" <<'PY'
import base64, hashlib, re, sys
html = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'<img class="portrait[^"]*" src="data:image/jpeg;base64,([^"]*)"', html)
print(hashlib.sha256(base64.b64decode(m.group(1))).hexdigest() if m else "unknown")
PY
}

list_portraits() {
  local active found=0
  active="$(active_hash)"
  [ "$active" != "$UNKNOWN" ] || die "could not identify the live portrait in $HTML — the portrait <img> markup no longer matches what active_hash looks for"
  printf 'Portraits in %s/\n\n' "$DIR"
  for f in "$DIR"/*.jpg "$DIR"/*.jpeg; do
    [ -e "$f" ] || continue
    found=1
    local name hash mark dims
    name="$(basename "${f%.*}")"
    hash="$(shasum -a 256 "$f" | cut -d' ' -f1)"
    dims="$(sips -g pixelWidth -g pixelHeight "$f" 2>/dev/null \
            | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{printf "%sx%s", w, h}')"
    mark="  "; [ "$hash" = "$active" ] && mark="* "
    printf '%s%-24s %10s  %6sKB\n' "$mark" "$name" "$dims" "$(( $(stat -f%z "$f") / 1024 ))"
  done
  [ "$found" -eq 1 ] || die "no .jpg files in $DIR/"
  printf '\n* = currently live in %s\n' "$HTML"
}

[ $# -eq 1 ] || { sed -n '5,18p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[ -d "$DIR" ] || die "no $DIR/ directory"

case "$1" in
  --list|-l) list_portraits; exit 0 ;;
  -*) die "unknown option: $1" ;;
esac

# Resolve the name to a file, accepting "blue-duotone", "blue-duotone.jpg", or a path.
SRC=""
for candidate in "$1" "$DIR/$1" "$DIR/$1.jpg" "$DIR/$1.jpeg"; do
  [ -f "$candidate" ] && { SRC="$candidate"; break; }
done
[ -n "$SRC" ] || die "no portrait named '$1' — run --list to see what's there"

[ "$(file -b --mime-type "$SRC")" = "image/jpeg" ] || die "$SRC is not a JPEG"

WIDTH="$(sips -g pixelWidth "$SRC" | awk '/pixelWidth/{print $2}')"
HEIGHT="$(sips -g pixelHeight "$SRC" | awk '/pixelHeight/{print $2}')"
BYTES="$(stat -f%z "$SRC")"
[ -n "$WIDTH" ] && [ -n "$HEIGHT" ] || die "could not read the dimensions of $SRC"

if [ "$HEIGHT" -gt "$MAX_HEIGHT" ] || [ "$BYTES" -gt "$MAX_BYTES" ]; then
  printf 'warning: %s is %sx%s at %sKB — larger than the ~587x760 / 120KB the page expects.\n' \
    "$SRC" "$WIDTH" "$HEIGHT" "$(( BYTES / 1024 ))" >&2
  printf '         The portrait never displays taller than 260px, so this is wasted weight.\n' >&2
  printf '         Resize it first:  sips --resampleHeight 760 %s\n\n' "$SRC" >&2
  printf 'Embed it anyway? [y/N] ' >&2
  read -r reply
  case "$reply" in [yY]*) ;; *) die "cancelled" ;; esac
fi

python3 - "$HTML" "$SRC" "$WIDTH" "$HEIGHT" <<'PY'
import base64, re, sys

html_path, src_path, width, height = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(src_path, "rb") as fh:
    payload = base64.b64encode(fh.read()).decode("ascii")

html = open(html_path, encoding="utf-8").read()

# The portrait <img> spans three lines: the src on one, width/height on the next,
# then alt. Rewrite the first two together so they can never drift apart.
pattern = re.compile(
    r'(<img class="portrait[^"]*" src="data:image/jpeg;base64,)[^"]*'
    r'("\s*\n\s*width=")\d+(" height=")\d+(")'
)
html, count = pattern.subn(
    lambda m: f"{m.group(1)}{payload}{m.group(2)}{width}{m.group(3)}{height}{m.group(4)}",
    html,
)
if count != 1:
    sys.exit(f"error: expected exactly one portrait <img> in {html_path}, found {count}")

with open(html_path, "w", encoding="utf-8") as fh:
    fh.write(html)
PY

printf 'Embedded %s (%sx%s, %sKB) into %s\n' \
  "$(basename "$SRC")" "$WIDTH" "$HEIGHT" "$(( BYTES / 1024 ))" "$HTML"
printf 'Preview it locally, then commit and push to deploy.\n'
