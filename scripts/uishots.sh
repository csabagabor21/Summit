#!/bin/bash
# Gyors UI-screenshotok a Summit appból (koppintásos UI-tesztekkel).
# Használat: ./scripts/uishots.sh [kimeneti-mappa]
# Kimenet: <mappa>/*.png emberi nevekkel (01-fooldal, fantom-30-elonezet, ...),
#   innen a `fastlane frameit` csinál keretes mockupot.
# Feltétel: a Summit-iPhone-Fresh szimulátoron bejelentkezett demo-állapot.
set -euo pipefail
cd "$(dirname "$0")/.."
DEV=AE91ECCE-1223-44F8-A70E-3CA8EB52B077
OUT=${1:-fastlane/screenshots-hu}
# Az Xcode GUI által újragenerált user-scheme árnyékolná a shared
# Summit.xcscheme-et (abban van a teszt-akció) — töröljük, újragenerálódik.
rm -f Summit.xcodeproj/xcuserdata/*/xcuserdatad/xcschemes/Summit.xcscheme
rm -rf /tmp/uitest-qc.xcresult "$OUT"
mkdir -p "$OUT"
xcodebuild test -project Summit.xcodeproj -scheme Summit \
  -destination "platform=iOS Simulator,id=$DEV" \
  -only-testing:SummitUITests \
  -derivedDataPath /tmp/derived-uitest \
  -resultBundlePath /tmp/uitest-qc.xcresult > /tmp/uishots-run.log 2>&1
xcrun xcresulttool export attachments --path /tmp/uitest-qc.xcresult \
  --output-path /tmp/uishots-qc > /dev/null
python3 - "$OUT" <<'EOF'
import json, os, shutil, sys
out = sys.argv[1]
man = json.load(open('/tmp/uishots-qc/manifest.json'))
n = 0
for group in man:
    for a in group.get('attachments', []):
        src = os.path.join('/tmp/uishots-qc', a['exportedFileName'])
        human = a.get('suggestedHumanReadableName', '').split('_0_')[0] or a['exportedFileName']
        if human.endswith('.png'):
            pass
        else:
            human += '.png'
        shutil.copy(src, os.path.join(out, human))
        n += 1
print(f'{n} screenshot -> {out}')
EOF
grep -E 'Executed [0-9]+ tests' /tmp/uishots-run.log | tail -n 2
