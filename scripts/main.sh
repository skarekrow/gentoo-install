# shellcheck source=./scripts/protection.sh
source "$GENTOO_INSTALL_REPO_DIR/scripts/protection.sh" || exit 1


################################################
# Functions

function install_stage3() {
	prepare_installation_environment
	apply_disk_configuration
	download_stage3
	extract_stage3
}

function configure_base_system() {
	einfo "Generating locales"
	echo "$LOCALES" > /etc/locale.gen \
		|| die "Could not write /etc/locale.gen"
	locale-gen \
		|| die "Could not generate locales"

	# Set hostname
	einfo "Selecting hostname"
	sed -i "/hostname=/c\\hostname=\"$HOSTNAME\"" /etc/conf.d/hostname \
		|| die "Could not sed replace in /etc/conf.d/hostname"

	# Set timezone
	einfo "Selecting timezone"
	echo "$TIMEZONE" > /etc/timezone \
		|| die "Could not write /etc/timezone"
	chmod 644 /etc/timezone \
		|| die "Could not set correct permissions for /etc/timezone"
	try emerge -v --config sys-libs/timezone-data

	# Set keymap
	einfo "Selecting keymap"
	sed -i "/keymap=/c\\keymap=\"$KEYMAP\"" /etc/conf.d/keymaps \
		|| die "Could not sed replace in /etc/conf.d/keymaps"

	# Set locale
	einfo "Selecting locale"
	try eselect locale set "$LOCALE"

	# Update environment
	env_update
}

function configure_portage() {
	# Prepare /etc/portage for autounmask
	mkdir_or_die 0755 "/etc/portage/package.use"
	mkdir_or_die 0755 "/etc/portage/package.keywords"
	mkdir_or_die 0755 "/etc/portage/package.accept_keywords"
	touch_or_die 0644 "/etc/portage/package.license"

	getuto
	chmod 644 /etc/portage/gnupg/pubring.kbx \
		|| die "Could not chmod 644 /etc/portage/gnupg/pubring.kbx"

	cat > '/etc/portage/bashrc' << 'EOF'
# From /usr/share/doc/etckeeper*/bashrc.example
case "${EBUILD_PHASE}" in
        setup|prerm) etckeeper pre-install ;;
        postinst|postrm) etckeeper post-install ;;
esac
EOF

	cat > '/etc/portage/make.conf' << 'EOF'
# These settings were set by the catalyst build script that automatically
# built this stage.
# Please consult /usr/share/portage/config/make.conf.example for a more
# detailed example.
COMMON_FLAGS="-march=native -O2 -pipe"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"

# NOTE: This stage was built with the bindist Use flag enabled

# This sets the language of build output to English.
# Please keep this setting intact when reporting bugs.
LC_MESSAGES=C.utf8

# Appending getbinpkg to the list of values within the FEATURESvariable
FEATURES="${FEATURES} getbinpkg"
# Require signatures
FEATURES="${FEATURES} binpkg-request-signature"

USE="dist-kernel ipv6"

EMERGE_DEFAULT_OPTS="--jobs=10 --ask"
ACCEPT_LICENSE="*"
EOF

	cat > "/etc/portage/package.accept_keywords/installkernel" << 'EOF'
sys-kernel/installkernel **
sys-boot/uefi-mkconfig **
EOF

	cat > "/etc/portage/package.use/installkernel" << 'EOF'
sys-kernel/installkernel dracut efistub
EOF

	cat > "/etc/portage/package.use/linux-firmware" << 'EOF'
sys-kernel/linux-firmware initramfs bindist redistributable dist-kernel unknown-license
EOF

	cat > "/etc/portage/package.use/intel-microcode" << 'EOF'
sys-firmware/intel-microcode initramfs
EOF

	cat > "/etc/portage/package.use/sysklogd" << 'EOF'
app-admin/sysklogd logrotate
EOF

	chmod 644 /etc/portage/make.conf \
		|| die "Could not chmod 644 /etc/portage/make.conf"
	chmod 644 /etc/portage/bashrc \
		|| die "Could not chmod 644 /etc/portage/bashrc"
	chmod 644 /etc/portage/package.accept_keywords/installkernel \
		|| die "Could not chmod 644 /etc/portage/package.accept_keywords/installkernel"
	chmod 644 /etc/portage/package.use/installkernel \
		|| die "Could not chmod 644 /etc/portage/package.use/installkernel"
	chmod 644 /etc/portage/package.use/linux-firmware \
		|| die "Could not chmod 644 /etc/portage/package.use/linux-firmware"
	chmod 644 /etc/portage/package.use/intel-microcode \
		|| die "Could not chmod 644 /etc/portage/package.use/intel-microcode"
	chmod 644 /etc/portage/package.use/sysklogd \
		|| die "Could not chmod 644 /etc/portage/package.use/sysklogd"
}

function enable_sshd() {
	einfo "Installing and enabling sshd"
	enable_service sshd
}

function install_authorized_keys() {
	mkdir_or_die 0700 "/root/"
	mkdir_or_die 0700 "/root/.ssh"

	if [[ -n "$ROOT_SSH_AUTHORIZED_KEYS" ]]; then
		einfo "Adding authorized keys for root"
		touch_or_die 0600 "/root/.ssh/authorized_keys"
		echo "$ROOT_SSH_AUTHORIZED_KEYS" > "/root/.ssh/authorized_keys" \
			|| die "Could not add ssh key to /root/.ssh/authorized_keys"
	fi
}

function install_kernel() {
	# Install kernel
	einfo "Installing kernel and related tools"
	try emerge --verbose sys-kernel/linux-firmware sys-firmware/intel-microcode sys-boot/efibootmgr \
		sys-kernel/gentoo-kernel-bin sys-kernel/dracut sys-kernel/installkernel sys-boot/uefi-mkconfig
}

function install_sys_packages() {
	einfo "Installing standard sys packages"
	try emerge --verbose -- app-admin/doas app-admin/sysklogd app-misc/tmux app-portage/gentoolkit app-shells/bash-completion net-misc/chrony net-misc/netifrc sys-apps/etckeeper sys-apps/mlocate sys-apps/ripgrep sys-block/io-scheduler-udev-rules sys-fs/dosfstools sys-process/cronie net-misc/dhcpcd

	einfo "Enabling standard services"
	enable_service chronyd default
	enable_service cronie default
	enable_service sysklogd default
}

function install_my_packages() {
	einfo "Installing my packages"
	#try emerge --verbose -- app-backup/borgbackup app-backup/restic app-editors/helix 
}

function add_fstab_entry() {
	printf '%-46s  %-24s  %-6s  %-96s %s\n' "$1" "$2" "$3" "$4" "$5" >> /etc/fstab \
		|| die "Could not append entry to fstab"
}

function generate_fstab() {
	einfo "Generating fstab"
	install -m0644 -o root -g root "$GENTOO_INSTALL_REPO_DIR/contrib/fstab" /etc/fstab \
		|| die "Could not overwrite /etc/fstab"

	# EFI System Partition
	add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_EFI")" "/efi" "vfat" "umask=0077" "0 2"

	if [[ -v "DISK_ID_SWAP" ]]; then
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_SWAP")" "none" "swap" "sw" "0 0"
	fi
}

function main_install_gentoo_in_chroot() {
	[[ $# == 0 ]] || die "Too many arguments"

	maybe_exec 'before_install'

	# Remove the root password, making the account accessible for automated
	# tasks during the period of installation.
	einfo "Clearing root password"
	passwd -d root \
		|| die "Could not change root password"

	# Mount efi partition
	einfo "Creating EFI directory"
	mkdir_or_die 0700 "/efi"

	einfo "Mounting efi partition"
	mount_by_id "$DISK_ID_EFI" "/efi"

	# Create efi vendor directories
	einfo "Creating vendor directories"
	mkdir_or_die 0700 "/efi/EFI/Gentoo"

	einfo "Mounting efi vars"
	mount_efivars

	# Sync portage
	einfo "Syncing portage tree"
	try emerge-webrsync

	# Configure basic system things like timezone, locale, ...
	maybe_exec 'before_configure_base_system'
	configure_base_system
	maybe_exec 'after_configure_base_system'

	# Prepare portage environment
	maybe_exec 'before_configure_portage'
	configure_portage

	# Install git (for git portage overlays)
	einfo "Installing git and eselect-repository"
	try emerge --verbose dev-vcs/git app-eselect/eselect-repository 

	if [[ "$PORTAGE_SYNC_TYPE" == "git" ]]; then
		# https://wiki.gentoo.org/wiki/Portage_with_Git
		try eselect repository disable gentoo
		try eselect repository enable gentoo
		rm -rf /var/db/repos/gentoo \
			|| die "Could not delete obsolete rsync gentoo repository"
		try emaint sync -r gentoo
		try emaint sync -r gentoo
	fi
	maybe_exec 'after_configure_portage'

	einfo "Generating ssh host keys"
	try ssh-keygen -A

	# Install authorized_keys before dracut, which might need them for remote unlocking.
	install_authorized_keys

	# Generate a valid fstab file
	generate_fstab

	# Install kernel and initramfs
	maybe_exec 'before_install_kernel'
	install_kernel
	maybe_exec 'after_install_kernel'

	# Install standard system packages
	install_sys_packages

	# Install zfs kernel module and tools if we used zfs
	einfo "Installing zfs"
	try emerge --verbose sys-fs/zfs sys-fs/zfs-kmod

	einfo "Enabling zfs services"
	try rc-update add zfs-import boot
	try rc-update add zfs-mount boot
	try zgenhostid

	einfo "Reconfiguring kernel for zfs"
	try emerge --config sys-kernel/gentoo-kernel-bin

	einfo "Removing incorrect old entries"
	try rm -f /efi/EFI/Gentoo/*.old
	try rm -f /efi/EFI/gentoo/vmlinuz-*-old.efi

	einfo "Creating empty uefi-mkconfig config"
	try touch /etc/default/uefi-mkconfig

	einfo "Running uefi-mkconfig"
	try uefi-mkconfig

	if [[ $ENABLE_SSHD == "true" ]]; then
		enable_sshd
	fi

	# Install my standard set of packages
	install_my_packages

	# Install additional packages, if any.
	if [[ ${#ADDITIONAL_PACKAGES[@]} -gt 0 ]]; then
		einfo "Installing additional packages"
		# shellcheck disable=SC2086
		try emerge --verbose -- "${ADDITIONAL_PACKAGES[@]}"
	fi

	if ask "Do you want to assign a root password now?"; then
		try passwd root
		einfo "Root password assigned"
	else
		try passwd -d root
		ewarn "Root password cleared, set one as soon as possible!"
	fi

	# If configured, change to gentoo testing at the last moment.
	# This is to ensure a smooth installation process. You can deal
	# with the blockers after installation ;)
	if [[ $USE_PORTAGE_TESTING == "true" ]]; then
		einfo "Adding ~$GENTOO_ARCH to ACCEPT_KEYWORDS"
		echo "ACCEPT_KEYWORDS=\"~$GENTOO_ARCH\"" >> /etc/portage/make.conf \
			|| die "Could not modify /etc/portage/make.conf"
	fi

	maybe_exec 'after_install'

	# Upgrade and make sure use flags are correct
	einfo "Emerging -avuDN @world"
	try emerge -avuDN @world

	einfo "emerge --depclean"
	try emerge --depclean

	einfo "Gentoo installation complete."
	einfo "You may now reboot your system or execute ./install --chroot $ROOT_MOUNTPOINT to enter your system in a chroot."
	einfo "Chrooting in this way is always possible in case you need to fix something after rebooting."
}

function main_install() {
	[[ $# == 0 ]] || die "Too many arguments"

	gentoo_umount
	install_stage3

	mount_efivars
	gentoo_chroot "$ROOT_MOUNTPOINT" "$GENTOO_INSTALL_REPO_BIND/install" __install_gentoo_in_chroot
}

function main_chroot() {
	# Skip if already mounted
	mountpoint -q -- "$1" \
		|| die "'$1' is not a mountpoint"

	gentoo_chroot "$@"
}
