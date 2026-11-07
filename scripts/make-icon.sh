#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT="$ROOT/Brand/logo-source.jpg"
OUT="$ROOT/SmartVideo/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
if [[ ! -f "$INPUT" ]]; then
  echo "Missing ViePN app icon source: $INPUT" >&2
  exit 1
fi
mkdir -p "$(dirname "$OUT")"
if command -v sips >/dev/null 2>&1; then
  sips -s format png -z 1024 1024 "$INPUT" --out "$OUT" >/dev/null
else
  echo "This icon preparation script requires macOS sips." >&2
  exit 1
fi
test -s "$OUT"
echo "Prepared ViePN Smart Video AppIcon: $OUT"
