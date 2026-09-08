# Maintainer: local package generated for CachyOS/Arch Linux

pkgname=chatgpt
_default_upstream_version=26.901.51231
_default_upstream_sha256=62580188d87c3d3a9369dab7c73b42a8a32518d4df8a2d5bae6466ddeac5c05e
pkgver="${CHATGPT_UPSTREAM_VERSION:-${_default_upstream_version}}"
pkgrel=2
pkgdesc='Official ChatGPT desktop preview repackaged for Arch Linux and CachyOS'
arch=('x86_64')
url='https://chatgpt.com/download/'
license=('LicenseRef-custom')
options=('!strip' '!debug')
provides=(
  "chatgpt-desktop=${pkgver}"
)
conflicts=(
  'chatgpt-desktop'
)

depends=(
  'alsa-lib'
  'at-spi2-core'
  'cairo'
  'coreutils'
  'curl'
  'dbus'
  'expat'
  'fakeroot'
  'gdk-pixbuf2'
  'glib2'
  'glibc'
  'gnupg'
  'graphite'
  'gtk3'
  'libcups'
  'libarchive'
  'libdrm'
  'libgcc'
  'libglvnd'
  'libnotify'
  'libpulse'
  'libstdc++'
  'libusb'
  'libx11'
  'libxcb'
  'libxcomposite'
  'libxdamage'
  'libxext'
  'libxfixes'
  'libxkbcommon'
  'libxrandr'
  'mesa'
  'nspr'
  'nss'
  'pango'
  'pacman'
  'systemd-libs'
  'sh'
  'util-linux'
  'xdg-utils'
)

optdepends=(
  'apparmor: load the bundled user-namespace profile when AppArmor is enabled'
  'git: Git repository integration'
  'gtk4: GTK 4 backend when launched with --gtk-version=4'
  'kde-cli-tools: move deleted files to the Plasma trash'
  'kdialog: show the launch-time update prompt under KDE Plasma'
  'org.freedesktop.secrets: store credentials using a Secret Service backend'
  'pipewire: WebRTC screen sharing under Wayland'
  'polkit: authorize installation of updates from the desktop prompt'
  'qt6-tools: update the KDE progress window through qdbus6'
  'zenity: show the launch-time update prompt outside KDE Plasma'
)

backup=('etc/apparmor.d/chatgpt')
install='chatgpt.install'
_upstream_deb_url="${CHATGPT_UPSTREAM_URL:-https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${pkgver}_amd64.deb}"
source=(
  "chatgpt_${pkgver}_amd64.deb::${_upstream_deb_url}"
  'chatgpt-launcher.sh'
  'install-local.sh'
  'launch-update-check.sh'
  'chatgpt.install'
  'openai-codex-linux-repository.key'
)
noextract=("chatgpt_${pkgver}_amd64.deb")
sha256sums=(
  "${CHATGPT_UPSTREAM_SHA256:-${_default_upstream_sha256}}"
  'fd1805c09569505b6448c2a802b8937040dedf65d035ee7d1f0cf55418e7c1d8'
  '528e884275b3aeeb263510a43cd8cbaa889ae747398b41c9a2c7ddf98e10ac06'
  'b19bfefac8b53bfa10eb45531872e3d9ba3f14e8b72ae073778c91751092db56'
  '4b620bae786d4b6559a7eeb520e511311f5f87893734c17c7b4dfba0f5f9a8c2'
  '6c8933f828af390b2457f9e2d234082d783d6e4bb1911615b4861c6c61f4ea5a'
)

package() {
  local deb_file="${srcdir}/chatgpt_${pkgver}_amd64.deb"
  local data_member
  data_member=$(bsdtar -tf "${deb_file}" | awk '/^data\.tar\./ { print; exit }')
  [[ -n "${data_member}" ]] || return 1
  bsdtar -xOf "${deb_file}" "${data_member}" |
    bsdtar --no-same-owner -xf - -C "${pkgdir}"

  install -Dm644 "${pkgdir}/usr/share/doc/chatgpt/copyright" \
    "${pkgdir}/usr/share/licenses/${pkgname}/copyright"
  ln -s /usr/lib/chatgpt/LICENSES.chromium.html \
    "${pkgdir}/usr/share/licenses/${pkgname}/LICENSES.chromium.html"

  rm -rf "${pkgdir}/usr/share/doc" "${pkgdir}/usr/share/lintian"

  # Keep the upstream application untouched and route desktop/CLI launches
  # through a small update check before invoking the official launcher.
  rm -f "${pkgdir}/usr/bin/chatgpt"
  install -Dm755 "${srcdir}/chatgpt-launcher.sh" \
    "${pkgdir}/usr/bin/chatgpt"
  install -Dm755 "${srcdir}/chatgpt-launcher.sh" \
    "${pkgdir}/usr/lib/chatgpt-arch-updater/chatgpt-launcher.sh"

  install -Dm755 "${srcdir}/install-local.sh" \
    "${pkgdir}/usr/lib/chatgpt-arch-updater/install-local.sh"
  install -Dm755 "${srcdir}/launch-update-check.sh" \
    "${pkgdir}/usr/lib/chatgpt-arch-updater/launch-update-check.sh"
  install -Dm644 "${startdir}/PKGBUILD" \
    "${pkgdir}/usr/lib/chatgpt-arch-updater/PKGBUILD"
  install -Dm644 "${srcdir}/chatgpt.install" \
    "${pkgdir}/usr/lib/chatgpt-arch-updater/chatgpt.install"
  install -Dm644 "${srcdir}/openai-codex-linux-repository.key" \
    "${pkgdir}/usr/lib/chatgpt-arch-updater/openai-codex-linux-repository.key"
}
