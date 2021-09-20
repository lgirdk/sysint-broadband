#!/bin/sh
##########################################################################
# If not stated otherwise in this file or this component's Licenses.txt
# file the following copyright and licenses apply:
#
# Copyright 2016 RDK Management
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################

source /etc/device.properties
source /etc/logFiles.properties
source /etc/log_timestamp.sh

LOG_PATH=/rdklogs/logs

MAXSIZE_ATOM=5000
MAX_FILE_SIZE_ATOM=300

TFTP_PORT=69
udpsvd -vE $ATOM_ARPING_IP $TFTP_PORT tftpd $LOG_PATH &

#wait for components to create log
sleep 10

TMP_FILE_LIST=$(echo $ATOM_FILE_LIST | tr "," " " | tr "{" " " | tr "}" " " | tr "*" "0")
TMP_FILE_LIST=${TMP_FILE_LIST/"txt0"/"txt"}
for file in $TMP_FILE_LIST; do
  if [ ! -f $LOG_PATH/$file ]; then
   touch $LOG_PATH/$file
  fi
done

while :
do
	sleep 60

	# Rotate the log files in FILE_LIST_LIMIT_SIZE_ATOM (which are not handled by rdk-logger log4crc)
	for file in $FILE_LIST_LIMIT_SIZE_ATOM
	do
		actualFileName="$(eval echo \$$file)"
		totalSize=$(du -c $LOG_PATH/$actualFileName | tail -n1 | awk '{print $1}')
		if [ "$totalSize" -ge "$MAX_FILE_SIZE_ATOM" ]; then
			# Copy file_name -> file_name.1 and truncate the original file.
			# Apps have file_name open, so it should not be moved / renamed.
			cp $LOG_PATH/${actualFileName} $LOG_PATH/${actualFileName}.1
			>$LOG_PATH/${actualFileName}
		fi
	done

	totalSize=$(du -c $LOG_PATH | tail -n1 | awk '{print $1}')

	if [ $totalSize -ge $MAXSIZE_ATOM ]; then
		echo_t "MAXSIZE_ATOM reached, upload the logs"
		dmcli eRT setv Device.LogBackup.X_RDKCENTRAL-COM_SyncandUploadLogs bool true
	fi
done
