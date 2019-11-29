#!/bin/bash

###################################################################################################################################################
# Functions
###################################################################################################################################################
function okay_failedexit {
	if [ $1 -eq 0 ]; then
		echo "Okay"
	else
		echo "Failed"
		exit
	fi
}

###################################################################################################################################################

TXT_UNDERLINE="\033[1m\033[4m"
TXT_NORMAL="\033[0m"

CWD=$PWD
DIR_INITRD="${CWD}/initrd"
DIR_MAKEJAIL="${CWD}/makejail"
DIR_FILES="${CWD}/files"

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

echo -n "	Generating cpio image: "
INITRD_PATH="${DIR_FILES}/initrd"
cd "${DIR_INITRD}"
sudo find . | sudo cpio -H newc -o 2> /dev/null 1> "${INITRD_PATH}"
okay_failedexit $?
cd "${CWD}"
echo -n "	Compressing initrd: "
gzip -f "${INITRD_PATH}" &> /dev/null
okay_failedexit $?
