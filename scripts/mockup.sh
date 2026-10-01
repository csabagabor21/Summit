#!/bin/bash
# Keretes mockup screenshot-mappából: ./scripts/mockup.sh <mappa>
# A mappa PNG-it hu/ alá rendezi, a fájlnevekből title.strings-t ír
# (kötőjel/alulvonás -> szóköz; kézzel átírható, újrafuttatható),
# majd frameit-tel iPhone-keretbe teszi.
# Kimenet: <mappa>/hu/*_framed.png
# Feltétel: fastlane + imagemagick (brew install fastlane imagemagick).
set -euo pipefail
DIR=${1:?Használat: ./scripts/mockup.sh <screenshot-mappa>}
cd "$DIR"
mkdir -p hu fastlane
# Már keretezettek és segédfájlok nem kellenek újra.
find . -maxdepth 1 -name '*.png' -exec mv {} hu/ \; 2>/dev/null || true
: > hu/title.strings
for f in hu/*.png; do
  case "$f" in *_framed.png) continue;; esac
  base=$(basename "$f" .png)
  title=$(echo "$base" | sed -e 's/^tab-//' -e 's/^fantom-//' -e 's/[-_]/ /g')
  printf '"%s" = "%s";\n' "$base" "$title" >> hu/title.strings
done
[ -f fastlane/Framefile.json ] || echo '{"device_frame_version": "latest"}' > fastlane/Framefile.json
fastlane frameit 2>&1 | grep -E 'Added frame|Skipping|error|Unsupported' | head -n 20
echo "Kész: $DIR/hu/*_framed.png"
