#!/bin/bash

. ./shared_functions

print_usage() {
	cat << EOF
Usage: create_initrd_pkg.sh [OPTIONS]
Utility to build a base initrd.img to be packaged for distribution.

!!!NOTE: This is a maintenance package, and is not normally needed!!!

Options:
	-y			- Actually build package.
EOF
	exit 1
}

BUILD_INITRD_PACKAGE=0
# Pass arguments
while getopts ":y" opt; do
	case $opt in
		y)
			BUILD_INITRD_PACKAGE=1
			;;
		\?)
			print_usage
			;;
	esac
done

if [ ${BUILD_INITRD_PACKAGE} -eq 0 ]; then
	echo "!!! THIS IS A MAINTENANCE UTIL, YOU DON'T NEED TO RUN THIS. !!!"
	exit
fi

# Run sudo to make sure we're authenticated (and not mess with displayed text)
sudo ls &> /dev/null

echo -e "${TXT_UNDERLINE}Creating base initrd.img package...${TXT_NORMAL}"
initrd_build_base

# Make sure permissions are correct.
sudo chown -R root:root "${DIR_EXTRAS}"

if [ ! -d "${DIR_PKGS}" ]; then
	echo -n "	Creating packages directory: "
	mkdir -p "${DIR_PKGS}" &> /dev/null
	okay_failedexit $?
fi

TMP_INITRD_DIR=`basename ${DIR_INITRD}`
echo -n "	Creating initrd package archive: "
sudo tar -czf ${DIR_PKGS}/initrd.img.${HOST_ARCH}.tgz ${TMP_INITRD_DIR}/* &> /dev/null
okay_failedexit $?

echo -n "	Creating archive signature: "
gpg --armor --detach-sig --local-user "celliwig@nym.hush.com" --output ${DIR_PKGS}/initrd.img.${HOST_ARCH}.tgz.asc ${DIR_PKGS}/initrd.img.${HOST_ARCH}.tgz &> /dev/null
okay_failedexit $?
