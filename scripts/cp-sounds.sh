#!/bin/bash
# Cyberpunk 2077 UI-hangok kinyerése a SAJÁT, jogtiszta telepítésből az
# app Cyberpunk-skinjéhez (ugyanaz az elv, mint az mc-sprite.sh a
# Minecraft-textúráknál). A játék Mac-verziója a hangokat REDengine
# `.archive`-okban, Wwise Opus-formátumban tárolja, ezért a lánc:
#   WolvenKit.Console (unbundle) -> wwiser (esemény -> média-ID)
#   -> sfx_container.opusinfo (média-ID -> opuspak + offset)
#   -> vgmstream-cli (Opus -> WAV) -> ffmpeg (AAC, .m4a Data Set)
#
# Előkészület (egyszeri):
#   - WolvenKit.Console 9.1+: https://github.com/WolvenKit/WolvenKit/releases
#     macOS-en .NET 10 x64 runtime-mal, Rosetta alatt fut:
#       arch -x86_64 /path/to/dotnet WolvenKit.CLI.dll ...
#     A csomag libkraken.dylib-je C++-mangled szimbólumokat exportál,
#     a CLI viszont C-neveket keres (Kraken_Decompress/Kraken_Compress) —
#     egy vékony shim-dylib kell elé (a valódi lib libkraken_real.dylib
#     néven mellé másolva, a shim ugyanarra mutat).
#   - wwiser: https://github.com/bnnm/wwiser (bnk-parser)
#   - vgmstream-cli (mac): https://github.com/vgmstream/vgmstream/releases
#     + `brew install libvorbis opus mpg123 speex`
#
# Használat: GAME="/Volumes/Storage/Cyberpunk 2077" ./scripts/cp-sounds.sh
set -euo pipefail
GAME=${GAME:?állítsd be a GAME változót a Cyberpunk 2077 mappájára}
WK=${WK:?állítsd be a WK változót a WolvenKit.CLI.dll mappájára}
DOTNET=${DOTNET:?állítsd be a DOTNET változót az x64 dotnet futtatóra}
VG=${VG:?állítsd be a VG változót a vgmstream-cli elérési útjára}
WWISER=${WWISER:?állítsd be a WWISER változót a wwiser.py elérési útjára}
OUT=${1:-/tmp/cpui}
ARCH="$GAME/archive/Mac/content"
mkdir -p "$OUT/bnk" "$OUT/txtp" "$OUT/opus" "$OUT/wem"

wk() { arch -x86_64 "$DOTNET" "$WK/WolvenKit.CLI.dll" "$@"; }

# 1) Hangbankok + Opus-csomagok + az opusinfo index kinyerése.
wk unbundle "$ARCH/audio_2_soundbanks.archive" -o "$OUT/bnk" -w "sfx_container.bnk"
wk unbundle "$ARCH/audio_2_soundbanks.archive" -o "$OUT/opus" -w "*.opuspak"
wk unbundle "$ARCH/audio_2_soundbanks.archive" -o "$OUT/opus" -w "*.opusinfo"

# 2) Eseménynév -> média-ID a bankból (wwiser txtp: CAkEvent FNV-hash ->
#    Source média-ID). A cél-események és a belőlük lett asset-nevek:
#      ui_menu_onpress              -> cp_snd_click (stílusos gomb)
#      ui_menu_mouse_click          -> cp_snd_mouseclick (sima koppintás)
#      ui_gui_tab_change            -> cp_snd_tab (dock)
#      ui_menu_close                -> cp_snd_back (VISSZA gomb)
#      ui_menu_value_up             -> cp_snd_valueup (kapcsoló be)
#      ui_menu_value_down           -> cp_snd_valuedown (kapcsoló ki)
#      ui_phone_navigation          -> cp_snd_navigate (belső választó)
#      ui_positive                  -> cp_snd_confirm
#      ui_generic_set_01_negative   -> cp_snd_error
#      ui_phone_sms                 -> cp_snd_toast
#      ui_splash_screen_glitch      -> cp_snd_glitch (1 mp-re vágva)
python3 "$WWISER" "$OUT/bnk/base/sound/soundbanks/sfx_container.bnk" -g -go "$OUT/txtp" -gw "$OUT/wem" -gd

echo "A média-ID-ket az sfx_container.opusinfo alapján vágd ki a"
echo "sfx_container_<pack>.opuspak fájlokból (12 B fejléc után: u32 count,"
echo "u32 grouping, majd count x u32 média-ID, count x u16 pack-index,"
echo "count x u32 offset, count x u16 riff-offset, count x u32 hossz),"
echo "majd: $VG -i -o hang.wav hang.wem  és  ffmpeg -i hang.wav -c:a aac -b:a 96k cp_snd_<név>.m4a"
echo "Az .m4a-k a FirkaNative/Assets.xcassets/Cyberpunk/cp_snd_<név>.dataset mappákba mennek."
