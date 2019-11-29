#!/bin/bash

. ./shared_functions

KERNEL_PACKAGE="${1}"

echo -e "${TXT_UNDERLINE}Creating initrd.img...${TXT_NORMAL}"

# Run sudo to make sure we're authenticated (and not mess with displayed text)
sudo ls &> /dev/null

echo -n "	Generating makejail configuration: "
MAKEJAIL_CFG="${DIR_MAKEJAIL}/install-helper-initrd.py"
MAKEJAIL_CFG_PRE="${DIR_MAKEJAIL}/install-helper-initrd.py.pre"
sed "s|###PROJECT_DIR###|${DIR_INITRD}|g" "${MAKEJAIL_CFG_PRE}" > "${MAKEJAIL_CFG}"
okay_failedexit $?

if [ ! -d "${DIR_INITRD}" ]; then
	echo -n "	Creating initrd image directory: "
	mkdir "${DIR_INITRD}" &> /dev/null
	okay_failedexit $?
fi

echo -n "	Running makejail: "
sudo makejail "${MAKEJAIL_CFG}" &> /dev/null
okay_failedexit $?

if [[ "${KERNEL_PACKAGE}" != "" ]]; then
	KERNEL_PACKAGE_TYPE=`identify_package_type "${KERNEL_PACKAGE}"`
	echo "	Kernel package type identified as: ${KERNEL_PACKAGE_TYPE}"

	KERNEL_PACKAGE_NAME=`basename "${KERNEL_PACKAGE}"`
	case "${KERNEL_PACKAGE_TYPE}" in
		"debian")
			echo -n "	Extracting ${KERNEL_PACKAGE_NAME} to initrd dir: "
			deb_package_extract "${KERNEL_PACKAGE}" "${DIR_INITRD}"
			okay_failedexit $?
			;;
		"redhat")
			echo -n "	Extracting ${KERNEL_PACKAGE_NAME} to initrd dir: "
			rpm_package_extract "${KERNEL_PACKAGE}" "${DIR_INITRD}"
			okay_failedexit $?
			;;
		*)
			exit -1
			;;
	esac
fi

if [ ! -d "${DIR_USBKEY_BOOT}" ]; then
	echo -n "	Creating output directory: "
	mkdir -p "${DIR_USBKEY_BOOT}" &> /dev/null
	okay_failedexit $?
fi

echo -n "	Copying scripts: "
sudo cp -a "${DIR_SCRIPTS}"/* "${DIR_INITRD}"
okay_failedexit $?

echo -n "	Generating cpio image: "
INITRD_PATH="${DIR_USBKEY_BOOT}/initrd"
cd "${DIR_INITRD}"
sudo find . | sudo cpio -H newc -o 2> /dev/null 1> "${INITRD_PATH}"
okay_failedexit $?
cd "${CWD}"
echo -n "	Compressing initrd: "
gzip -f "${INITRD_PATH}" &> /dev/null
okay_failedexit $?
