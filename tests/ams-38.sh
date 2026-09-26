#!/bin/sh
# ams-38 — the portrait's keyboard focus ring must not be clipped away.
#
# The .portrait rule cuts its two 45° corner notches with clip-path, and clip-path clips
# everything the element paints outside the polygon, outline included. Every polygon
# point lies inside the image's box, so an outline drawn outside that box (a non-negative
# outline-offset) is never painted: a keyboard visitor tabs onto the portrait and sees
# nothing. A negative offset draws the ring inside the box, where the polygon keeps it.
#
# This is a code-shape check, not a rendering check. Exits non-zero when the .portrait{
# rule declares clip-path and any .portrait:focus-visible rule carries an outline-offset
# that is not negative, or carries none (the default offset is 0, still at the edge).

set -eu
cd "$(dirname "$0")/.."

# The base rule opens on its own line as "  .portrait{" and closes on the next "  }".
rule=$(awk '/^[[:space:]]*\.portrait\{/ { on=1 } on { print } on && /^[[:space:]]*\}/ { exit }' index.html)

if [ -z "$rule" ]; then
  echo "ams-38 FAIL: could not locate the .portrait{ rule in index.html"
  exit 1
fi

case "$rule" in
  *clip-path*) ;;
  *)
    echo "ams-38 PASS: the .portrait{ rule declares no clip-path, so nothing clips the focus ring"
    exit 0
    ;;
esac

focus=$(grep -n '\.portrait:focus-visible' index.html || true)

if [ -z "$focus" ]; then
  echo "ams-38 FAIL: no .portrait:focus-visible rule found — the portrait has no focus ring at all"
  exit 1
fi

bad=0
echo "$focus" | while IFS= read -r l; do
  n=${l%%:*}
  offset=$(printf '%s\n' "$l" | grep -o 'outline-offset:[^;}]*' | head -1 | sed 's/outline-offset://')
  case "$offset" in
    -*) ;;
    *)
      echo "ams-38 FAIL: .portrait clips with clip-path, but the focus ring at index.html:$n has outline-offset '${offset:-unset}', which draws it outside the polygon"
      exit 1
      ;;
  esac
done || bad=1

[ "$bad" -eq 0 ] || exit 1

echo "ams-38 PASS: every .portrait:focus-visible outline-offset is negative, inside the clip-path polygon"
