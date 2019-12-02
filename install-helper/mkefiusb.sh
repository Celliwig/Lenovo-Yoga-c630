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
	echo -n "	Checking kernel package type (${KERNEL_PACKAGE}): "
	KERNEL_PACKAGE_TYPE=`identify_package_type "${KERNEL_PACKAGE}"`
	if [[ "${KERNEL_PACKAGE_TYPE}" == "unknown" ]]; then
		echo "Failed"
		exit 1
	else
		echo "${KERNEL_PACKAGE_TYPE}"
	fi
fi
echo

read -r -p "ARE YOU SURE YOU WISH TO CONTINUE? (y/N): " DOCONTINUE
if [[ $DOCONTINUE = [Yy] ]]; then
	sudo ls &> /dev/null								# Sudo now so we aren't prompted later
	echo
else
	echo "Operation canceled"
	exit 1
fi

echo -e "${TXT_UNDERLINE}Partition and format: ${BLOCK_DEVICE}${TXT_NORMAL}"
read -r -p "	Partition device (y/N): " BLOCK_DEVICE_PARTITION
if [[ $BLOCK_DEVICE_PARTITION = [Yy] ]]; then
	echo "	Creating an EFI compatible USB key."
	echo -n "	Wiping partition table: "
	sudo sgdisk --zap-all "${BLOCK_DEVICE}" &> /dev/null
	okay_failedexit $?
	echo -n "	Create EFI System partition (2G): "
	sudo sgdisk --new=1:0:+2G --typecode=1:ef00 "${BLOCK_DEVICE}" &> /dev/null
	okay_failedexit $?
	echo -n "	Creating linux filesystem partition (rest): "
	sudo sgdisk --new=2:+2G:0 --typecode=2:8300 "${BLOCK_DEVICE}" &> /dev/null
	okay_failedexit $?
	echo -n "	Formating EFI System partition (VFAT): "
	sudo mkfs.vfat -F32 -n IHEFI "${BLOCK_DEVICE}1" &> /dev/null
	okay_failedexit $?
	echo -n "	Formating linux filesystem partition: "
	sudo mkfs.ext3 -F -L IHFILES "${BLOCK_DEVICE}2" &> /dev/null
	okay_failedexit $?
	echo
fi

# Wait a little time so that /dev/disk is updated
sleep 5

if [ -e /dev/disk/by-label/IHEFI ] && [ -e /dev/disk/by-label/IHFILES ]; then
	echo -e "${TXT_UNDERLINE}Copying system files${TXT_NORMAL}"
	if [ ! -d "${DIR_USBKEY}" ]; then
		echo -n "       Creating output directory: "
		mkdir -p "${DIR_USBKEY}" &> /dev/null
		okay_failedexit $?
	fi
	echo -n "	Mounting EFI System partition: "
	sudo mount -t vfat /dev/disk/by-label/IHEFI "${DIR_USBKEY}" -o uid=1000,gid=1000,umask=022 &> /dev/null
	okay_failedexit $?
	if [ ! -d "${DIR_EFI_BOOT}" ]; then
		echo -n "	Creating EFI boot directory: "
		mkdir -p "${DIR_EFI_BOOT}" &> /dev/null
		okay_failedexit $?
	fi

	if [[ "${KERNEL_PACKAGE}" != "" ]]; then
		echo -e "${TXT_UNDERLINE}Install kernel${TXT_NORMAL}"
		KERNEL_PACKAGE_TYPE=`identify_package_type "${KERNEL_PACKAGE}"`
		echo "  Kernel package type identified as: ${KERNEL_PACKAGE_TYPE}"

		KERNEL_PACKAGE_NAME=`basename "${KERNEL_PACKAGE}"`
		case "${KERNEL_PACKAGE_TYPE}" in
			"debian")
				echo -n "       Extracting ${KERNEL_PACKAGE_NAME}: "
				KERNEL_PACKAGE_TEMPDIR=`deb_package_extract "${KERNEL_PACKAGE}"`
				okay_failedexit $?
				;;
			"redhat")
				echo -n "       Extracting ${KERNEL_PACKAGE_NAME}: "
				KERNEL_PACKAGE_TEMPDIR=`rpm_package_extract "${KERNEL_PACKAGE}"`
				okay_failedexit $?
				;;
			*)
				exit -1
				;;
		esac

		echo -n "       Copying kernel package contents from ${KERNEL_PACKAGE_TEMPDIR} to USB key: "
		cp -a "${KERNEL_PACKAGE_TEMPDIR}"/* "${DIR_USBKEY}"
		okay_failedexit $?
		sudo rm -rf "${KERNEL_PACKAGE_TEMPDIR}"
	fi

	if "${INSTALL_GRUB}"; then
		echo -e "${TXT_UNDERLINE}Install GRUB${TXT_NORMAL}"
		if [ -d "${DIR_GRUB}" ]; then
			echo "	${DIR_GRUB} already exists"
			read -r -p "	Update existing repo? (y/n): " INSTALL_GRUB_GIT_UPDATE
			if [[ $INSTALL_GRUB_GIT_UPDATE = [Yy] ]]; then
				cd "${DIR_GRUB}"
				git pull &> /dev/null
				retval="${?}"
				cd "${CWD}"
				if [ "${retval}" -ne 0 ]; then
					echo "	git pull failed!!!"
					exit 1
				fi
			fi
		else
			echo "	No GRUB repo."
			read -r -p "	Clone GRUB repository? (y/n): " INSTALL_GRUB_GIT_CLONE
			if [[ ${INSTALL_GRUB_GIT_CLONE} = [Yy] ]]; then
				git clone "${GIT_REPO}" "${DIR_GRUB}" &> /dev/null
				retval="${?}"
				if [ "${retval}" -ne 0 ]; then
					echo "	git clone failed!!!"
					exit 1
				fi
			fi
		fi
		if [ -d "${DIR_GRUB}" ]; then
			cd "${DIR_GRUB}"

			read -r -p "	(Re)Build GRUB source? (y/n): " INSTALL_GRUB_BUILD
			if [[ ${INSTALL_GRUB_BUILD} = [Yy] ]]; then
				echo -n "	GRUB - Running bootstrap: "
				./bootstrap &> /dev/null
				okay_failedexit $?
				echo -n "	GRUB - Running autogen: "
				./autogen.sh &> /dev/null
				okay_failedexit $?
				echo -n "	GRUB - Running configure: "
				GRUB_CONFIG_OUT=`./configure|awk 'BEGIN { PRNT=0; } $1 == "*******************************************************" { PRNT=1; } { if (PRNT) print $0; } '`
				okay_failedexit $?
				while IFS= read -r GRUB_CONFIG_LINE; do
					echo "		${GRUB_CONFIG_LINE}"
				done <<< "${GRUB_CONFIG_OUT}"
				echo -n "	GRUB - Running make: "
				make -j 2 &> /dev/null
				okay_failedexit $?
			fi
			if [ -d "${DIR_EFI_GRUB}" ]; then			# Remove the existing grub directory
				rm -rf "${DIR_EFI_GRUB}" &> /dev/null
			fi
			mkdir -p "${DIR_EFI_GRUBMODS}" &> /dev/null
			BOOT_EFI_GRUB="${DIR_EFI_GRUB}/BOOTAA64.EFI"
			echo -n "	GRUB - Installing boot loader: "
			./grub-mkimage --directory grub-core --prefix "${EFI_GRUB}" --output "${BOOT_EFI_GRUB}" --format arm64-efi \
				part_gpt part_msdos ntfs ntfscomp hfsplus fat ext2 normal chain boot configfile linux minicmd \
				gfxterm all_video efi_gop video_fb font video loadenv disk test gzio bufio gettext terminal \
				crypto extcmd boot fshelp search iso9660 &> /dev/null
			okay_failedexit $?
			echo -n "	GRUB - Copying modules: "
			cp grub-core/*.{mod,lst} "${DIR_EFI_GRUBMODS}" &> /dev/null
			okay_failedexit $?
			echo -n "	GRUB - Set as default bootloader: "
			cp "${BOOT_EFI_GRUB}" "${DIR_EFI_BOOT}"
			okay_failedexit $?
			cd "${CWD}"
		fi
		echo
	fi

	echo -n "	UnMounting EFI System partition: "
	sudo umount "${DIR_USBKEY}" &> /dev/null
	okay_failedexit $?
fi
