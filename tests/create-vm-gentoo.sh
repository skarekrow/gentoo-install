#!/bin/bash

virt-install \
	--connect=qemu:///system \
	--name=gentoo-install-test \
	--vcpus=2 \
	--memory=8192 \
	--cdrom=/var/tmp/catalyst/builds/23.0-default/install-amd64-minimal-20240628.zfs.iso \
	--disk size=20 \
	--boot uefi \
	--os-variant=gentoo \
	--noautoconsole \
	--graphics none
#	--transient \
	# --console pty,target.type=virtio \
	# --serial pty \
	# --extra-args 'console=ttyS0,115200n8 --- console=ttyS0,115200n8' \

# virsh
# virsh destroy gentoo-install-test && virsh undefine --nvram gentoo-install-test && rm -f /var/lib/libvirt/images/gentoo-install-test*
