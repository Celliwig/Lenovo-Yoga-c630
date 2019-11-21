# Lenovo Yoga firmware extraction tool (beta)

This tool creates the required firmware directories that linux needs for wifi/audio/etc, primarily from the drivers installed on the Windows partition.

It is recommended that you login to Windows first, and do an update to make sure the latest firmware is available before running this utility. You should run this from a clean directory as it generates a number of files/directories. Also it will not run as root so as to avoid accidentally doing something detrimental, however this means sudo is used so you will be prompted for your password (either to mount the Windows partition, or to copy files into /lib/firmware).
