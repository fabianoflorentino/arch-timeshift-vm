# Maintainer: Fabiano Santos Florentino <fabianofs@archlinux.org>
# shellcheck disable=SC2034
pkgname=arch-timeshift-vm
pkgdesc="Restore an Arch Linux Timeshift/BTRFS snapshot into a disposable bootable libvirt/KVM VM"
pkgrel=1
arch=('any')
url="https://github.com/fabianoflorentino/arch-timeshift-vm"
license=('MIT')
depends=('python' 'python-pip')
makedepends=('git')
# The tool provisions its own virtualenv on the host via `arch-timeshift-vm
# install`; the package itself only ships the sources and the wrapper.
source=("$pkgname::$url.git#tag=v$pkgver")
sha256sums=('SKIP')

pkgver() {
  git describe --tags --always | sed 's/^v//; s/-/+/g'
}

package() {
  cd "$pkgname"
  install -d "$pkgdir/usr/share/arch-timeshift-vm"
  cp -a ansible.cfg config.example.yml Makefile README.md LICENSE CHANGELOG.md \
    CONTRIBUTING.md requirements.yml requirements-dev.txt PKGBUILD \
    group_vars inventory playbooks roles scripts sudoers docs \
    "$pkgdir/usr/share/arch-timeshift-vm/"

  install -d "$pkgdir/usr/bin"
  ln -s /usr/share/arch-timeshift-vm/scripts/arch-timeshift-vm \
    "$pkgdir/usr/bin/arch-timeshift-vm"

  install -d "$pkgdir/usr/share/licenses/$pkgname"
  install -Dm644 "$pkgname/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}

# post_install message guiding the operator through the first run.
# shellcheck disable=SC2034
install=arch-timeshift-vm.install