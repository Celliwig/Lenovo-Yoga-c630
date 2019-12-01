#!/bin/bash

. ./shared_functions

print_usage() {
	cat << EOF
Usage: mkefiusb.sh [OPTIONS]
Utility to build an EFI boot compatible USB key.
Will split the device into two, 2G for EFI, and a ext3 partition for everything else.

Kernel package (Debian/RedHat supported) is optional.
If the kernel package is specified it is included on the EFI partition, and in the initrd image.

Options:
	-d <device name>	- Device to prep.
	-g <grub package>	- Grub EFI package (optional).
	-k <kernel package>	- Kernel package to include (optional).
	-m <module name>	- Load named module on startup (optional).

'-m' can be specified multiple times.
EOF
	exit 1
}

BLOCK_DEVICE=""
GRUB_PACKAGE=""
KERNEL_PACKAGE=""
MODULE_LIST=()
# Pass arguments
while getopts ":k:m:" opt; do
	case $opt in
		d)
			if [[ "${BLOCK_DEVICE}" == "" ]]; then
				BLOCK_DEVICE="${OPTARG}"
			else
				print_usage
			fi
			;;
		g)
			if [[ "${GRUB_PACKAGE}" == "" ]]; then
				GRUB_PACKAGE="${OPTARG}"
			else
				print_usage
			fi
			;;
		k)
			if [[ "${KERNEL_PACKAGE}" == "" ]]; then
				KERNEL_PACKAGE="${OPTARG}"
			else
				print_usage
			fi
			;;
		m)
			MODULE_LIST+=("${OPTARG}")
			;;
		\?)
			print_usage
			;;
	esac
done

echo -e "${TXT_UNDERLINE}Create an EFI compatible USB key...${TXT_NORMAL}"
