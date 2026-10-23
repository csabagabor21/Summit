#!/bin/bash
# Minecraft-sprite felvétele az asset catalogba (pbxproj-módosítás nélkül).
# Használat: scripts/mc-sprite.sh <forrás.png> <név>   pl. mc_item_bell
# A forrás egy 1.21.11-es kliens-jarból kibontott textúra (assets/minecraft/textures/...).
set -euo pipefail
src="$1"; name="$2"
[[ "$name" == mc_* ]] || { echo "a név mc_ előtaggal kezdődjön" >&2; exit 1; }
[[ -f "$src" ]] || { echo "nincs ilyen fájl: $src" >&2; exit 1; }
root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$root/FirkaNative/Assets.xcassets/Minecraft/$name.imageset"
mkdir -p "$dir"
# Animált textúrák (függőleges filmcsík) első kockája: a szélességgel egyező magasság.
w=$(sips -g pixelWidth "$src" | awk '/pixelWidth/{print $2}')
h=$(sips -g pixelHeight "$src" | awk '/pixelHeight/{print $2}')
if [[ -f "$src.mcmeta" ]] && grep -q '"animation"' "$src.mcmeta" && (( h > w )); then
  sips -c "$w" "$w" --cropOffset 0 0 "$src" --out "$dir/$name.png" >/dev/null
else
  cp "$src" "$dir/$name.png"
fi
cat > "$dir/Contents.json" <<JSON
{
  "images" : [ { "filename" : "$name.png", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : false, "template-rendering-intent" : "original" }
}
JSON
echo "$name"
