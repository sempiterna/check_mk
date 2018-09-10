#!/bin/bash
#
# Script to automate the update of the Check_MK agent on the server
# this script is installed on.
#
# Variables:
# SOURCE_IP: IP address or fqdn of the download server.
#
# SOURCE_PROTO: Protocol. http or https
#
# SOURCE LOCATION: In which absolute directory to look for the download
#
# SOURCE_VERSIONFILE: The filename containing the agent version. You,
# or the administrator need to create a file in the download location.
# The only contents of this file is the Check_MK agent version
# (e.g. 1.2.8p5).
#
# DOWNLOAD_PATH: Local path where the downloaded agent will be stored.
#
# LOG_PATH: Local path where the update log will be stored.
# This will contain info about the operation of this script.
#
# Optional variables:
#
# CHECK_MK_CHECK (Y/N): Y if used as Check_MK local check. Log
# output to stdout will be suppressed and check output and level will
# be shown.
#
# USE_PIGGYBACK (Y/N): If Y, you can send the output of the local 
# check to another check_mk defined host or dummy host.
#
# PIGGYBACK_TARGET: Used if USE_PIGGYBACK is Y. The target is either a 
# dummyhost or another check_mk defined host.
#
# CHECK_MK_CHECK_NAME: This is only used if USE_PIGGYBACK is N.
# The results will be listed as a service on the host this check runs
# on. We therefore need a descriptive name. If Piggyback is enabled,
# the hostname is used.
#
# AGENT_ISUPDATED_LEVEL(0/1/2/3): If output of this check is sent to
# check_mk, this variable will set the statuscode that will be sent to
# check_mk on a (successful) agent update. I set this to 1 (warn) in my
# setup, so that I get notified through check_mk if the agent is updated.
#
# DOWNLOAD_INSECURE (Y/N): If SOURCE_PROTO is set to https, and no valid
# ssl certificate is available, download without ssl check.
#
# Copyright (c) 2016, Jeroen Wierda (jeroen@wierda.com)
# Date : 04-08-2016
# Modify: 08-09-2018
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

SOURCE_IP="" # required!
SOURCE_PROTO="http"
SOURCE_LOCATION="/mon/check_mk/agents/"
SOURCE_VERSIONFILE="version"

DOWNLOAD_PATH="/opt/cmk" #where downloads are saved
LOG_PATH="/opt/cmk/log" #where logs should be written

##Use the variables below if this script is used as Check_MK check
##instead of stand-alone through a crontab.
CHECK_MK_CHECK="Y"
USE_PIGGYBACK="Y" #Y if results should be shown on another host
PIGGYBACK_TARGET="Check_MK.Agents" #Target hostname
CHECK_MK_CHECK_NAME="Check_MK Agent Updater" #only used if USE_PIGGYBACK=N
AGENT_ISUPDATED_LEVEL="1" # 0: OK, 1: WARN, 2: CRIT, 3: UNKNOWN
DOWNLOAD_INSECURE="N"

##no changes required below this line

CMK_AGENT=`which check_mk_agent`
DATE_CONSTRUCT="%d-%m-%Y %H:%M:%S"

if [ "${CHECK_MK_CHECK}" == "Y" ] && [ "${USE_PIGGYBACK}" == "Y" ] && [ -n "${PIGGYBACK_TARGET}" ]; then
        echo -e "<<<<${PIGGYBACK_TARGET}>>>>"
        echo -e "<<<local>>>"
fi

function log_writer {
	if [ "$1" == "1" ]; then LOG_TEXT="INFO"; else LOG_TEXT="ERROR"; fi
	CUR_TIMESTAMP=$(date +"${DATE_CONSTRUCT}")
	if [ "${CHECK_MK_CHECK}" == "N" ]; then
		echo -e "$CUR_TIMESTAMP : $LOG_TEXT $2" |tee -a ${LOG_PATH}/check.log
	else
		echo -e "$CUR_TIMESTAMP : $LOG_TEXT $2" >> ${LOG_PATH}/check.log
	fi
}

ALLVARS=("${DOWNLOAD_PATH}:0" "${LOG_PATH}:0")

function script_final() {
	if [ "${CHECK_MK_CHECK}" == "Y" ] && [ "${USE_PIGGYBACK}" == "Y" ] && [ -n "${PIGGYBACK_TARGET}" ]; then
		SERVICE_NAME=$(hostname --long)
	else
		SERVICE_NAME=${CHECK_MK_CHECK_NAME// /_}
	fi

	if [ "${CHECK_MK_CHECK}" == "Y" ] && ([ "$1" == "0" ] || [ "$1" == "1" ] || [ "$1" == "2" ]); then
		echo $1 ${SERVICE_NAME} - \(Agent:${INSTALLED_VERSION}\) $2
		log_writer "1" "Check_MK check output: \"$1 ${SERVICE_NAME} - (Agent:${INSTALLED_VERSION}) $2\""
	fi
	if [ "${CHECK_MK_CHECK}" == "Y" ] && [ "${USE_PIGGYBACK}" == "Y" ] && [ -n "${PIGGYBACK_TARGET}" ]; then
		echo -e "<<<<>>>>"
	fi
	exit 0
}

function check_directories() {
	EXITSTATUS=0
	declare -a A=("${!1}")

	for VAR in "${A[@]}"
	do
		DIR_A=$(echo $VAR | awk -F':' '{print $1}')
		DIR_CHECK=$(echo $VAR | awk -F':' '{print $2}')

		case "$DIR_A" in
		*\ * )
			echo "$DIR_A : contains a space."
			EXITSTATUS=1
		;;
		esac

		if [ "${#DIR_A}" -gt "0" ] && ( [ "${DIR_A:0:1}" != "/" ] || [ "${#DIR_A}" -lt "3" ] ); then
			echo "$DIR_A : less than 3 characters long, or it does not start with a /"
			EXITSTATUS=1
		fi

		if [ "${DIR_CHECK}" -eq "1" ]; then
			if ! [ -d "${DIR_A}" ]; then
				echo "$DIR_A : Does not exist on this system."
				EXITSTATUS=1
			fi
		fi
	done

	if [ "$EXITSTATUS" == "1" ]; then
		exit 1
	fi
	unset EXITSTATUS
}

download_agent() {
	FILE_EXISTS=$(${DOWN_BIN} ${DOWN_INSECURE}${WGET_EXTRAVARS}${SOURCE_PROTO}://${SOURCE_IP}${SOURCE_LOCATION} |sed -e 's/<[^>]*>//g' |grep ${SERVER_VERSION} |grep agent |grep $1 |sed -e 's/^[[:space:]]*//' 2>/dev/null)
	if [ -n "$FILE_EXISTS" ]; then
		if [ -f ${DOWNLOAD_PATH}/${FILE_EXISTS} ]; then
			log_writer "1" "File \"${FILE_EXISTS}\" already exists in ${DOWNLOAD_PATH}. Not downloading again."
		else
			cd ${DOWNLOAD_PATH} && $DOWN_BIN ${DOWN_INSECURE}${CURL_EXTRAVARS}${SOURCE_PROTO}://${SOURCE_IP}${SOURCE_LOCATION}${FILE_EXISTS}
			if [ $? != 0 ]; then
				ERROR_MSG="Something went wrong while trying to download the Check_MK agent from ${SOURCE_PROTO}://${SOURCE_IP}${SOURCE_LOCATION}${FILE_EXISTS}."
				log_writer "2" "${ERROR_MSG}"
				script_final "2" "${ERROR_MSG}"
				#exit 1
			else
				log_writer "1" "File \"${FILE_EXISTS}\" downloaded and stored in ${DOWNLOAD_PATH}."
			fi
		fi
	else
		ERROR_MSG="The requested agent version (${SERVER_VERSION}) can not be found at ${SOURCE_PROTO}://${SOURCE_IP}${SOURCE_LOCATION}."
		log_writer "2" "${ERROR_MSG}"
		script_final "2" "${ERROR_MSG}"
		#exit 1
	fi
}

check_directories ALLVARS[@]

for DIR_CHECK in "${ALLVARS[@]}"
do
	if ! [ -d ${DIR_CHECK%??} ]; then
		mkdir -p ${DIR_CHECK%??}
	fi
done

if [ -z "${CMK_AGENT}" ]; then
	log_writer "2" "There is no Check_MK agent installed on this server."
	exit 1
fi

WGET_BIN=`which wget`

if [ -z "${WGET_BIN}" ]; then
	CURL_BIN=`which curl`
	if [ "${CURL_BIN}" == "" ]; then
		ERROR_MSG="Neither WGET or CURL is installed. The Check_MK agent cannot be downloaded."
		log_writer "2" "${ERROR_MSG}"
		script_final "2" "${ERROR_MSG}"
		#exit 1
	else
		log_writer "1" "No wget available, using ${CURL_BIN} to download."
		DOWN_BIN="$CURL_BIN -s"
		if [ "${SOURCE_PROTO}" == "https" ] && [ "${DOWNLOAD_INSECURE}" == "Y" ]; then
			DOWN_INSECURE="--insecure "
		fi
		CURL_EXTRAVARS="-O "
	fi
else
	DOWN_BIN="$WGET_BIN -q"
	if [ "${SOURCE_PROTO}" == "https" ] && [ "${DOWNLOAD_INSECURE}" == "Y" ]; then
		DOWN_INSECURE="--no-check-certificate "
	fi
	WGET_EXTRAVARS=" -O - "
fi

INSTALLED_VERSION=$(${CMK_AGENT} |head -2 | sed -n '2p' | cut -d':' -f2 |sed -e 's/^[[:space:]]*//')
SERVER_VERSION=$(${DOWN_BIN} ${DOWN_INSECURE}${WGET_EXTRAVARS}${SOURCE_PROTO}://${SOURCE_IP}${SOURCE_LOCATION}${SOURCE_VERSIONFILE} 2>/dev/null)

if [ -z "${INSTALLED_VERSION}" ]; then
	log_writer "2" "The current version number of the Check_MK agent could not be retrieved."
	exit 1
elif [ -z "${SERVER_VERSION}" ]; then
	ERROR_MSG="Either the version file (${SOURCE_PROTO}://${SOURCE_IP}${SOURCE_LOCATION}${SOURCE_VERSIONFILE}) could not be retrieved, or the content is empty."
	log_writer "2" "${ERROR_MSG}"
	script_final "2" "${ERROR_MSG}"
	#exit 1
elif [ "${INSTALLED_VERSION}" == "${SERVER_VERSION}" ]; then
	if [ -f ${LOG_PATH}/updated ]; then LAST_UPDATED="Last updated at $(cat ${LOG_PATH}/updated)".; fi
	ERROR_MSG="No new Check_MK agent available. ${LAST_UPDATED}"
	log_writer "1" "No new Check_MK agent available. Current: ${INSTALLED_VERSION}, New: ${SERVER_VERSION}"
	script_final "0" "${ERROR_MSG}"
	#exit 0
elif [ "${INSTALLED_VERSION}" != "${SERVER_VERSION}" ]; then
	log_writer "1" "New Check_MK agent available. Current: ${INSTALLED_VERSION}, New: ${SERVER_VERSION}"

	DOWNLOAD_OPTIONS_R=("yum:-y -q --nogpgcheck install" "rpm:-i --quiet --force --nosignature")
	DOWNLOAD_OPTIONS_D=("gdebi:--n --quiet" "dpkg:-i --no-debsig")

	function agent_install() {
		declare -a PMAN=("${!1}")
		for DOWNLOAD_OPTIONS in "${PMAN[@]}"
		do
			PACKAGE_MANAGER=$(echo ${DOWNLOAD_OPTIONS} | awk -F':' '{print $1}')
			PACKAGE_MANAGER_OPT=$(echo ${DOWNLOAD_OPTIONS} | awk -F':' '{print $2}')
			PM_DETECT=$(which $PACKAGE_MANAGER)
			if [ -n "${PM_DETECT}" ]; then
				$PM_DETECT $PACKAGE_MANAGER_OPT ${DOWNLOAD_PATH}/${FILE_EXISTS} > /dev/null 2>&1
				if [ $? != 0 ]; then
					GETENFORCE_LOC=$(which getenforce)
					if [ `echo ${PM_DETECT} |grep -i ${PACKAGE_MANAGER}` ] && [ -n "${GETENFORCE_LOC}" ] && [ `${GETENFORCE_LOC} | grep -i enforcing` ]; then
						SELINUX_MSG=" Selinux is detected and running in mode Enforcing. This may prevent this script from using ${PACKAGE_MANAGER}."
					fi
					ERROR_MSG="${PACKAGE_MANAGER} could not install the Check_MK agent. Operation cancelled.${SELINUX_MSG}"
					log_writer "2" "${ERROR_MSG}"
					script_final "2" "${ERROR_MSG}"
				else
					SUCCESS=1
				fi
				break
			fi
		done
	}

	if [ "$(which rpm)" != "" ]; then
		download_agent "rpm"
		agent_install DOWNLOAD_OPTIONS_R[@]
	else
		download_agent "deb"
		agent_install DOWNLOAD_OPTIONS_D[@]
	fi

	if [ "$SUCCESS" == "1" ]; then
		NEW_VERSION=$(${CMK_AGENT} |head -2 | sed -n '2p' | cut -d':' -f2 |sed -e 's/^[[:space:]]*//')
		if [ "${NEW_VERSION}" == "${SERVER_VERSION}" ]; then
			CUR_TIMESTAMP2=$(date +"${DATE_CONSTRUCT}")
			echo "${CUR_TIMESTAMP2}" > ${LOG_PATH}/updated
			INSTALLED_VERSION=${NEW_VERSION}
			ERROR_MSG="The Check_MK agent has successfully been updated. Updated on ${CUR_TIMESTAMP2}."
			log_writer "1" "The Check_MK agent has successfully been upgraded to ${NEW_VERSION}."
			script_final "${AGENT_ISUPDATED_LEVEL}" "${ERROR_MSG}"
		else
			log_writer "2" "The Check_MK agent was upgraded, but the versions do not match. Current version: ${NEW_VERSION}, Server version: ${SERVER_VERSION}."
		fi
	fi
fi
