#!/bin/bash
# Capture an iPhone Duo simulator screenshot straight into screenshots/duo/.
# Usage:  ./screenshots/shot.sh inner  1-split-view
#         ./screenshots/shot.sh outer  2-alarm-list
# "inner" = big screen (unfolded), "outer" = cover screen (folded).
set -e
case "$1" in
  inner) display=3 ;;
  outer) display=1 ;;
  *) echo "First word must be inner or outer"; exit 1 ;;
esac
name="${2:-shot}"
dir="$(cd "$(dirname "$0")" && pwd)/duo"
mkdir -p "$dir"
file="$dir/$1-$name.png"
xcrun simctl io booted screenshot --display=$display "$file" >/dev/null
size=$(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixel/{print $2}' | paste -sd x -)
echo "Saved $file ($size)"
