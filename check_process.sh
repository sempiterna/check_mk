#!/bin/bash
#
# A Check_MK local check that checks if a service or process is running,
# and optionally when it was started and how much RAM it is using. If a
# port number is given, it will also check if the process/service is
# connected to the given port.
#
# PROCESS_NAMES[x]: One process/service per variable/line. Services
# should be added as follows:
#
# "processname:friendly name:run as user:type(service or process):port"
#
#    processname: Name of the process or service you want to check.
#
#    friendly name: Name of the process/service that will be shown in
#                   Check_MK
#
#    run as user: Check process info using username (root is default).
#                 Useful if you have the same process names running
#                 under different users.
#
#    type: Either service or process. This determines how the status
#          will be checked on the server (process is default).
#
#    port: A portnumber. This will check if the process is connected to
#          the given port (optional).
#
# SHOWMEM_STAT (Y/N): Y if memory statistics should be shown.
#
# SHOWRUNNINGSINCE_STAT (Y/N): Y if the start time/date of the process
# should be shown. 
#
# USE_PIGGYBACK (Y/N): If Y, you can send the output of the local 
# check to another check_mk defined host or dummy host.
#
# PIGGYBACK_TARGET: Used if USE_PIGGYBACK is Y. The target is either a 
# dummyhost or another check_mk defined host.
#
# PREFIX: This is useful if output of this check is shown inside
# a dummyhost, along with output of the same check for multiple servers.
# If the prefix is for example the subdomain of the server, the
# displayed check name would be constructed as
#
# <subdomain>_<name>_<process/service>
#    instead of
# <procname>_<process/service>
# 
# Copyright (c) 2016, Jeroen Wierda (jeroen@wierda.com)
# Date : 04-09-2016
#
# --------------------------------------------------------------------
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#######################################################################
declare -a PROCESS_NAMES

#PROCESS_NAMES[0]="processname:friendly name:run as user:type(service or process):port"
#One process or service per line. Increment the digit for each new line.
#Examples:
PROCESS_NAMES[1]="monit:Monit Monitoring:root:service"
PROCESS_NAMES[2]="filebeat:Filebeat Standalone:root:process"

SHOWMEM_STAT="Y"
SHOWRUNNINGSINCE_STAT="Y"
USE_PIGGYBACK="N"
PIGGYBACK_TARGET=""
PREFIX=""

#The bytesToHuman function below came from: http://unix.stackexchange.com/questions/44040/a-standard-tool-to-convert-a-byte-count-into-human-kib-mib-etc-like-du-ls1
bytesToHuman() {
	b=${1:-0}; d=''; s=0; S=(Bytes {K,M,G,T,E,P,Y,Z}iB)
	while ((b > 1024)); do
		d="$(printf ".%02d" $((b % 1024 * 100 / 1024)))"
		b=$((b / 1024))
		let s++
	done
	echo "$b$d ${S[$s]}"
}

SERVICE_MAN_A=`which systemctl 2> /dev/null`
SERVICE_MAN_B=`which service 2> /dev/null`

if [ "${USE_PIGGYBACK}" = "Y" ] && [ -n "${PIGGYBACK_TARGET}" ]; then
	echo -e "<<<<${PIGGYBACK_TARGET}>>>>"
	echo -e "<<<local>>>"
fi

if [ -n "$PREFIX" ]; then SRV_PREFIX="${PREFIX}_"; else SRV_PREFIX=""; fi

for PROCESS_STRING in "${PROCESS_NAMES[@]}"
do
	i=0
	declare -a PROC_ARRAY
	IFS=':' read -r -a PROC_ARRAY <<< "${PROCESS_STRING}"
	
	while [ $i -lt 5 ]
	do
		if [ $i -eq 0 ] && [ -z "${PROC_ARRAY[0]}" ]; then
			continue
		elif [ $i -eq 1 ] && [ -z "${PROC_ARRAY[1]}" ]; then
			PROC_NAME[1]=${PROC_NAME[0]}
		elif ([ $i -eq 2 ] && [ -z "${PROC_ARRAY[2]}" ]) || ([ $i -eq 2 ] && ! [ `id -u "${PROC_ARRAY[2]}" 2> /dev/null` ]); then
			PROC_NAME[2]="root"
		elif [ $i -eq 3 ] && [ -z "${PROC_ARRAY[3]}" ]; then
			PROC_NAME[3]="process"
		elif ([ $i -eq 4 ] && [ -z "${PROC_ARRAY[4]}" ]) || ([ $i -eq 4 ] && [[ ${PROC_ARRAY[4]} =~ ^-?[^0-9]+$ ]]); then
			PROC_NAME[4]=""
		else
			PROC_NAME[$i]=${PROC_ARRAY[$i]}
		fi
		((i++))
	done

	USERNAME=${PROC_NAME[2]}
	LOOKUP_TYPE=${PROC_NAME[3]}

	if [ "${LOOKUP_TYPE}" == "service" ]; then
		if [ -n "${SERVICE_MAN_A}" ]; then SERVICE_MAN=$SERVICE_MAN_A; STATUS_A="status "; else SERVICE_MAN=$SERVICE_MAN_B; STATUS_B=" status"; fi
		CHECK_INIT=$(${SERVICE_MAN} ${STATUS_A}${PROC_NAME[0]}${STATUS_B})
		if [ $? -eq 0 ]; then SERVICE_STATUS="OK"; else SERVICE_STATUS="NOK"; fi

		if [ "${SHOWMEM_STAT}" == "Y" ] || [ "${SHOWRUNNINGSINCE_STAT}" == "Y" ] || [ -n "${PROC_NAME[4]}" ]; then
			PROC_ID=$(pgrep $(if [ "$USERNAME" != "root" ]; then echo "-u $USERNAME"; fi) ${PROC_NAME[0]} -o)
			if [ "${PROC_ID}" == "" ]; then SHOWRUNNINGSINCE_STAT="N"; SHOWMEM_STAT="N"; unset PROC_NAME[4]; fi
		fi
	fi

	if [ "${LOOKUP_TYPE}" == "process" ]; then
	
		if [ $USERNAME != "root" ]; then
			ASSOC_SUFFIX=$USERNAME
			declare PS_OUTPUT_$ASSOC_SUFFIX
			ASSOC_WHOLE="PS_OUTPUT_$ASSOC_SUFFIX"
			if [ "${!ASSOC_WHOLE}" != "" ]; then
				GRAB_PROCESSLIST=${!ASSOC_WHOLE}
			else
				GRAB_PROCESSLIST=$(ps -u $USERNAME -f)
				declare PS_OUTPUT_$USERNAME="${GRAB_PROCESSLIST}"
			fi
		else
			GRAB_PROCESSLIST=$(ps -ef)
		fi

		CHECK_PROC=$(echo "$GRAB_PROCESSLIST" |grep -v "grep" |grep "${PROC_NAME[0]}")

		if ! [ -n "$CHECK_PROC" ]; then
			SERVICE_STATUS="NOK"
		else
			SERVICE_STATUS="OK"
		fi
		
		if [ "${SHOWMEM_STAT}" == "Y" ] || [ "${SHOWRUNNINGSINCE_STAT}" == "Y" ] || [ -n "${PROC_NAME[4]}" ]; then
			PROC_ID_A=$(echo $CHECK_PROC |awk '{print $2}')
			#get main proc ID:
			PROC_ID_B=$(ps -o ppid= -p ${PROC_ID_A} |sed -e 's/^[[:space:]]*//')
			if [ "${PROC_ID_B}" == "1" ]; then
				PROC_ID=$PROC_ID_A
			else
				PROC_ID=$PROC_ID_B
			fi
		fi
		
	fi

	if [ "${SHOWRUNNINGSINCE_STAT}" == "Y" ] || [ "${SHOWMEM_STAT}" == "Y" ]; then
		START_BRACK="("
		END_BRACK=")"
	fi

	if [ "${SHOWRUNNINGSINCE_STAT}" == "Y" ]; then
		PROC_RUN=$(ps -p $PROC_ID -o lstart=)
		RUNNING_TEXT="Running since: ${PROC_RUN}"
	else
		RUNNING_TEXT=""
	fi

	if [ "${SHOWMEM_STAT}" == "Y" ]; then
		if [ "${SHOWRUNNINGSINCE_STAT}" == "Y" ]; then SHOW_SEPARATOR=" - "; else SHOW_SEPARATOR=""; fi
		PROC_MEM=$((`pmap -x $PROC_ID | tail -1 |awk '{print $3}'` * 1024))
		PROC_MEMH=$(bytesToHuman $PROC_MEM)
		MEM_TEXT="${SHOW_SEPARATOR}MemUse: $PROC_MEMH"
	else
		MEM_TEXT=""
	fi

	if [ -n "${PROC_NAME[4]}" ]; then
		PROC_CONNECTED=$(netstat -p -n |grep ${PROC_NAME[4]} |tr "/" " " |awk '{print $7}' |grep $PROC_ID)
		if [ -z "$PROC_CONNECTED" ]; then SERVICE_STATUS="WARN"; fi
	fi

	if [ "${SERVICE_STATUS}" == "OK" ]; then
		echo 0 ${SRV_PREFIX}${PROC_NAME[1]// /_}_${LOOKUP_TYPE} - ${PROC_NAME[1]} ${LOOKUP_TYPE} OK ${START_BRACK}${RUNNING_TEXT}${MEM_TEXT}${END_BRACK}
	elif [ "${SERVICE_STATUS}" == "WARN" ]; then
		echo 1 ${SRV_PREFIX}${PROC_NAME[1]// /_}_${LOOKUP_TYPE} - ${PROC_NAME[1]} ${LOOKUP_TYPE} Is running, but not connected to port ${PROC_NAME[4]}
	else
		echo 2 ${SRV_PREFIX}${PROC_NAME[1]// /_}_${LOOKUP_TYPE} - ${PROC_NAME[1]} ${LOOKUP_TYPE} NOT RUNNING
	fi

	unset PROC_NAME CHECK_PROC SERVICE_STATUS PROC_ID PROC_RUN RUNNING_TEXT PROC_CONNECTED
done

if [ "${USE_PIGGYBACK}" == "Y" ] && [ -n "${PIGGYBACK_TARGET}" ]; then
	echo -e "<<<<>>>>"
fi