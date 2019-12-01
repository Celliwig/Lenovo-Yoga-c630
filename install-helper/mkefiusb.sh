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
	-d <device name>	- Target device (mandatory).
	-g			- Build grub (optional).
	-k <kernel package>	- Kernel package to include (optional).
	-m <module name>	- Load named module on startup (optional).

'-m' can be specified multiple times.
EOF
	exit 1
}

BLOCK_DEVICE=""
INSTALL_GRUB=false
KERNEL_PACKAGE=""
MODULE_LIST=()
# Pass arguments
while getopts ":d:gk:m:" opt; do
	case $opt in
		d)
			if [[ "${BLOCK_DEVICE}" == "" ]]; then
				BLOCK_DEVICE="${OPTARG}"
			else
				print_usage
			fi
			;;
		g)
			INSTALL_GRUB=true
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
# If target not specified, print usage and exit
if [ -z "${BLOCK_DEVICE}" ]; then print_usage; fi

echo -e "${TXT_UNDERLINE}Running sanity checks: ${TXT_NORMAL}"
echo -n "	Checking target is block device: "
BLOCK_DEVNAME=`basename "${BLOCK_DEVICE}"`
if [ -e /sys/block/"${BLOCK_DEVNAME}" ]; then
	echo "Okay"
else
	echo "Failed"
	exit 1
fi
echo -n "	Check target device is not mounted: "
mount |grep "${BLOCK_DEVICE}" &> /dev/null
if [ $? -ne 0 ]; then
	echo "Okay"
else
	echo "Failed"
	exit 1
fi
if [ -n "${KERNEL_PACKAGE}" ]; then
	echo -n "	Checking kernel package [\"${KERNEL_PACKAGE}\"] type: "
	KERNEL_PACKAGE_TYPE=`identify_package_type "${KERNEL_PACKAGE}"`
	if [[ "${KERNEL_PACKAGE_TYPE}" == "unknown" ]]; then
		echo "Failed"
		exit 1
	else
		echo "${KERNEL_PACKAGE_TYPE}"
	fi
fi
echo

read -r -p "ARE YOU SURE YOU WISH TO CONTINUE? THIS WILL ERASE: "${BLOCK_DEVICE}". (y/N): " BLOCK_DEVICE_CONFIRM
if [[ $BLOCK_DEVICE_CONFIRM = [Yy] ]]; then
	echo
	echo -e "${TXT_UNDERLINE}Create an EFI compatible USB key...${TXT_NORMAL}"
else
	echo "Operation canceled"
	exit 1
fi

#if "${INSTALL_GRUB}"; then
#	echo -e "${TXT_UNDERLINE}Install GRUB...${TXT_NORMAL}"
#	if [ -d "${DIR_GRUB}" ]; then
#		echo "	${DIR_GRUB} already exist..."
#		read -r -p "	Update existing repo? (y/n): " INSTALL_GRUB_GIT_UPDATE
#		if [[ $INSTALL_GRUB_GIT_UPDATE = [Yy] ]]; then
#			cd "${DIR_GRUB}"
#			git pull &> /dev/null
#			retval="${?}"
#			cd "${CWD}"
#			if [ "${retval}" -ne 0 ]; then
#				echo "	git pull failed!!!"
#				exit 1
#			fi
#		fi
#	else
#		echo "	No GRUB repo."
#		read -r -p "	Clone GRUB repository? (y/n): " INSTALL_GRUB_GIT_CLONE
#		if [[ ${INSTALL_GRUB_GIT_CLONE} = [Yy] ]]; then
#			git clone https://git.savannah.gnu.org/git/grub.git "${DIR_GRUB}" &> /dev/null
#			retval="${?}"
#			if [ "${retval}" -ne 0 ]; then
#				echo "	git clone failed!!!"
#				exit 1
#			fi
#		fi
#	fi
#	if [ -d "${DIR_GRUB}" ]; then
#		cd "${DIR_GRUB}"
#		./autogen.sh
#		./configure --with-platform=efi --target=aarch64
#		export EFI_ARCH=
#		cd "${CWD}"
#	fi
#	echo
#fi
