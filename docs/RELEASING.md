# Releasing Popup Notes

Two distribution paths. Both require a **paid** Apple Developer Program
membership ($99/yr — check your status at developer.apple.com/account) for a
friction-free install; without it you can still share dev-signed builds with
caveats (see "Sharing without a paid account" below).

All commands run from the repo root. Artifacts land in `dist/` (gitignored).

## Path A — share a DMG directly (recommended first)

Outside-the-App-Store distribution needs a **Developer ID Application**
certificate plus **notarization** (Apple's automated malware scan). Hardened
Runtime is already enabled in the project, as required.

One-time setup:

1. **Certificate:** Xcode ▸ Settings ▸ Accounts ▸ (your team) ▸ Manage
   Certificates ▸ + ▸ *Developer ID Application*. (Only the Account Holder can
   create it; the portal at developer.apple.com/account/resources/certificates
   works too.)
2. **Notary credentials:** create an app-specific password at
   account.apple.com, then:

   ```sh
   xcrun notarytool store-credentials notary \
     --apple-id <your-apple-id> --team-id 422R4JTNFH
   ```

Every release:

```sh
NOTARY_PROFILE=notary ./scripts/release.sh developer-id
```

That archives, exports with Developer ID, builds the DMG, submits it to the
notary service (`--wait` blocks until Apple finishes, usually minutes), staples
the ticket, and verifies with `spctl`. The resulting
`dist/PopupNotes-<version>.dmg` opens cleanly on any Mac.

## Path B — Mac App Store

The app already meets the technical requirements: App Sandbox on, app category
set, privacy manifest bundled, export-compliance key declared, and SwiftData /
the Carbon hotkey / `SMAppService` all work sandboxed.

> **Review guideline 2.4.5(iii) — handled:** Mac apps "may not auto-launch …
> at startup or login without consent," so launch-at-login is enabled only by
> the user clicking **Enable** in the first-run onboarding strip at the bottom
> of the notes panel (or the Settings toggle) — never silently. A one-time
> launch reconciliation also disables any pre-consent default left by old
> builds. Mention the strip's Enable/Not Now consent in your review notes.

1. In [App Store Connect](https://appstoreconnect.apple.com): Apps ▸ + ▸ New
   App ▸ platform **macOS**, bundle ID `ai.jetwriter.popupnotes`.
2. Fill the listing: description, keywords, support URL, a **privacy policy
   URL** (required even for "Data Not Collected"), and screenshots (current
   accepted macOS sizes incl. 1280×800, 1440×900, 2560×1600, 2880×1800 — the
   upload UI lists them; window screenshots over a wallpaper are fine).
3. App Privacy section: everything is local, so declare **Data Not Collected**.
4. Build and upload:

   ```sh
   ./scripts/release.sh app-store
   ```

   then upload the `.pkg` from `dist/appstore/` with the **Transporter** app (or
   use Xcode ▸ Window ▸ Organizer ▸ Distribute App and skip the script).
5. Select the build on the version page and add **review notes**: explain it's
   a menu-bar-only app (no Dock icon), the panel opens with ⌃⌘N, and quitting
   is via the menu-bar icon — reviewers reject what they can't find.
6. Submit for review. First reviews typically take a few days.

## Sharing without a paid account (what you have today)

`./scripts/release.sh` produces a dev-signed DMG. It runs fine on your Macs,
but anyone else gets "Apple could not verify…". They must: open it once, then
System Settings ▸ Privacy & Security ▸ scroll down ▸ **Open Anyway** ▸ confirm
(macOS 26 may ask for an admin password). Right-click ▸ Open no longer
bypasses this. Fine for a couple of friends who trust you; get Developer ID
for anything wider.

## Versioning

Bump `MARKETING_VERSION` (user-facing, e.g. 1.1) and `CURRENT_PROJECT_VERSION`
(build number — must increase for every App Store upload) in the target's
build settings before releasing.
