#!/bin/bash

. ./shared_functions

print_usage() {
	cat << EOF
Usage: create_grub_pkg.sh [OPTIONS]
Utility to build GRUB to be packaged for distribution.

!!!NOTE: This is a maintenance package, and is not normally needed!!!

Options:
	-y			- Actually build package.
EOF
	exit 1
}

local BUILD_GRUB_PACKAGE=0
# Pass arguments
while getopts ":y" opt; do
	case $opt in
		y)
			BUILD_GRUB_PACKAGE=1
			;;
		\?)
			print_usage
			;;
	esac
done

if [ ${BUILD_GRUB_PACKAGE} -eq 0 ]; then
	echo "!!! THIS IS A MAINTENANCE UTIL, YOU DON'T NEED TO RUN THIS. !!!"
	exit
fi

# Run sudo to make sure we're authenticated (and not mess with displayed text)
sudo ls &> /dev/null

echo -e "${TXT_UNDERLINE}Creating GRUB package...${TXT_NORMAL}"
grub_install_from_src "${DIR_GRUBSRC}" "${DIR_GRUBPKG}"

if [ ! -d "${DIR_PKGS}" ]; then
	echo -n "	Creating packages directory: "
	mkdir -p "${DIR_PKGS}" &> /dev/null
	okay_failedexit $?
fi

TMP_GRUB_DIR=`basename ${DIR_GRUBPKG}`
echo -n "	Creating GRUB package archive: "
sudo tar -czf ${DIR_PKGS}/grub.${HOST_ARCH}.tgz ${TMP_GRUB_DIR}/* &> /dev/null
okay_failedexit $?

echo -n "	Creating archive signature: "
gpg --armor --detach-sig --local-user "celliwig@nym.hush.com" --output ${DIR_PKGS}/grub.${HOST_ARCH}.tgz.asc ${DIR_PKGS}/grub.${HOST_ARCH}.tgz &> /dev/null
okay_failedexit $?
