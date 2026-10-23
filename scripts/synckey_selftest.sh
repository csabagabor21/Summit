#!/bin/sh
# SummitSyncKey önteszt (v2 kulcsképzés, AES-GCM mezőtitkosítás, v1→v2
# összefésülés) — Xcode-projekt és szimulátor nélkül, macOS-en:
#   sh scripts/synckey_selftest.sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -O -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  "$ROOT/FirkaNative/Core/Storage/SummitSyncKey.swift" \
  "$ROOT/scripts/synckey-selftest/Stubs.swift" \
  "$ROOT/scripts/synckey-selftest/main.swift" \
  -o "$OUT/synckey-selftest"
"$OUT/synckey-selftest"
