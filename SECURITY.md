# Security Policy

## Unofficial client — please read first

Summit is an **unofficial, community-built** e-KRÉTA student client. It is
not affiliated with, endorsed by, or supported by e-KRÉTA / the Hungarian
Educational Authority. Use at your own risk.

## How your data is handled

- **KRÉTA login** runs through the official `idp.e-kreta.hu` OAuth flow with
  a fresh PKCE verifier, nonce and state for every login attempt.
- **KRÉTA tokens** are stored only on your device, in the iOS Keychain
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, see
  `FirkaNative/Core/Storage/SessionStore.swift`). They are not included in
  backups that leave the device and are never sent to any Summit server.
- **Your own Meta AI key** is stored in the Keychain the same way. The
  paired Apple Watch keeps its own copy in the watch app's storage so it
  can answer without the phone.
- **Settings sync** (optional, `sync2` Firestore collection) is end-to-end
  encrypted. The key is derived on the device from your KRÉTA account ID
  and a passphrase of at least 8 characters, using PBKDF2-SHA256 with
  600 000 rounds; the passphrase itself never leaves the device. Every
  synced value is encrypted with AES-GCM, including the profile photo, notes,
  custom tasks and the Meta AI key. The server only sees the document ID,
  the schema version and the timestamps of when each setting last changed.
  Anyone who knows your passphrase **and** your KRÉTA account ID can read
  your synced settings, so use a passphrase you don't use anywhere else.
  The older, unencrypted `sync` documents are migrated and deleted
  automatically the first time an updated app syncs.
- **Anonymous statistics** (opt-in, off by default) send a random install
  ID, the school name and the institute code, the app version, the platform
  and the day. They contain no student identifiers.
- **The shared AI fallback** (used when you have no Meta AI key) goes
  through Summit's Cloudflare Worker. The Gemini API key lives only there,
  and the worker forwards your study material without logging it.

## Backend protection

The repository is public, so endpoints, schemas and the Firebase web API
key are public too. They are not secrets. Access is enforced on the server:

- **Firebase App Check** (App Attest, with DeviceCheck as fallback) is
  attached to every request to Firestore, the push worker and the AI proxy.
- **Firestore security rules** (`Firebase/firestore.rules`) allow no
  listing and have strict per-field schemas and size limits. Only the
  aggregated `public/map` document is publicly readable. They are tested in
  `Firebase/rules-tests`.
- **The push and AI worker** (`LiveActivityPush/worker.js`) verifies App
  Check tokens. Its diagnostics endpoint needs an admin token.

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
