# Contributing to Summit

Thanks for stopping by! Summit is an unofficial, community-built e-KRÉTA
student client for iOS. Contributions are welcome — bug reports, pull
requests, translations, and ideas alike.

## Ground rules

- Be kind and constructive. This project serves students, parents, and
  teachers — keep every interaction friendly.
- One pull request = one change. Small, focused PRs get reviewed fastest.
- No credentials, tokens, or private keys in issues, PRs, or code. Ever.

## Getting started

1. Requirements: iOS 26 SDK / Xcode 15+, optional
   [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml` →
   `Summit.xcodeproj`).
2. Clone the repo and copy the Firebase config template:
   ```bash
   git clone https://github.com/csabagabor21/Summit.git
   cd Summit
   cp FirkaNative/GoogleService-Info.plist.example FirkaNative/GoogleService-Info.plist
   ```
   The real `GoogleService-Info.plist` is git-ignored. For a local build,
   point it at your own Firebase project (see `Firebase/SETUP_HU.md`,
   Hungarian for now — English setup docs welcome as a PR!).
3. Open `Summit.xcodeproj` and build for an iOS 26 Simulator
   (`Summit` scheme, Debug).
4. Debug builds use the Firebase App Check **debug provider**. On first run
   it logs a debug token to the Xcode console. Register it in your Firebase
   project (App Check → Apps → Manage debug tokens), otherwise Firestore and
   the worker reject the simulator's requests once enforcement is on.
5. Tests that need no simulator:
   ```bash
   sh scripts/synckey_selftest.sh          # sync key derivation + encryption
   node --test LiveActivityPush/           # push / AI worker
   python3 -m unittest discover -s Firebase -p "test_*.py"   # map aggregator
   ```
   Firestore rules tests: see `Firebase/rules-tests/README.md`.

## What NOT to put in a PR

- Anything under `build/`, `DerivedData/`, `.env`, or key material
  (`.p8`, `.p12`, `.mobileprovision`, service-account JSON).
- KRÉTA credentials or session tokens (they live in the device Keychain
  only — `FirkaNative/Core/Storage/SessionStore.swift`).
- Personal data of any kind (names, OM identifiers, grades, e-mails).

## Reporting bugs / security issues

- Bugs: open a GitHub issue with steps to reproduce, expected vs. actual
  behavior, iOS version, and app version/build number.
- Security: see [SECURITY.md](SECURITY.md) — please do **not** open a
  public issue for vulnerabilities.
