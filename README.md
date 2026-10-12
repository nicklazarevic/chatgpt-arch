# ChatGPT desktop for Arch Linux / CachyOS

A native Arch package recipe for the official OpenAI Linux app. It repackages
ChatGPT without modifying its executable or application resources and checks
for ChatGPT updates when you open the app.

## Install

Requires Arch Linux or CachyOS on **x86_64**, an internet connection and a
regular user account with sudo access. Install the prerequisites, then clone
and run the installer as your regular user:

```sh
sudo pacman -S --needed base-devel git curl gnupg
git clone https://github.com/nicklazarevic/chatgpt-arch.git
cd chatgpt-arch
./install-local.sh
```

The installer checks OpenAI's signed repository, downloads and verifies the
current DEB, builds an Arch package locally, and invokes pacman. If makepkg
reports missing runtime dependencies, install the packages it lists with
`sudo pacman -S --needed <packages>`, then rerun the installer.

For update dialogs on KDE Plasma:

```sh
sudo pacman -S --needed kdialog qt6-tools polkit
```

On other desktops, install `zenity` and `polkit` instead, and ensure your desktop
has a running Polkit authentication agent. Without a dialog tool, the launcher
opens ChatGPT without offering an update; the terminal installer still works.

Launch **ChatGPT** from the application menu or run `chatgpt`.

## Updates

Every launch checks OpenAI's signed repository before opening ChatGPT. The
initial check has a **five-second timeout**, with at most one extra second to
terminate an unresponsive check. If it fails or times out, ChatGPT opens normally.
A second launch does not wait for an update dialog or build already in progress.

When a newer version is available:

- **Update** shows the current phase: download, verification, package preparation
  and installation. Polkit asks for authorization when the package is ready.
  After installation, build downloads and packages are removed and ChatGPT opens.
- **Later** opens the currently installed ChatGPT immediately.

The update reuses the metadata downloaded by that launch and verifies its
signature and checksum again before building. There are no scheduled services.
The updater downloads ChatGPT from OpenAI; it does not fetch or execute scripts
from GitHub. All installer and dialog text is in English.

To skip the check once:

```sh
CHATGPT_SKIP_UPDATE_CHECK=1 chatgpt
```

### Launch the clean installed app

If you use a separate Voice overlay, its mount namespace can make the installed
archive appear to be the overlay to commands run inside the app. The host's
installed archive is a separate file.

From this checkout, verify the host archive without launching anything:

```sh
./launch-clean.sh --check
```

To use the clean installed app, quit all ChatGPT windows, then run:

```sh
./launch-clean.sh
```

The helper starts ChatGPT through the systemd user service manager, outside any
inherited overlay mount, and skips the update check. It refuses to launch while
ChatGPT is running because an existing process would reuse the overlay session.
It does not change your Voice profile, application settings, desktop entry, or
overlay files. The installed app's normal settings still apply.

From the cloned repository:

```sh
./install-local.sh --check       # Check only
./install-local.sh --build-only  # Build even if already installed; do not install
./install-local.sh               # Install or update if needed
```

`--build-only` prints the package path under `dist/` and respects makepkg's
configured compression format.

## Troubleshooting

If an update fails, ChatGPT can still open using the installed version. The error
dialog distinguishes cancelled authorization, authorization/startup failure,
and a pacman error. Use **Show details** to inspect the error output.

The last failed desktop update log is saved with user-only access at:

```text
~/.local/state/chatgpt-arch-updater/last-error.log
```

If `XDG_STATE_HOME` is set, the log is stored under that directory instead.
When requesting help, include the relevant error and the output of
`pacman -Q chatgpt`; review the log before sharing it.

- **App will not open:** try `CHATGPT_SKIP_UPDATE_CHECK=1 chatgpt` in a terminal
  to see the application's own output.
- **Download checksum failure:** rerun the updater to download the file again.
  Signature/checksum failures are never bypassed.
- **Pacman database locked:** let the other package transaction finish, then
  retry the update.
- **Package needs repair:** run `./install-local.sh --build-only`, then install
  the printed path with `sudo pacman -U /path/to/chatgpt-package.pkg.tar.zst`
  (use the actual filename and extension).

For an explicit native Wayland launch:

```sh
chatgpt --ozone-platform=wayland
```

## Uninstall

```sh
sudo pacman -R chatgpt
```

This removes the installed package and its launcher. Personal ChatGPT data and
per-user updater files are retained. The updater's build cache is normally at
`~/.local/share/chatgpt-arch-updater/` (or under `XDG_DATA_HOME`, when set).

## Provenance and direct builds

No ChatGPT binary, upstream DEB, or prebuilt Arch package is stored in this
repository. The installer verifies OpenAI's repository signature, the package
index checksum, and the DEB checksum before building.

- Download host: `persistent.oaistatic.com`
- Architecture: OpenAI `amd64` / Arch `x86_64`
- Repository signing-key fingerprint:
  `3BFA 0E4A E8B8 CC16 A2D9 BA68 4A3B 4A56 6C46 60E4`

The version `26.901.51231` and checksum
`62580188d87c3d3a9369dab7c73b42a8a32518d4df8a2d5bae6466ddeac5c05e`
in `PKGBUILD` are a **pinned reference for direct makepkg builds** and are not
updated automatically. `install-local.sh` reads the current version and checksum
from OpenAI's signed metadata instead. `pkgrel` is the local Arch packaging
revision; it is independent of the upstream ChatGPT version.

To build the pinned reference directly:

```sh
mkdir -p dist
PKGDEST="$PWD/dist" makepkg --cleanbuild
```

The launcher scripts and repository key are declared as package sources with
SHA-256 checksums. If you edit them, regenerate their checksums in `PKGBUILD`
before building. Changes to these scripts are installed by rebuilding from an
updated checkout; the ChatGPT update check does not update this repository.

Official application documentation:
<https://learn.chatgpt.com/docs/linux/linux-app>
