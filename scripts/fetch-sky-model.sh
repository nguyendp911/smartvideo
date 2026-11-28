#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
base="https://huggingface.co/twistlabs/fotometis-sky/resolve/97dfe50bf3fe4dc02badea287512afaf4ce857c2/SkySegSmall.mlpackage"
root="Models/SkySegSmall.mlpackage"
mkdir -p "$root/Data/com.apple.CoreML/weights"
for f in Manifest.json Data/com.apple.CoreML/model.mlmodel Data/com.apple.CoreML/weights/weight.bin; do
  curl --fail --location --retry 3 --connect-timeout 20 --max-time 180 "$base/$f" -o "$root/$f"
done
printf '%s  %s\n' f12a39fe104d0a5d2285820d322d9697de5a5011ee355132cbc01822e9d1a06f "$root/Data/com.apple.CoreML/model.mlmodel" 5df3feebcc15a77480fabb9896b96036e5acc38dc043af414f09dc5b1d296efb "$root/Data/com.apple.CoreML/weights/weight.bin" | shasum -a 256 -c -
