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
	-I <ISO image>		- ISO image to copy to device.
	-i			- Build initrd.
	-k <kernel package>	- Kernel package to include.
	-m <module name>	- Load named module on startup.
	-p			- Erase target device and build required partitions.

'-I' - multiple ISO images can be specified.
'-m' - multiple module names can be specified.
EOF
	exit 1
}

BLOCK_DEVICE=""
INITRD_BUILD=false
INSTALL_GRUB=false
ISO_IMAGE_LIST=()
KERNEL_PACKAGE=""
MAKE_PARTITIONS=false
MODULE_LIST=()
# Pass arguments
while getopts ":d:gI:ik:m:p" opt; do
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
		I)
			ISO_IMAGE_LIST+=("${OPTARG}")
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
	echo -e "${TXT_UNDERLINE}Partition and format: ${BLOCK_DEVICE}${TXT_NORMAL}"
	read -r -p "	Partition device (y/N): " BLOCK_DEVICE_PARTITION
	if [[ $BLOCK_DEVICE_PARTITION = [Yy] ]]; then
		dev_size_bytes=`sudo blockdev --getsize64 ${BLOCK_DEVICE}`
		dev_size_gig=$((dev_size_bytes/1000000000))
		echo "	Detected: ${BLOCK_DEVICE} (${dev_size_gig} GB)"

		if [ ${dev_size_gig} -eq 0 ]; then
			echo "	!!!NOT ENOUGH SPACE ON THIS DEVICE!!!"
			exit 1
		else
			# Calculate some basic layouts
			# After about 4G, the unused space can be used to copy ISO images in to
			if [ ${dev_size_gig} -le 4 ]; then
				PARTITION_EFI_SIZE=1
				PARTITION_ALT_SIZE=$((${dev_size_gig}-1))
			elif [ ${dev_size_gig} -le 8 ]; then
				PARTITION_EFI_SIZE=1
				PARTITION_ALT_SIZE=3
			else
				PARTITION_EFI_SIZE=1
				PARTITION_ALT_SIZE=$(((${dev_size_gig}/2)-1))
			fi

			PARTITION_EFI_SIZE_TXT="${PARTITION_EFI_SIZE}G"
			PARTITION_ALT_SIZE_TXT="${PARTITION_ALT_SIZE}G"

			echo "	Creating an EFI compatible USB key."
			echo -n "	Wiping partition table: "
			sudo sgdisk --zap-all "${BLOCK_DEVICE}" &> /dev/null
			okay_failedexit $?
			echo -n "	Create EFI System partition (${PARTITION_EFI_SIZE_TXT}): "
			sudo sgdisk --new=1:0:+${PARTITION_EFI_SIZE_TXT} --typecode=1:ef00 --change-name=1:IHEFI "${BLOCK_DEVICE}" &> /dev/null
			okay_failedexit $?
			echo -n "	Formating EFI System partition (VFAT): "
			sudo mkfs.vfat -F32 -n IHEFI "${BLOCK_DEVICE}1" &> /dev/null
			okay_failedexit $?

			if [ ${PARTITION_ALT_SIZE} -gt 0 ]; then
				echo -n "	Creating linux filesystem partition (${PARTITION_ALT_SIZE_TXT}): "
				sudo sgdisk --new=2:0:+${PARTITION_ALT_SIZE_TXT} --typecode=2:8300 --change-name=2:IHFILES "${BLOCK_DEVICE}" &> /dev/null
				okay_failedexit $?
				echo -n "	Formating linux filesystem: "
				sudo mkfs.ext3 -F -L IHFILES "${BLOCK_DEVICE}2" &> /dev/null
				okay_failedexit $?
			fi
		fi
	fi

	# Wait a little time so that /dev/disk is updated
	sleep 5
fi

if [ -e /dev/disk/by-label/IHEFI ] && [ -e /dev/disk/by-label/IHFILES ]; then
	MOUNTAS_UID=`id -u`
	MOUNTAS_GID=`id -g`

	echo -e "${TXT_UNDERLINE}Copying system files${TXT_NORMAL}"
	if [ ! -d "${DIR_USBKEY}" ]; then
		echo -n "	Creating 'usb_key/' directory: "
		mkdir -p "${DIR_USBKEY}" &> /dev/null
		okay_failedexit $?
	fi
	if [ ! -d "${DIR_USBKEYFILES}" ]; then
		echo -n "	Creating 'usb_key-files/' directory: "
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
	if [ ! -d "${DIR_USBKEYFILES}/images" ]; then
		echo -n "	Creating 'usb_key-files/images' directory: "
		mkdir -p "${DIR_USBKEYFILES}/images" &> /dev/null
		okay_failedexit $?
	fi

	KERNEL_NAME=()
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
		cp -a "${KERNEL_PACKAGE_TEMPDIR}"/* "${DIR_USBKEY}"/ &> /dev/null
		okay_failedexit $?

		# Identify the kernel name(s)
		for tmp_kernel_name in `find "${KERNEL_PACKAGE_TEMPDIR}" -name vmlinuz-\* `; do
			KERNEL_NAME+=( `basename "${tmp_kernel_name}"` )
		done

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
		grub_install_from_src "${DIR_GRUBSRC}" "${DIR_USBKEY}"
		grub_set_default "${DIR_USBKEY}"

		for tmp_kernel_name in ${KERNEL_NAME[@]}; do
			grub_config_write_menuitem "${DIR_USBKEY}" "${tmp_kernel_name}"
		done
		grub_config_write_main "${DIR_USBKEY}"
	fi

	echo -n "	UnMounting EFI System partition: "
	sudo umount "${DIR_USBKEY}" &> /dev/null
	okay_failedexit $?
	echo -n "	UnMounting install-helper file storage: "
	sudo umount "${DIR_USBKEYFILES}" &> /dev/null
	okay_failedexit $?
fi

if [ ${#ISO_IMAGE_LIST[@]} -gt 0 ]; then
	echo -e "${TXT_UNDERLINE}Copying ISO images${TXT_NORMAL}"
	for tmp_iso_image in ${ISO_IMAGE_LIST[@]}; do
		tmp_iso_filename=`basename "${tmp_iso_image}"`
		echo -n "	Copying ${tmp_iso_filename}: "
		if [ -f "${tmp_iso_image}" ]; then
			# Check there's space
			sudo ./extras/install-helper/ih-iso-images -C "${tmp_iso_image}" &> /dev/null
			if [ ${?} -eq 0 ]; then
				sudo ./extras/install-helper/ih-iso-images -v -c "${tmp_iso_image}" &> /dev/null
				if [ ${?} -eq 0 ]; then
					echo "Okay"
				else
					echo "Failed"
				fi
			else
				echo "Not enough space."
			fi
		else
			echo "Does not exist."
		fi
	done
fi
