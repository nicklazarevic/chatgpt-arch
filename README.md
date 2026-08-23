# ChatGPT desktop for Arch Linux / CachyOS

This directory contains a native Arch package recipe that repackages the official
OpenAI Linux app without modifying the ChatGPT executable or application
resources.

## Provenance

- Upstream version: `26.818.21641`
- Upstream architecture: `amd64` / Arch `x86_64`
- Official download host: `persistent.oaistatic.com`
- Upstream DEB SHA-256:
  `e138b8e8008f2b90071e1b19f9cef1125c5ed7710e68fd9c87e6655285d68f6a`
- OpenAI repository signing-key fingerprint:
  `3BFA 0E4A E8B8 CC16 A2D9 BA68 4A3B 4A56 6C46 60E4`

The upstream checksum was read from OpenAI's signed Debian repository metadata,
and the repository signature was verified before this package was built.

## Install

Run the installer. It checks OpenAI's signed repository first, builds the
`chatgpt` Arch package when necessary, and then invokes pacman:

```sh
./install-local.sh
```

No ChatGPT binary, upstream DEB, or prebuilt Arch package is stored in this
repository. When installation or an update is needed, the installer downloads
the current DEB directly from OpenAI's signed repository, verifies its checksum,
and builds the Arch package locally.

Nothing runs in the background. Every launch through the desktop entry or the
`chatgpt` command checks OpenAI's signed repository. When an update exists, a
dialog shows the installed and available versions:

- **Update** shows a progress window while it downloads, verifies, and builds
  the new package. It then asks for authorization, installs the package,
  removes the downloaded build artifacts, and opens ChatGPT.
- **Later** opens the currently installed ChatGPT immediately.

If the check cannot be completed, for example while offline, ChatGPT opens
normally. A second launch never waits for an update dialog or build already in
progress. Polkit asks for authorization only when pacman is ready to install a
newly built package.

To skip the launch-time check once, run:

```sh
CHATGPT_SKIP_UPDATE_CHECK=1 chatgpt
```

To check without building or installing anything, use
`./install-local.sh --check`. To build the latest package without installing
it, use `./install-local.sh --build-only`. All installer and dialog text is in
English.

Then launch **ChatGPT** from the application menu or run:

```sh
chatgpt
```

The official app defaults to XWayland in a Wayland session. Native Wayland is
experimental and can be selected explicitly with:

```sh
chatgpt --ozone-platform=wayland
```

## Rebuild

The package can be reproduced with:

```sh
mkdir -p dist
PKGDEST="$PWD/dist" makepkg --cleanbuild
```

OpenAI only configures package-manager updates directly for its supported
DEB/RPM distributions. This installer provides an on-launch equivalent for
Arch/CachyOS and does not add an APT or DNF repository.

Official documentation:
<https://learn.chatgpt.com/docs/linux/linux-app>
