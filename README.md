# Codex Desktop (Intel macOS)

![GitHub repo size](https://img.shields.io/github/repo-size/Sancerio/codex-intel)
![GitHub stars](https://img.shields.io/github/stars/Sancerio/codex-intel?style=flat)
![GitHub license](https://img.shields.io/github/license/Sancerio/codex-intel)

Run OpenAI Codex Desktop on Intel macOS by converting the official macOS app bundle or DMG into an x86_64 Electron app bundle. Stable and Beta builds are both supported.

> This is an unofficial community project. Codex Desktop is a product of OpenAI.

Learn more about Codex: https://openai.com/codex/

## What this does

The installer:

1. Takes a local `.app` bundle or extracts the macOS `.dmg`
2. Pulls out `app.asar` (the Electron app)
3. Rebuilds native modules (`node-pty`, `better-sqlite3`) for Electron x64
4. Disables macOS‑only Sparkle auto‑update
5. Downloads Electron for darwin‑x64 (default: the packaged app's Electron version, with optional fallback override)
6. Repackages everything into a runnable app bundle with the same name as the original DMG app, such as `Codex.app` or `Codex (Beta).app`
7. Applies a small patch so it doesn’t try to connect to a Vite dev server

## Prerequisites

- Intel Mac (x86_64)
- Node.js 20+ and npm
- Python 3
- Xcode Command Line Tools (`xcode-select --install`)
- Homebrew (for `p7zip` and `curl`)

Install dependencies:

```bash
brew install p7zip curl
```

You also need the Codex CLI installed:

```bash
npm i -g @openai/codex
```

## Installation

### Option A: Provide your own app bundle or DMG

```bash
git clone https://github.com/<your-user>/codex-intel.git
cd codex-intel
chmod +x install.sh
./install.sh /path/to/Codex*.app
```

Or:

```bash
./install.sh /path/to/Codex*.dmg
```

Verbose native rebuild output:

```bash
./install.sh -v /path/to/Codex.dmg
```

Force an older Electron runtime explicitly:

```bash
./install.sh --electron-version 32.3.3 /path/to/Codex.app
```

### Option B: Auto‑download DMG

If you have the DMG URL, you can pass it directly:

```bash
./install.sh https://example.com/Codex*.dmg
```

### Option C: Use the current Beta app bundle zip

The current Beta desktop build is listed in the public beta appcast:

https://persistent.oaistatic.com/codex-app-beta/appcast.xml

Current entry:

[Codex (Beta) darwin-arm64 26.317.21539](https://persistent.oaistatic.com/codex-app-beta/Codex%20(Beta)-darwin-arm64-26.317.21539.zip)

Because this download is a `.zip` containing `Codex (Beta).app`, unzip it first, then point `install.sh` at the extracted app bundle:

```bash
unzip 'Codex (Beta)-darwin-arm64-26.317.21539.zip'
./install.sh './Codex (Beta).app'
```

## Codex Automation

If you use Codex Automations, you can save the beta refresh workflow as a scheduled task for this repo.

Suggested setup:

- workspace: `codex-intel`
- schedule: weekdays at `9:00 AM`
- model: `GPT-5.4`
- title: `Update Codex Intel Binary`

Suggested prompt:

```text
Help me take a look if there's a new beta release for the codex, download, and convert them so we can update our build.
```

This works well as a recurring repo maintenance task:

- checks whether a newer Codex Beta build exists
- downloads the current Beta app bundle zip
- runs the local conversion flow in this repo
- lets you review the resulting build/logs before committing any repo changes

For manual installs, `install.sh` remains the source of truth.

## Usage

The installer creates:

```
./codex-app/<original app name>.app
```

Launch it from Finder or:

```bash
./codex-app/Codex.app/Contents/MacOS/Electron --no-sandbox
```

For Beta builds, that path is typically:

```bash
./codex-app/Codex\ \(Beta\).app/Contents/MacOS/Electron --no-sandbox
```

Or use the helper script:

```bash
./start.sh
```

## Legacy Intel Mac Fallback

Some older Intel Macs can launch a rebuilt Codex app on Electron `32.3.3` but fail on newer Electron releases such as `40.x`.

Typical symptoms:

- blank or black window on launch
- startup trying to hit `http://localhost:5175`
- app opens from a repo-local bundle but not from `/Applications`

For those machines, use:

```bash
./install.sh --electron-version 32.3.3 /path/to/Codex.app
```

If you already have a working patched bundle under `./codex-app/`, copy that same `.app` into `/Applications` so Finder launches the identical build.

Detailed case notes: [docs/legacy-intel-electron-32-fallback.md](/Users/cowkin/Code/DailyOps/codex-intel/docs/legacy-intel-electron-32-fallback.md)

## Performance (Intel Fan Noise / Idle Heat)

This repo now applies a low-power window patch during `install.sh`:

- forces opaque windows
- disables liquid-glass effects
- applies an aggressive renderer performance patch:
  - disables renderer Sentry init
  - bypasses Shiki highlight provider wrapper
  - disables non-essential telemetry/notification hooks

This reduces idle GPU load on many Intel Macs.

Tradeoffs in aggressive mode:

- desktop notifications/badge updates may be reduced
- some telemetry diagnostics are disabled
- code highlighting behavior may be simpler in chat output

If you already built an app in `codex-app/`, patch it in place without reinstalling:

```bash
./optimize-power.sh
```

Optional custom app path:

```bash
./optimize-power.sh /path/to/Codex*.app
```

`./start.sh` launches the newest app bundle under `codex-app/`, so a fresh Beta install will be picked automatically even if older stable bundles are still present.

## Notes

- Auto‑update is disabled (Sparkle is macOS‑only and removed).
- The app may show warnings about `url.parse` deprecation — safe to ignore.
- The app expects the Codex CLI to be available. `install.sh` also tries to copy an x86_64 `codex` binary into the app bundle, so Finder launches do not depend only on your interactive shell PATH.
- During native rebuild, upstream modules can emit compiler warnings; this is expected as long as rebuild finishes with `Rebuild OK`.
- Native rebuild output is saved under `work/logs/` by default (for example `work/logs/rebuild-better-sqlite3.log`).
- To stream full native rebuild output live, run with `./install.sh -v ...` (or set `NATIVE_REBUILD_VERBOSE=1`).

## Troubleshooting

**App opens a blank window**
- Make sure the patch applied (installer output should say “patched main.js”).
- On some older Intel Macs, rebuild again with `--electron-version 32.3.3`.
- If patching fails with a pattern error, use the Codex CLI fallback shown by `install.sh` to update patch logic in `install.sh`, then rerun the installer.

**`/Applications/Codex.app` still fails after a repo-local build works**
- You are probably launching two different app bundles.
- Compare `./codex-app/Codex.app` and `/Applications/Codex.app`; if they differ, replace the `/Applications` copy with the verified working bundle.
- Re-run the smoke test directly against the installed bundle:

```bash
./smoke-test.sh /Applications/Codex.app
```

**Integrated terminal fails with `posix_spawnp failed`**
- On macOS, this can happen for two different reasons:
- The login shell path from the account record or `SHELL` is invalid.
- The packaged `node-pty` helper binary does not match the app architecture. On the affected Intel Mac, `pty.node` was `x86_64` but `spawn-helper` was still `arm64`, so terminal startup failed even when the shell path was `/bin/zsh`.
- This repo now patches the packaged app to fall back to `/bin/zsh`, `/bin/bash`, and then `/bin/sh` when the recorded shell path is invalid.
- The installer also now copies the matching `node-pty` `spawn-helper` into the final app bundle so Electron 32 x64 builds do not retain a stale arm64 helper.
- Re-run `./install.sh ...` to rebuild with both terminal fixes.
- There is currently no macOS integrated-terminal shell picker in Codex settings, so this is not something you can reliably fix from the app UI alone.
- A user-level fix is to set your login shell back to a valid system shell:

```bash
chsh -s /bin/zsh
```

- You can verify the current login shell with:

```bash
dscl . -read /Users/"$USER" UserShell
```

- You can inspect the packaged helper architecture with:

```bash
file /Applications/Codex.app/Contents/Resources/app.asar.unpacked/node_modules/node-pty/build/Release/spawn-helper
```

**Native module load error**
- Delete `codex-app/` and rerun `install.sh`.

**Compiler warnings during install**
- Warnings from `better-sqlite3` and `node-pty` can be normal with newer toolchains.
- Treat the run as successful if installer output shows `Rebuild OK: better-sqlite3` and `Rebuild OK: node-pty`.
- If rebuild fails, inspect `work/logs/rebuild-*.log`.

**Native rebuild fails on an old Intel Mac with missing C++20 headers**
- Electron native rebuilds for some fallback versions require newer Apple SDK headers than old Command Line Tools provide.
- A common failure looks like missing `<source_location>` during `node-gyp rebuild`.
- On machines that cannot be updated further, a previously rebuilt Electron `32.3.3` bundle may still run even if a fresh local rebuild is no longer possible.
- In that case:
  - keep the installer changes in this repo
  - preserve a known-good patched `.app`
  - test the exact installed bundle with `./smoke-test.sh /Applications/Codex.app`

**Gatekeeper warning**
- Right‑click the app → Open (once) to allow it.

## Disclaimer

This project does not distribute OpenAI software. It automates the same conversion steps a user would perform locally using their own DMG.

## License

MIT
