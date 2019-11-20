#!/bin/bash

# This script tries to extract the firmware files needed to enable the DSPs/audio/wifi on the Lenovo Yoga
# from the systems windows partion
###################################################################################################################################################

URL_FW_FIRMWARE5BIN="https://github.com/kvalo/ath10k-firmware/raw/master/WCN3990/hw1.0/HL2.0/WLAN.HL.2.0-01387-QCAHLSWMTPLZ-1/firmware-5.bin"

TXT_UNDERLINE="\033[1m\033[4m"
TXT_NORMAL="\033[0m"

# Don't run as root to avoid doing anything monumentally stupid
if [ ${UID} -eq 0 ]; then
	echo -e "${TXT_UNDERLINE}Error: This script won't run as root.${TXT_NORMAL}"
	exit
fi

WIN_PART=""									# Windows partition path
# Try to automatically identify windows partition
echo -e "${TXT_UNDERLINE}Getting Windows drivers...${TXT_NORMAL}"
echo "Searching for Windows partition..."
WIN_PART_LABEL="Windows4"
WIN_PART_TMP=`blkid -L "${WIN_PART_LABEL}"`
if [ $? -eq 0 ]; then
	echo "	Found Windows partition: ${WIN_PART_TMP}"
	WIN_PART=${WIN_PART_TMP}
else
	echo "	Partition not found."
	echo -n "Please enter the path of the Windows partition: "
	read WIN_PART
fi

# Check if partition exists
if [ ! -e ${WIN_PART} ]; then
	echo "Error: Windows partition path does not exist: ${WIN_PART}"
	exit
fi

WIN_MNT=""									# Windows mount path
WIN_MNT_UNMNT=""								# Whether to umount windows mount
# Check if it's already mounted
echo -n "Checking if partition already mounted: "
while read pmount
do
	if [[ "${pmount}" =~ "${WIN_PART} " ]]; then
		WIN_MNT=`echo "${pmount}"|awk '{print $2}'`
	fi
done < /proc/mounts
if [[ ${WIN_MNT} == "" ]]; then
	echo "No"
else
	echo "${WIN_MNT}"
fi

# Windows partition not mounted, so mount
if [[ $WIN_MNT == "" ]]; then
	# Check if /mnt already in use
	echo -n "Checking if /mnt in use: "
	while read pmount
	do
		if [[ "${pmount}" =~ "/mnt " ]]; then
			echo "Yes"
			echo "	Either unmount /mnt, or manually mount Windows filesystem readonly and rerun."
			exit
		fi
	done < /proc/mounts
	echo "No"

	# Mount windows partition
	echo "Mounting Windows partition: ${WIN_PART}"
	sudo mount -o ro -t ntfs ${WIN_PART} /mnt
	if [ $? -eq 0 ]; then
		WIN_MNT_UNMNT='/mnt'						# Flag that we need to umount /mnt
	else
		echo "	Error: Mount failed."
		exit
	fi
fi

# Check mounted readonly
WIN_MNT_STS_RO=""
echo -n "Checking Windows FS is read only: "
while read pmount
do
	if [[ "${pmount}" =~ "${WIN_PART} " ]]; then
		WIN_MNT_STS_RO=`echo "${pmount}"|awk '$4 ~ /^ro,/ {print "true"}; $4 ~ /^rw,/ {print "false"}'`
	fi
done < /proc/mounts
echo "${WIN_MNT_STS_RO}"
if [[ "${WIN_MNT_STS_RO}" != "true" ]]; then
	echo "	Error: Windows filesystem not mounted read-only."
	exit
fi

CWD=`pwd`
COPY_ERR=0
# Create directory to copy windows files into
PATH_WIN_DRV="${CWD}/Windows Drivers"
if [ -e "${PATH_WIN_DRV}" ]; then
	echo "Deleting existing copy of Windows drivers..."
	rm -rf "${PATH_WIN_DRV}"
fi
echo -n "Creating directory for Windows drivers: "
mkdir "${PATH_WIN_DRV}" &> /dev/null
if [ $? -eq 0 ]; then
	echo "Done"

	# Copying Window's driver file
	echo -n "Copying Window's driver files: "
	# Copy DSP files
	for DSP_FILE in `find /mnt/Windows/System32/DriverStore/FileRepository/ -name qcadsp850.mbn`; do
		DSP_PATH=`dirname "${DSP_FILE}"`
		cp -a "${DSP_PATH}" "${PATH_WIN_DRV}" &> /dev/null
		if [ $? -ne 0 ]; then
			COPY_ERR=$((COPY_ERR+1))
		fi
	done
	# Copy board files
	for BRD_FILE in `find /mnt/Windows/System32/DriverStore/FileRepository/ -name bdwlan.bin`; do
		BRD_PATH=`dirname "${BRD_FILE}"`
		cp -a "${BRD_PATH}" "${PATH_WIN_DRV}" &> /dev/null
		if [ $? -ne 0 ]; then
			COPY_ERR=$((COPY_ERR+1))
		fi
	done

	if [ ${COPY_ERR} -eq 0 ]; then
		echo "Done"
	else
		echo "Failed"
	fi
else
	echo "Failed"
fi

# Umount Windows partition if we mounted it
if [[ "${WIN_MNT_UNMNT}" != "" ]]; then
	echo "Unmounting /mnt."
	sudo umount /mnt
fi

# Process copied files
if [ ${COPY_ERR} -eq 0 ]; then
	echo -e "\n${TXT_UNDERLINE}Processing found drivers.${TXT_NORMAL}"
	echo -n "Scanning copied files: "
	# Get path to latest DSP files
	DSP_FILE_CUR=`find Windows\ Drivers/ -type f -name qcadsp850.mbn -exec ls -t {} +|head -n1`
	if [[ "${DSP_FILE_CUR}" == "" ]]; then
		echo "Failed to find any DSP files."
		exit
	else
		DSP_PATH=`dirname "${DSP_FILE_CUR}"`
	fi
	# Get path to latest board files
	BRD_FILE_CUR=`find Windows\ Drivers/ -type f -name bdwlan.bin -exec ls -t {} +|head -n1`
	if [[ "${BRD_FILE_CUR}" == "" ]]; then
		echo "Failed to find any board files."
		exit
	else
		BRD_PATH=`dirname "${BRD_FILE_CUR}"`
	fi
	echo "Done"

	# Create merged board file
	echo -e "\n${TXT_UNDERLINE}Merged board file:${TXT_NORMAL}"
	PATH_BRD_MAKE="${CWD}/creating-board-2.bin"
	PATH_BRD_SRC="${CWD}/creating-board-2.bin/bdf"
	PATH_BRD_MFILE="board-2.bin"
	if [ -e "${PATH_BRD_MAKE}" ]; then
		echo "Deleting existing board file directory..."
		rm -rf "${PATH_BRD_MAKE}"
	fi
	echo -n "Creating directory for merging board files: "
	mkdir -p "${PATH_BRD_SRC}" &> /dev/null
	if [ $? -eq 0 ]; then
		echo "Done"

		echo -n "Copying individual board files: "
		cp -a "${BRD_PATH}"/bdwlan.b* "${PATH_BRD_SRC}" &> /dev/null
		if [ $? -eq 0 ]; then
			echo "Done"
		else
			echo "Failed"
			exit
		fi

		cd "${PATH_BRD_MAKE}"

###################################################################################################################################################
# This section copied from: https://github.com/aarch64-laptops/build/blob/master/misc/lenovo-yoga-c630/wifi/create-board-2.bin/make-board-2.bin.sh
###################################################################################################################################################

		echo "Creating JSON board file...."

		JSON="bdf/board-2.json"
		iter=0
		echo "[" > "${JSON}"
		for file in bdf/bdwlan.*; do
			[[ $file == *.txt ]] && continue

			iter=$((iter+1))
			[ $iter -ne 1 ] && echo "  }," >> "${JSON}"

			echo "  {" >> "${JSON}"
			echo "          \"data\": \"$file\"," >> "${JSON}"
			if [[ $file == */bdwlan.bin ]]; then
#				file_ext="0"
				file_ext="ff"				# This was required for my install, don't know if this applies to everyone
			else
				file_ext="$(printf '%x\n' "$(basename "${file}" | sed -E 's:^.*\.b?([0-9a-f]*)$:0x\1:')")"
			fi
			echo "          \"names\": [\"bus=snoc,qmi-board-id=${file_ext}\"]" >> "${JSON}"
		done

		echo "  }" >> "${JSON}"
		echo "]" >> "${JSON}"

		echo -n "Fetching Qualcomm Atheros tools: "
		git clone https://github.com/qca/qca-swiss-army-knife.git &> /dev/null
		if [ $? -eq 0 ]; then
			echo "Done"
		else
			echo "Failed"
			exit
		fi

		echo -n "Creating merged board file: "
		python2 qca-swiss-army-knife/tools/scripts/ath10k/ath10k-bdencoder -c "${JSON}" -o "${PATH_BRD_MFILE}" &> /dev/null
		if [ $? -eq 0 ]; then
			echo "Done"
		else
			echo "Failed"
			exit
		fi

###################################################################################################################################################
	else
		echo "Failed"
		exit
	fi
	cd "${CWD}"

	# Create ath10k fw directory
	echo -e "\n${TXT_UNDERLINE}Atheros ath10k firmware${TXT_NORMAL}"
	PATH_FW_ATH10K="${CWD}/WCN3990/hw1.0"
	if [ -e "${PATH_FW_ATH10K}" ]; then
		echo "Deleting existing copy of ath10k firmware files..."
		rm -rf "${PATH_FW_ATH10K}"
	fi
	echo -n "Creating directory for ath10k firmware files: "
	mkdir -p "${PATH_FW_ATH10K}" &> /dev/null
	if [ $? -eq 0 ]; then
		echo "Done"

		echo -n "Copying merged board file: "
		cp "${PATH_BRD_MAKE}"/"${PATH_BRD_MFILE}" "${PATH_FW_ATH10K}" &> /dev/null
		if [ $? -eq 0 ]; then
			echo "Done"
		else
			echo "Failed"
			exit
		fi

		echo -n "Fetching firmware-5.bin: "
		wget "${URL_FW_FIRMWARE5BIN}" &> /dev/null
		if [ $? -eq 0 ]; then
			echo "Done"
		else
			echo "Failed"
			exit
		fi

	else
		echo "Failed"
		exit
	fi
	cd "${CWD}"

	# Create linux dsp directory
	echo -e "\n${TXT_UNDERLINE}Qualcomm DSP firmware${TXT_NORMAL}"
	PATH_FW_C630="${CWD}/c630"
	if [ -e "${PATH_FW_C630}" ]; then
		echo "Deleting existing copy of linux DSP files..."
		rm -rf "${PATH_FW_C630}"
	fi
	echo -n "Creating directory for linux DSP files: "
	mkdir "${PATH_FW_C630}" &> /dev/null
	if [ $? -eq 0 ]; then
		echo "Done"

		echo -n "Copying linux DSP files: "
		cp -a "${DSP_PATH}"/*.mbn "${PATH_FW_C630}" &> /dev/null
		if [ $? -eq 0 ]; then
			echo "Done"
		else
			echo "Failed"
			exit
		fi
	else
		echo "Failed"
	fi
fi
