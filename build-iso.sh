#!/bin/bash
set -eu
[ "$(id -u)" = 0 ] || exec sudo -E "$0" "$@"
here=$(cd "$(dirname "$0")" && pwd)
GH=https://github.com/gh0st-8221
B=${BUILD:-/tmp/ghostos-build}
OUT=${OUT:-$here/out}
pacman -S --needed --noconfirm archiso base-devel git gnu-efi || { echo "pacman failed"; exit 1; }

rm -rf "$B"
rm -f "$OUT"/ghostos-*.iso
STAMP=$(date +%Y.%m.%d-%H%M)
mkdir -p "$B" "$OUT"

git clone -q --depth 1 "$GH/ginit.git" "$B/ginit"
sed -i 's|{"/usr/bin/agetty", "--noissue", "--nohostname", "tty1", "linux", 0},|{"/usr/bin/agetty", "-a", "root", "--noissue", "--nohostname", "tty1", "linux", 0},|' "$B/ginit/config.h"
grep -q '"-a", "root"' "$B/ginit/config.h" || { echo "ginit config.h changed, fix the sed in build-iso.sh"; exit 1; }
make -C "$B/ginit" ginit poweroff reboot >/dev/null

git clone -q --depth 1 "$GH/gboot.git" "$B/gboot"
sed -i 's|^#define CONF_PATH2 .*|#define CONF_PATH2 "\\\\loader\\\\entries\\\\00-gboot.conf"|' "$B/gboot/main.c"
grep -q '00-gboot.conf' "$B/gboot/main.c" || { echo "gboot main.c changed, fix the sed in build-iso.sh"; exit 1; }
make -C "$B/gboot" >/dev/null

P=$B/profile
cp -r /usr/share/archiso/configs/releng "$P"
A=$P/airootfs
install -Dm755 "$B/ginit/ginit"    "$A/usr/local/bin/ginit"
install -Dm755 "$B/ginit/poweroff" "$A/usr/local/bin/poweroff"
install -Dm755 "$B/ginit/reboot"   "$A/usr/local/bin/reboot"
install -Dm755 "$here/ghostosinstall" "$A/usr/local/bin/ghostosinstall"
install -Dm755 "$here/live/rc"     "$A/etc/ginit/rc"
install -Dm755 "$B/ginit/stop"     "$A/etc/ginit/stop"
install -Dm644 "$here/live/main.conf" "$A/etc/iwd/main.conf"
install -Dm644 "$here/live/zlogin" "$A/root/.zlogin"
install -Dm644 "$here/live/motd"   "$A/etc/motd"
printf 'build: %s\n\n' "$STAMP" >> "$A/etc/motd"
echo ghostos > "$A/etc/hostname"
rm -f "$A/etc/resolv.conf"; : > "$A/etc/resolv.conf"

for p in git gptfdisk curl nano iwd dhcpcd efibootmgr fastfetch; do
	grep -qx "$p" "$P/packages.x86_64" || echo "$p" >> "$P/packages.x86_64"
done
sed -i -e 's/^iso_name=.*/iso_name="ghostos"/' \
	-e 's/^iso_label=.*/iso_label="GHOSTOS"/' \
	-e "s/^iso_version=.*/iso_version=\"$STAMP\"/" \
	-e 's/^iso_application=.*/iso_application="GhostOS installer"/' \
	-e "/^bootmodes=(/,/)/c\\bootmodes=('uefi.systemd-boot')" "$P/profiledef.sh"
sed -i '/^file_permissions=(/a\  ["/usr/local/bin/ghostosinstall"]="0:0:755"\n  ["/usr/local/bin/ginit"]="0:0:755"\n  ["/usr/local/bin/poweroff"]="0:0:755"\n  ["/usr/local/bin/reboot"]="0:0:755"\n  ["/etc/ginit/rc"]="0:0:755"\n  ["/etc/ginit/stop"]="0:0:755"' "$P/profiledef.sh"
grep -q "bootmodes=('uefi.systemd-boot')" "$P/profiledef.sh" || { echo "profiledef.sh not patched"; exit 1; }

rm -f "$P"/efiboot/loader/entries/*
install -m644 "$here/live/gboot.conf" "$P/efiboot/loader/entries/00-gboot.conf"
install -m644 "$B/gboot/gbootx64.efi" "$P/efiboot/gbootx64.efi"

M=$B/mkarchiso
cp "$(command -v mkarchiso)" "$M"
src='${pacstrap_dir}/usr/lib/systemd/boot/efi/systemd-boot${target_arch,,}.efi'
[ "$(grep -cF "$src" "$M")" = 1 ] || { echo "mkarchiso layout changed, cannot swap the boot loader"; exit 1; }
sed -i "s|$(printf '%s' "$src" | sed 's/[][\.*^$|/]/\\&/g')|\${profile}/efiboot/gbootx64.efi|" "$M"
grep -q 'efiboot/gbootx64.efi' "$M" || { echo "mkarchiso patch failed"; exit 1; }

bash "$M" -v -w "$B/work" -o "$OUT" "$P"
ls -l "$OUT"
