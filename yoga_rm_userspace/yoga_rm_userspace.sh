#!/bin/bash

NAME_QRTRNS="qrtr-ns"
NAME_PDMAPPER="pd-mapper"
NAME_RMTFS="rmtfs"
NAME_TQFTPSERV="tqftpserv"

PID_QRTRNS=`ps -A|grep "${NAME_QRTRNS}"|awk '{ print $1 }'`
if [ -z ${PID_QRTRNS} ]; then
	echo "Failed to find qrtr-ns pid."
	exit
fi
PID_PDMAPPER=`ps -A|grep "${NAME_PDMAPPER}"|awk '{ print $1 }'`
if [ -z ${PID_PDMAPPER} ]; then
	echo "Failed to find pd-mapper pid."
	exit
fi
PID_RMTFS=`ps -A|grep "${NAME_RMTFS}"|awk '{ print $1 }'`
if [ -z ${PID_RMTFS} ]; then
	echo "Failed to find rmtfs pid."
	exit
fi
PID_TQFTPSERV=`ps -A|grep "${NAME_TQFTPSERV}"|awk '{ print $1 }'`
if [ -z ${PID_TQFTPSERV} ]; then
	echo "Failed to find tqftpserv pid."
	exit
fi

echo "Found PIDs:"
echo "qrtr-ns: ${PID_QRTRNS}"
echo "pd_mapper: ${PID_PDMAPPER}"
echo "rmtfs: ${PID_RMTFS}"
echo "tqftpserv: ${PID_TQFTPSERV}"

echo "Checking for systemd units:"
STS_QRTRNS=`systemctl status "${NAME_QRTRNS}" &> /dev/null; echo $?`
if [ "${STS_QRTRNS}" -eq 0 ]; then
	echo -n "Found ${NAME_QRTRNS}.service: "
	PATH_QRTRNS=`awk -F "${NAME_QRTRNS}" '{ print $1 }' /proc/${PID_QRTRNS}/cmdline`
	echo "${PATH_QRTRNS}${NAME_QRTRNS}"
else
	echo "Error getting status of ${NAME_QRTRNS}.service: ${STS_QRTRNS}"
	exit
fi
STS_PDMAPPER=`systemctl status "${NAME_PDMAPPER}" &> /dev/null; echo $?`
if [ "${STS_PDMAPPER}" -eq 0 ]; then
	echo -n "Found ${NAME_PDMAPPER}.service: "
	PATH_PDMAPPER=`awk -F "${NAME_PDMAPPER}" '{ print $1 }' /proc/${PID_PDMAPPER}/cmdline`
	echo "${PATH_PDMAPPER}${NAME_PDMAPPER}"
else
	echo "Error getting status of ${NAME_PDMAPPER}.service: ${STS_PDMAPPER}"
	exit
fi
STS_RMTFS=`systemctl status "${NAME_RMTFS}" &> /dev/null; echo $?`
if [ "${STS_RMTFS}" -eq 0 ]; then
	echo -n "Found ${NAME_RMTFS}.service: "
	PATH_RMTFS=`awk -F "${NAME_RMTFS}" '{ print $1 }' /proc/${PID_RMTFS}/cmdline`
	echo "${PATH_RMTFS}${NAME_RMTFS}"
else
	echo "Error getting status of ${NAME_RMTFS}.service: ${STS_RMTFS}"
	exit
fi
STS_TQFTPSERV=`systemctl status "${NAME_TQFTPSERV}" &> /dev/null; echo $?`
if [ "${STS_TQFTPSERV}" -eq 0 ]; then
	echo -n "Found ${NAME_TQFTPSERV}.service: "
	PATH_TQFTPSERV=`awk -F "${NAME_TQFTPSERV}" '{ print $1 }' /proc/${PID_TQFTPSERV}/cmdline`
	echo "${PATH_TQFTPSERV}${NAME_TQFTPSERV}"
else
	echo "Error getting status of ${NAME_TQFTPSERV}.service: ${STS_TQFTPSERV}"
	exit
fi
