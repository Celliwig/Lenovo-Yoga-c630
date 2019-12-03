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
	-g			- Build grub.
	-i			- Build initrd.
	-k <kernel package>	- Kernel package to include.
	-m <module name>	- Load named module on startup.
	-p			- Erase target device and build required partitions.

'-m' can be specified multiple times.
EOF
	exit 1
}

BLOCK_DEVICE=""
INITRD_BUILD=false
INSTALL_GRUB=false
KERNEL_PACKAGE=""
MAKE_PARTITIONS=false
MODULE_LIST=()
# Pass arguments
while getopts ":d:gik:m:p" opt; do
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
		i)
			INITRD_BUILD=true
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
		p)
			MAKE_PARTITIONS=true
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

if "${MAKE_PARTITIONS}"; then
	PARTITION_EFI_SIZE="1G"

	echo -e "${TXT_UNDERLINE}Partition and format: ${BLOCK_DEVICE}${TXT_NORMAL}"
	read -r -p "	Partition device (y/N): " BLOCK_DEVICE_PARTITION
	if [[ $BLOCK_DEVICE_PARTITION = [Yy] ]]; then
		echo "	Creating an EFI compatible USB key."
		echo -n "	Wiping partition table: "
		sudo sgdisk --zap-all "${BLOCK_DEVICE}" &> /dev/null
		okay_failedexit $?
		echo -n "	Create EFI System partition (${PARTITION_EFI_SIZE}): "
		sudo sgdisk --new=1:0:+${PARTITION_EFI_SIZE} --typecode=1:ef00 "${BLOCK_DEVICE}" &> /dev/null
		okay_failedexit $?
		echo -n "	Creating linux filesystem partition (rest): "
		sudo sgdisk --new=2:+${PARTITION_EFI_SIZE}:0 --typecode=2:8300 "${BLOCK_DEVICE}" &> /dev/null
		okay_failedexit $?
		echo -n "	Formating EFI System partition (VFAT): "
		sudo mkfs.vfat -F32 -n IHEFI "${BLOCK_DEVICE}1" &> /dev/null
		okay_failedexit $?
		echo -n "	Formating linux filesystem partition: "
		sudo mkfs.ext3 -F -L IHFILES "${BLOCK_DEVICE}2" &> /dev/null
		okay_failedexit $?
	fi

	# Wait a little time so that /dev/disk is updated
	sleep 5
fi

if [ -e /dev/disk/by-label/IHEFI ] && [ -e /dev/disk/by-label/IHFILES ]; then
	MOUNTAS_UID=`id -u`
	MOUNTAS_GID=`id -g`

	echo -e "${TXT_UNDERLINE}Copying system files${TXT_NORMAL}"
	if [ ! -d "${DIR_USBKEY}" ]; then
		echo -n "       Creating 'usb_key/' directory: "
		mkdir -p "${DIR_USBKEY}" &> /dev/null
		okay_failedexit $?
	fi
	if [ ! -d "${DIR_USBKEYFILES}" ]; then
		echo -n "       Creating 'usb_key-files/' directory: "
		mkdir -p "${DIR_USBKEYFILES}" &> /dev/null
		okay_failedexit $?
	fi
	echo -n "	Mounting EFI System partition: "
	sudo mount -t vfat /dev/disk/by-label/IHEFI "${DIR_USBKEY}" -o uid=1000,gid=1000,umask=022 &> /dev/null
	okay_failedexit $?
	echo -n "	Mounting install-helper file storage: "
	sudo mount -t ext3 /dev/disk/by-label/IHFILES "${DIR_USBKEYFILES}" &> /dev/null
	okay_failedexit $?
	sudo chown ${MOUNTAS_UID}:${MOUNTAS_GID} "${DIR_USBKEYFILES}" &> /dev/null
	if [ ! -d "${DIR_EFI_BOOT}" ]; then
		echo -n "	Creating EFI boot directory: "
		mkdir -p "${DIR_EFI_BOOT}" &> /dev/null
		okay_failedexit $?
	fi

	if [[ "${KERNEL_PACKAGE}" != "" ]]; then
		echo -e "${TXT_UNDERLINE}Install kernel${TXT_NORMAL}"
		KERNEL_PACKAGE_TYPE=`identify_package_type "${KERNEL_PACKAGE}"`
		echo "	Kernel package type identified as: ${KERNEL_PACKAGE_TYPE}"

		KERNEL_PACKAGE_NAME=`basename "${KERNEL_PACKAGE}"`
		case "${KERNEL_PACKAGE_TYPE}" in
			"debian")
				echo -n "	Extracting ${KERNEL_PACKAGE_NAME}: "
				KERNEL_PACKAGE_TEMPDIR=`deb_package_extract "${KERNEL_PACKAGE}"`
				okay_failedexit $?
				;;
			"redhat")
				echo -n "	Extracting ${KERNEL_PACKAGE_NAME}: "
				KERNEL_PACKAGE_TEMPDIR=`rpm_package_extract "${KERNEL_PACKAGE}"`
				okay_failedexit $?
				;;
			*)
				exit -1
				;;
		esac

		echo -n "	Copying kernel package contents from ${KERNEL_PACKAGE_TEMPDIR} to USB key: "
		cp -a "${KERNEL_PACKAGE_TEMPDIR}"/* "${DIR_USBKEY}"
		okay_failedexit $?
		sudo rm -rf "${KERNEL_PACKAGE_TEMPDIR}"
	fi

	if "${INITRD_BUILD}"; then
		MODULE_LIST_TXT=""
		if [ "${#MODULE_LIST[@]}" -ne 0 ]; then
			for tmp_module in "${MODULE_LIST[@]}"; do
				MODULE_LIST_TXT="${MODULE_LIST_TXT} -m ${tmp_module}"
			done
		fi
		./build_initrd.sh -k "${KERNEL_PACKAGE}" ${MODULE_LIST_TXT}
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
			echo -n "	GRUB - Installing boot loader: "
			./grub-mkimage --directory grub-core --prefix "${EFI_GRUB}" --output "${FILE_EFI_GRUBBOOT}" --format arm64-efi \
				part_gpt part_msdos ntfs ntfscomp hfsplus fat ext2 normal chain boot configfile linux minicmd \
				gfxterm all_video efi_gop video_fb font video loadenv disk test gzio bufio gettext terminal \
				crypto extcmd boot fshelp search iso9660 &> /dev/null
			okay_failedexit $?
			echo -n "	GRUB - Copying modules: "
			cp grub-core/*.{mod,lst} "${DIR_EFI_GRUBMODS}" &> /dev/null
			okay_failedexit $?
			echo -n "	GRUB - Set as default bootloader: "
			cp "${FILE_EFI_GRUBBOOT}" "${DIR_EFI_BOOT}"
			okay_failedexit $?
			cd "${CWD}"
		fi
	fi

	rm "${FILE_EFI_GRUBCFG}" &> /dev/null
	echo "	Creating grub.cfg: "
	touch "${FILE_EFI_GRUBCFG}"
	echo "set menu_color_normal=white/black" >> "${FILE_EFI_GRUBCFG}"
	echo "set menu_color_highlight=black/light-gray" >> "${FILE_EFI_GRUBCFG}"
	echo "if background_color 44,0,30,0; then" >> "${FILE_EFI_GRUBCFG}"
	echo "  clear" >> "${FILE_EFI_GRUBCFG}"
	echo "fi" >> "${FILE_EFI_GRUBCFG}"
	echo "" >> "${FILE_EFI_GRUBCFG}"
	echo "insmod gzio" >> "${FILE_EFI_GRUBCFG}"
	echo "set timeout=30" >> "${FILE_EFI_GRUBCFG}"
	for tmp_kernel_version in `find "${DIR_USBKEY_BOOT}" -name vmlinuz-\* |sed "s|${DIR_USBKEY_BOOT}/||g"`; do
		echo "		Adding entry: ${tmp_kernel_version}"

		tmp_kernel_args='efi=novamap pd_ignore_unused clk_ignore_unused'
		tmp_initrd_version=`echo "${tmp_kernel_version}" |sed 's|vmlinuz||'`
		tmp_devicetree='/usr/lib/linux-image-5.4.0-rc7-g43234ba81/qcom/sdm850-lenovo-yoga-c630.dtb'

		echo "menuentry \"${tmp_kernel_version}\" {" >> "${FILE_EFI_GRUBCFG}"
		echo "	set gfxpayload=keep" >> "${FILE_EFI_GRUBCFG}"
		echo "	linux /boot/${tmp_kernel_version} ${tmp_kernel_args}" >> "${FILE_EFI_GRUBCFG}"
		echo "	initrd /boot/initrd${tmp_initrd_version}.gz" >> "${FILE_EFI_GRUBCFG}"
		echo "	devicetree ${tmp_devicetree}" >> "${FILE_EFI_GRUBCFG}"
		echo "}" >> "${FILE_EFI_GRUBCFG}"
	done

	echo -n "	UnMounting EFI System partition: "
	sudo umount "${DIR_USBKEY}" &> /dev/null
	okay_failedexit $?
	echo -n "	UnMounting install-helper file storage: "
	sudo umount "${DIR_USBKEYFILES}" &> /dev/null
	okay_failedexit $?
fi
