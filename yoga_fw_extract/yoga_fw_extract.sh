#!/bin/bash

# This script tries to extract the firmware files needed to enable the DSPs/audio/wifi on the Lenovo Yoga
# from the systems windows partion

# Don't run as root
if [ ${UID} -eq 0 ]; then
	echo "Error: This script won't run as root."
	exit
fi

WIN_PART=""									# Windows partition path
# Try to automatically identify windows partition
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

PWD=`pwd`
# Create directory to copy windows files into
PATH_WIN_DRV="${PWD}/Windows Drivers"
if [ -e "${PATH_WIN_DRV}" ]; then
	echo "Deleting existing copy of Windows drivers..."
	rm -rf "${PATH_WIN_DRV}"
fi
echo -n "Creating directory for Windows drivers: "
mkdir "${PATH_WIN_DRV}" &> /dev/null
if [ $? -eq 0 ]; then
	echo "Done"

	COPY_ERR=0
	# Copying Window's driver file
	echo -n "Copying Window's driver files: "
	# Copy DSP files
	for DSP_FILE in `find /mnt/Windows/System32/DriverStore/FileRepository/ -name qcadsp850.mbn`; do
		DSP_PATH=`dirname "${DSP_FILE}"`
		cp -r "${DSP_PATH}" "${PATH_WIN_DRV}" &> /dev/null
		if [ $? -ne 0 ]; then
			COPY_ERR=$((COPY_ERR+1))
		fi
	done
	# Copy board files
	for BRD_FILE in `find /mnt/Windows/System32/DriverStore/FileRepository/ -name bdwlan.bin`; do
		BRD_PATH=`dirname "${BRD_FILE}"`
		cp -r "${BRD_PATH}" "${PATH_WIN_DRV}" &> /dev/null
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
