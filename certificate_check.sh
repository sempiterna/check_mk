#!/bin/bash
#
# Check_mk local check to check the validity (expiration date) of
# certificates. Port numbers can be supplied to check certificates
# on services other than https, or https listening on different ports.
#
# Variables:
# CHECK_SITES: array where hostname:port can be supplied. 
# Multiple value separated by a space.
#
# USE_PIGGYBACK (Y/N): If Y, you can send the output of the local 
# check to another check_mk defined host or dummy host.
#
# PIGGYBACK_TARGET: Used if USE_PIGGYBACK is Y. The target is either a 
# dummyhost or another check_mk defined host.
#
# WARN_DAYS/CRIT_DAYS: Number of days before expiration to send a 
# warning or critical status.
#
# Copyright (c) 2016, Jeroen Wierda (jeroen@wierda.com)
# Date : 30-06-2016
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
declare -a CHECK_SITES
declare -a ERROR_DOM

#CHECK_SITES=("www.site1.com" "smtp.site15.com:465" "some.otherservice.com:7001")
CHECK_SITES=("www.site1.com")
USE_PIGGYBACK="Y"
PIGGYBACK_TARGET="chat4all.org"
WARN_DAYS=30
CRIT_DAYS=15

OPENSSLBIN=`which openssl`
DATEBIN=`which date`

[ -z "${CHECK_SITES}" ] && { echo -e "Specify at least one FQDN in CHECK_SITES"; exit 1; }

if [ -z ${OPENSSLBIN} ] || [ -z ${DATEBIN} ]; then EXIT_ERROR=1; else EXIT_ERROR=0; fi

if [ "${USE_PIGGYBACK}" = "Y" ] && [ -n "${PIGGYBACK_TARGET}" ]; then
	echo -e "<<<<${PIGGYBACK_TARGET}>>>>"
	echo -e "<<<local>>>"
fi

if [ ${EXIT_ERROR} -eq 0 ]; then

	DATE_NOW=$(${DATEBIN} +%s)

	for SITE in "${CHECK_SITES[@]}"
	do
		SITE_ADDRESS=$(echo ${SITE} | awk -F':' '{print $1}')
		SITE_PORT=$(echo ${SITE} | awk -F':' '{print $2}')

		if [ -z "${SITE_PORT}" ]; then
			SITE_PORT=443
		fi

		CERT=$(echo | ${OPENSSLBIN} s_client -connect ${SITE_ADDRESS}:${SITE_PORT} 2>/dev/null)

		if ! [ $? == 0 ]; then
			EXIT_ERROR=1
			ERROR_DOM+=("${SITE_ADDRESS}")
			continue
		fi

		CERT_ENDDATE=$(echo "${CERT}" | ${OPENSSLBIN} x509 -noout -dates  | tail -1| awk -F'=' '{print $2}')

		CERT_ENDDATE_EPOCH=$(${DATEBIN} --date "$CERT_ENDDATE" '+%s')

		CERT_SUBJECT=$(echo "${CERT}" |${OPENSSLBIN} x509 -noout -subject | awk -F'CN=' '{print $2}' | awk -F'/' '{print $1}')

		DATE_DIFF=$((${CERT_ENDDATE_EPOCH}-${DATE_NOW}))
		DATE_DAYSLEFT=$(awk "BEGIN { rounded = sprintf(\"%.0f\", ${DATE_DIFF}/60/60/24); print rounded }")
		
		if [ ${DATE_DAYSLEFT} -lt 0 ]; then
			STATUS=2
			STATUS_TEXT="expired"
			STATUS_DAYS=""
		elif [ ${DATE_DAYSLEFT} -le ${CRIT_DAYS} ]; then
			STATUS=2
			STATUS_TEXT="will expire"
			STATUS_DAYS="in ${DATE_DAYSLEFT} days "
		elif [ ${DATE_DAYSLEFT} -lt ${WARN_DAYS} ]; then
			STATUS=1
			STATUS_TEXT="will expire"
			STATUS_DAYS="in ${DATE_DAYSLEFT} days "
		else
			STATUS=0
			STATUS_TEXT="will expire"
			STATUS_DAYS="in ${DATE_DAYSLEFT} days "
		fi

		echo ${STATUS} cert_${SITE_ADDRESS//./_} - Certificate ${CERT_SUBJECT} \(port ${SITE_PORT}\) ${STATUS_TEXT} ${STATUS_DAYS}on ${CERT_ENDDATE}

	done

fi

if [ ${EXIT_ERROR} -eq 1 ]; then
	if [ ${#ERROR_DOM[*]} == 0 ]; then
	for SITE in "${CHECK_SITES[@]}"
	do
		SITE_ADDRESS=$(echo ${SITE} | awk -F':' '{print $1}')
		echo 3 cert_${SITE_ADDRESS//./_} - Either one of the binaries openssl or date can not be found.
	done
	else
		for ERROR_ITEM in "${ERROR_DOM[@]}"
		do
			echo 2 cert_${ERROR_ITEM//./_} - There was a problem obtaining the certificate for ${ERROR_ITEM}
		done
	fi
fi

if [ "${USE_PIGGYBACK}" == "Y" ] && [ -n "${PIGGYBACK_TARGET}" ]; then
	echo -e "<<<<>>>>"
fi
