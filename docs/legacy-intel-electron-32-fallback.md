# Legacy Intel Mac: Electron 32 Fallback

## Summary

This repo was validated on an older Intel Mac running macOS 12.7.6 where the current Codex desktop packaging path could not be made reliable on newer Electron builds such as `40.x`.

The stable working path on that machine was:

- app bundle version: `26.325.31654`
- Electron runtime: `32.3.3`
- architecture: `x86_64`

## Observed Failure Mode

On the affected machine, newer rebuild attempts could fail in more than one way:

- blank or black window during startup
- startup path trying to use a dev-server URL such as `http://localhost:5175`
- `/Applications/Codex.app` still failing even though `./codex-app/Codex.app` worked

In one reproduced case, the repo-local app launched correctly while the installed `/Applications/Codex.app` was still an older broken bundle.

## Root Cause In This Case

There were two separate problems:

1. The wrong app bundle was being launched from Finder.
   The working patched bundle lived under `./codex-app/`, but `/Applications/Codex.app` still contained the older `app.asar`.

2. On Electron `32.3.3`, the desktop main-process logic needed stricter guarding around the renderer URL path.
   The bundle could still enter the dev-server code path when `app.isPackaged` was not behaving the way the original app expected after repackaging.

The working fix was to force the dev-server branch to run only when `process.env.ELECTRON_RENDERER_URL` is actually set.

## Why Not Just Rebuild On That Mac

That specific machine also had an old Apple toolchain:

- active developer directory: `/Library/Developer/CommandLineTools`
- no full Xcode installed
- Apple clang 14
- SDK 13.1

Fresh native rebuilds for Electron fallback targets failed because the local SDK headers were too old for required C++20 headers such as `<source_location>`.

So the machine could run a known-good Electron `32.3.3` app bundle, but could not reliably produce that bundle from scratch without a newer Apple toolchain.

## Practical Guidance

If you are maintaining another older Intel Mac:

1. Try the normal path first.

```bash
./install.sh /path/to/Codex.app
```

2. If the app opens blank or black, try Electron `32.3.3`.

```bash
./install.sh --electron-version 32.3.3 /path/to/Codex.app
```

3. If the repo-local app works but Finder launch does not, replace `/Applications/Codex.app` with the verified working bundle from `./codex-app/`.

4. Validate the exact installed bundle.

```bash
./smoke-test.sh /Applications/Codex.app
```

## Current Repo Changes Supporting This

The repo now includes:

- explicit Electron version override support via `--electron-version`
- ABI-aware `node-pty` target directory handling
- stronger main-bundle patching for the dev-server branch
- a direct-launch smoke test script for local verification

## Limits

This does not prove Electron `40.x` can never work on old Intel Macs. It documents one real machine where:

- Electron `32.3.3` was the practical stable fallback
- the machine could not be upgraded enough to perform a fresh clean rebuild locally
- the installed app had to be replaced with the already-verified working bundle
