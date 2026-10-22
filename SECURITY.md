# Security Policy

## Unofficial client — please read first

Summit is an **unofficial, community-built** e-KRÉTA student client. It is
not affiliated with, endorsed by, or supported by e-KRÉTA / the Hungarian
Educational Authority. Use at your own risk.

## How credentials are handled

- Your KRÉTA login runs through the official `idp.e-kreta.hu` OAuth flow.
- Tokens are stored **only on your device** (iOS Keychain via
  `FirkaNative/Core/Storage/SessionStore.swift`) and are never sent to any
  Summit server.
- Optional cross-device settings sync (`sync` Firestore collection) carries
  **no personal data** — only device-generated hashes and UI preferences.
  Grades, names, OM identifiers, e-mails, and tokens are never synced.

## Supported versions

The latest `main` branch and the latest TestFlight/App Store release receive
security fixes. Older builds are not patched — please update first.

## Reporting a vulnerability

- **Do not open a public GitHub issue** for security problems.
- Contact the maintainer privately: open a
  [private security advisory](https://github.com/csabagabor21/Summit/security/advisories/new)
  on GitHub, or e-mail via the address on the GitHub profile.
- Include: what you found, where (file/endpoint), steps to reproduce, and
  the impact you see.
- You can expect an acknowledgment within a few days and a fix or mitigation
  plan as fast as the KRÉTA API allows. Please give us reasonable time to fix
  before any public disclosure.
