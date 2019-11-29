#!/bin/bash

. ./shared_functions

CWD=$PWD
DIR_INITRD="${CWD}/initrd"
DIR_MAKEJAIL="${CWD}/makejail"
DIR_FILES="${CWD}/files"
KERNEL_PACKAGE=$1

echo -e "${TXT_UNDERLINE}Creating initrd.img...${TXT_NORMAL}"

# Run sudo to make sure we're authenticated (and not mess with displayed text)
sudo ls &> /dev/null

echo -n "	Generating makejail configuration: "
MAKEJAIL_CFG="${DIR_MAKEJAIL}/install-helper-initrd.py"
MAKEJAIL_CFG_PRE="${DIR_MAKEJAIL}/install-helper-initrd.py.pre"
sed "s|###PROJECT_DIR###|${DIR_INITRD}|g" "${MAKEJAIL_CFG_PRE}" > "${MAKEJAIL_CFG}"
okay_failedexit $?

echo -n "	Running makejail: "
sudo makejail "${MAKEJAIL_CFG}" &> /dev/null
okay_failedexit $?

if [ ! -d "${DIR_FILES}" ]; then
	echo -n "	Creating output directory: "
	mkdir "${DIR_FILES}" &> /dev/null
	okay_failedexit $?
fi

if [[ "${KERNEL_PACKAGE}" != "" ]]; then
	KERNEL_PACKAGE_TYPE=`identify_package_type "${KERNEL_PACKAGE}"`
	echo "	Kernel package type identified as: ${KERNEL_PACKAGE_TYPE}"
fi

echo -n "	Generating cpio image: "
INITRD_PATH="${DIR_FILES}/initrd"
cd "${DIR_INITRD}"
sudo find . | sudo cpio -H newc -o 2> /dev/null 1> "${INITRD_PATH}"
okay_failedexit $?
cd "${CWD}"
echo -n "	Compressing initrd: "
gzip -f "${INITRD_PATH}" &> /dev/null
okay_failedexit $?
