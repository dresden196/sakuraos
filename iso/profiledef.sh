#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="sakura"
iso_label="SAKURA_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="SakuraOS <https://sakuraos.org>"
iso_application="SakuraOS Live Installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="sakura"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
# releng uses xz, which costs ~15 minutes of squashfs time on a Plasma-sized
# rootfs. zstd is a few percent larger and several times faster, which matters
# far more while the ISO is being rebuilt many times a day.
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  # sudo refuses to read a drop-in that is group- or world-writable
  ["/etc/sudoers.d/10-sakura-live"]="0:0:440"
  # polkit ignores a rules file it does not trust the ownership of, and does
  # so quietly -- the rule simply never applies and the password dialog comes
  # back with no explanation.
  ["/etc/polkit-1/rules.d/49-sakura-live-install.rules"]="0:0:644"
)
