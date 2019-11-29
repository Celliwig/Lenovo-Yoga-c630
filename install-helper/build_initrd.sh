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

echo -e "${TXT_UNDERLINE}Creating initrd.img...${TXT_NORMAL}"

echo -n "	Generating makejail configuration: "
MAKEJAIL_CFG="${DIR_MAKEJAIL}/install-helper-initrd.py"
MAKEJAIL_CFG_PRE="${DIR_MAKEJAIL}/install-helper-initrd.py.pre"
sed "s|###PROJECT_DIR###|${DIR_INITRD}|g" "${MAKEJAIL_CFG_PRE}" > "${MAKEJAIL_CFG}"
okay_failedexit $?
