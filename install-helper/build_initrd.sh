#!/bin/bash

. ./shared_functions

print_usage() {
	cat << EOF
Usage: build_initrd.sh [OPTIONS]
Utility to build an install-helper initrd.img.

Kernel package (Debian/RedHat supported) is optional.
If the kernel package is specified it is included in the initrd image.

Options:
	-k <kernel package>	- Kernel package to include.
	-m <module name>	- Load named module on startup.

'-m' can be specified multiple times.
EOF
	exit 1
}

KERNEL_PACKAGE=""
MODULE_LIST=()
# Pass arguments
while getopts ":k:m:" opt; do
	case $opt in
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

echo -e "${TXT_UNDERLINE}Creating initrd.img...${TXT_NORMAL}"

# Run sudo to make sure we're authenticated (and not mess with displayed text)
sudo ls &> /dev/null

# Make a tmpfs on /opt to copy our local utils into
echo -n "	Making temporary /opt: "
sudo mount -t tmpfs none /opt &> /dev/null
okay_failedexit $?
# TmpFS will mount as 777, so reset ACLs
sudo chmod 755 /opt

# Make cmdline-patch
echo -n "	Making cmdline-patch: "
cd "${DIR_CMDLINE}"
make cmdline-patch &> /dev/null
okay_failedexit $?
cd "${CWD}"
sudo cp "${DIR_CMDLINE}/cmdline-patch" "/opt" &> /dev/null

# Make grub-cfg
echo -n "	Making grub-cfg: "
cd "${DIR_GRUBCFG}"
make grub-cfg &> /dev/null
okay_failedexit $?
cd "${CWD}"
sudo cp "${DIR_GRUBCFG}/grub-cfg" "/opt" &> /dev/null

echo -n "	Generating makejail configuration: "
MAKEJAIL_CFG="${DIR_MAKEJAIL}/install-helper-initrd.py"
"${DIR_MAKEJAIL}"/makejail-config "${DIR_INITRD}"
okay_failedexit $?

MAKEJAIL_CFG_CHKFILES=`"${DIR_MAKEJAIL}"/makejail-chkfiles "${MAKEJAIL_CFG}"`
if [ ${?} -ne 0 ]; then
	echo "Please install the following files:"
	echo "${MAKEJAIL_CFG_CHKFILES}"
	exit
fi

if [ ! -d "${DIR_INITRD}" ]; then
	echo -n "	Creating initrd image directory: "
	mkdir "${DIR_INITRD}" &> /dev/null
	okay_failedexit $?
fi

echo -n "	Running makejail: "
sudo makejail "${MAKEJAIL_CFG}" &> /dev/null
okay_failedexit $?

# Unmount /opt as we're finished with it
sudo umount /opt

INITRD_SUFFIX=""
if [[ "${KERNEL_PACKAGE}" != "" ]]; then
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

	# Get the kernel version to apply to the initrd filename
	INITRD_SUFFIX=`ls "${KERNEL_PACKAGE_TEMPDIR}"/boot/vmlinuz-*|awk -F 'vmlinuz' '{ print $2 }'`

	echo -n "	Copying kernel package contents from ${KERNEL_PACKAGE_TEMPDIR} to initrd image: "
	copy_source_2_target "${KERNEL_PACKAGE_TEMPDIR}" "${DIR_INITRD}"
	okay_failedexit $?
	sudo rm -rf "${KERNEL_PACKAGE_TEMPDIR}"
fi

# Make sure permissions are correct.
sudo chown -R root:root "${DIR_EXTRAS}"
echo -n "	Copying scripts: "
sudo cp -a "${DIR_EXTRAS}"/* "${DIR_INITRD}"
okay_failedexit $?

if [ "${#MODULE_LIST[@]}" -ne 0 ]; then
	echo "	Modules to load on boot:"
	for tmp_module in "${MODULE_LIST[@]}"; do
		echo "		${tmp_module}"
		echo "${tmp_module}" | sudo tee -a "${DIR_INITRD}"/conf/modules &> /dev/null
	done
fi

if [ ! -d "${DIR_INITRD_GPGKEYS}" ]; then
	echo -n "	Creating GPG keys directory: "
	sudo mkdir -p "${DIR_INITRD_GPGKEYS}" &> /dev/null
	okay_failedexit $?
fi
cd "${DIR_INITRD_GPGKEYS}"
echo -n "	Fetching Fedora GPG key: "
sudo wget "${FEDORA_GPG_KEYS}" &> /dev/null
okay_failedexit $?
cd "${CWD}"

if [ ! -d "${DIR_USBKEY_BOOT}" ]; then
	echo -n "	Creating output directory: "
	mkdir -p "${DIR_USBKEY_BOOT}" &> /dev/null
	okay_failedexit $?
fi

echo -n "	Generating cpio image: "
INITRD_PATH="${DIR_USBKEY_BOOT}/initrd${INITRD_SUFFIX}"
cd "${DIR_INITRD}"
sudo find . | sudo cpio -H newc -o 2> /dev/null 1> "${INITRD_PATH}"
okay_failedexit $?
cd "${CWD}"
echo -n "	Compressing initrd: "
gzip -f "${INITRD_PATH}" &> /dev/null
okay_failedexit $?
