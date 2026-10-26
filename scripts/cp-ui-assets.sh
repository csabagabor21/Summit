#!/bin/bash
# Cyberpunk 2077 UI-elemek kinyerése a SAJÁT, jogtiszta telepítésből az
# app Cyberpunk-skinjéhez (ugyanaz az elv, mint az mc-sprite.sh és a
# cp-sounds.sh). A felhasznált eredeti elemek:
#   - cp_menu_bg:  pause_menu/tex/menu_bg_texture_1080p.xbm (szünet-menü
#                  háttértextúra, 1920x1080 BC7) -> 1200px JPEG
#   - cp_btn_bg:   pause_menu/atlas_pause_menu_buttons.xbm BC3 atlasz
#                  `pause_button_bg` darabja (265x80, fehér sziluett,
#                  az app sablonként színezi)
#   - cp_logo:     main_menu/menu_background_1080p.xbm atlasz angol
#                  CYBERPUNK 2077 logója (az atlaszban függőlegesen
#                  tükrözve tárolódik, vissza kell forgatni)
#   - cp_pattern:  fx/textures/other/fx_circuit_y_tile_d.xbm áramkör-
#                  minta (512x168-as csempe, screen-keveréssel ül a
#                  gombok/panelek áttetsző alapján)
#
# Lánc: WolvenKit.Console unbundle (.xbm) -> WolvenKit convert s
# (.xbm.json: méret + tömörítés + base64 textúra) -> BC7/BC3 dekódolás
# (uv + texture2ddecoder) -> vágás (Pillow) -> asset catalog.
# A WolvenKit saját textúra-exportja (uncook) macOS-en a Windows-only
# texconv miatt nem megy, ezért a nyers blokkokat dekódoljuk.
# Tömörítés-leképezés: TCM_QualityColor -> BC7, TCM_DXTAlpha -> BC3,
# TCM_DXTNoAlpha -> BC1.
#
# Előkészület: lásd scripts/cp-sounds.sh (WolvenKit + .NET x64 + kraken
# shim), plusz: brew install uv
#
# Használat: GAME="/Volumes/Storage/Cyberpunk 2077" ./scripts/cp-ui-assets.sh
set -euo pipefail
GAME=${GAME:?állítsd be a GAME változót a Cyberpunk 2077 mappájára}
WK=${WK:?állítsd be a WK változót a WolvenKit.CLI.dll mappájára}
DOTNET=${DOTNET:?állítsd be a DOTNET változót az x64 dotnet futtatóra}
OUT=${1:-/tmp/cpui_assets}
ARCH="$GAME/archive/Mac/content/basegame_1_engine.archive"
mkdir -p "$OUT/raw" "$OUT/png"

wk() { arch -x86_64 "$DOTNET" "$WK/WolvenKit.CLI.dll" "$@"; }

# 1) Nyers .xbm textúrák és atlaszok.
wk unbundle "$ARCH" -o "$OUT/raw" -r "pause_menu/tex/menu_bg_texture_1080p"
wk unbundle "$ARCH" -o "$OUT/raw" -r "pause_menu/atlas_pause_menu_buttons"
wk unbundle "$ARCH" -o "$OUT/raw" -r "main_menu/menu_background_1080p"

# 2) Dekódolás .png-be (a .xbm.json melletti base64 blokkból).
uv run --no-project --with texture2ddecoder --with pillow python - "$OUT" <<'PYEOF'
import subprocess, json, base64, sys, glob, os
import texture2ddecoder
from PIL import Image
out = sys.argv[1]
for f in glob.glob(out + '/raw/**/*.xbm', recursive=True):
    subprocess.run(['arch','-x86_64',os.environ['DOTNET'],os.environ['WK']+'/WolvenKit.CLI.dll','convert','s',f],capture_output=True)
    d=json.load(open(f+'.json')); rc=d['Data']['RootChunk']; w,h=rc['width'],rc['height']
    comp=rc['setup']['compression']
    raw=base64.b64decode(rc['renderTextureResource']['renderResourceBlobPC']['Data']['textureData']['Bytes'])
    dec={'TCM_QualityColor':texture2ddecoder.decode_bc7,'TCM_DXTAlpha':texture2ddecoder.decode_bc3,'TCM_DXTNoAlpha':texture2ddecoder.decode_bc1}[comp]
    name=os.path.basename(f).replace('.xbm','.png')
    Image.frombytes('RGBA',(w,h),dec(raw,w,h)).save(out+'/png/'+name)
    print(name, w, h, comp)
PYEOF

echo "Vágás: cp_btn_bg = pause_buttons atlasz y32..111, x37..301 sávja;"
echo "cp_logo = menu_background atlasz y228..346 angol logója FLIP_TOP_BOTTOM-bal;"
echo "cp_menu_bg = menu_bg_texture 1200px széles JPEG-ként."
echo "A kész képek a FirkaNative/Assets.xcassets/Cyberpunk/*.imageset mappákba mennek."
