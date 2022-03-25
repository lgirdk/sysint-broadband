#!/bin/sh
##################################################################################
# If not stated otherwise in this file or this component's Licenses.txt file the
# following copyright and licenses apply:
#
#  Copyright 2022 Liberty Global B.V.
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
################################################################################

#-------------------------------------------------------------------------------
#This file run as scheduled task and backup selcted logs from /rdklogs/logs
# to /tmp. The backup logs are made available for plume log pull
#-------------------------------------------------------------------------------

#Maximum size of *.1 log file
BCKUP_MAXSIZE=800000

RDK_LOGS_PATH=/rdklogs/logs/
LOG_BACK_UP_PATH=/tmp/Plumelogbackup_ATOM/

#Check is plume log pull is enabled. Perform backup only if Plume log pull is enabled
logpull_enable=`syscfg get son_logpull_enable`
if [ -z "$logpull_enable" ] || [ "$logpull_enable" = "0" ] ;
then
    exit
fi

if [ -f /etc/device.properties ]
then
    source /etc/device.properties
fi

#File which stores the 'modify' timestamp of *.1 log files in /rdklogs/logs
if [ -f /tmp/timestamp.sh ]
then
    source /tmp/timestamp.sh
else
    touch /tmp/timestamp.sh
fi

Log_files="wifi_vendor.log wifi_vendor_apps.log wifi_vendor_hal.log WiFilog.txt.0 WiFilog.txt.1 wifihealth.txt SelfHeal.txt.0 SelfHeal.txt.0.1 MeshAgentLog.txt.0 MeshAgentLog.txt.1 AtomConsolelog.txt.0 AtomConsolelog.txt.0.1"

DoBackup_1()
{
    #1. Check if file already exists in backup folder
    if [ -f $LOG_BACK_UP_PATH$1 ]
    then
	#2. Check the size of file. If gretaer than 800 KB, move the file to .2 and copy the file from rdklogs
	size=`stat -c %s $LOG_BACK_UP_PATH$1`
	if [ $size -ge $BCKUP_MAXSIZE ]
	then
	    mv $LOG_BACK_UP_PATH$1 $LOG_BACK_UP_PATH$1".2"
	    cp $RDK_LOGS_PATH$1 $LOG_BACK_UP_PATH

	else
	    #3. Append the rdklogs file contents to backup 
	    cat $RDK_LOGS_PATH$1 >> $LOG_BACK_UP_PATH$1
        fi

    else
	cp $RDK_LOGS_PATH$1 $LOG_BACK_UP_PATH
    fi
}

#Perform log backup of *.1 files
CreateLogBackup_1()
{
    timestamp=`stat -c %Y $RDK_LOGS_PATH$1`

    #Check for the previous timestamp of the log file
    case "$1" in
               "WiFilog.txt.1") 
		       if [ "$WIFI" != $timestamp ]
		        then
		           DoBackup_1 $1
		           #remove the entry of WIFI timestamp from file and add new timestamp
			   sed -i '/WIFI/d' /tmp/timestamp.sh
			   echo "WIFI="$timestamp  >> /tmp/timestamp.sh
		        fi
               ;;

	      "MeshAgentLog.txt.1") 
		       if [ "$MESH" != $timestamp ]
		        then
		           DoBackup_1 $1
		           #remove the entry of MESH timestamp from file and add new timestamp
			   sed -i '/MESH/d' /tmp/timestamp.sh
			   echo "MESH="$timestamp  >> /tmp/timestamp.sh
		        fi
               ;;

              "SelfHeal.txt.0.1") 
		       if [ "$SELFHEAL" != $timestamp ]
		        then
		           DoBackup_1 $1
		           #remove the entry of SelfHeal timestamp from file and add new timestamp
			   sed -i '/SELFHEAL/d' /tmp/timestamp.sh
			   echo "SELFHEAL="$timestamp  >> /tmp/timestamp.sh
		        fi
               ;;

             "AtomConsolelog.txt.0.1") 
		       if [ "$ARMCONSOLE" != $timestamp ]
		        then
		           DoBackup_1 $1
		           #remove the entry of ArmConsole timestamp from file and add new timestamp
			   sed -i '/ATOMCONSOLE/d' /tmp/timestamp.sh
			   echo "ATOMCONSOLE="$timestamp  >> /tmp/timestamp.sh
		        fi
               ;;
    
    esac
}

#Perform log backup
CreateLogBackUp()
{
    #Check if backupFolder already exists or not. If not, then create a directory
    if [ ! -d "$LOG_BACK_UP_PATH" ]
    then
        mkdir $LOG_BACK_UP_PATH
    fi

    case $1 in
        *.1)
              CreateLogBackup_1 $1
              ;;
        *)
              #copy *log.txt.0 contents to backup.
              cp $RDK_LOGS_PATH$1 $LOG_BACK_UP_PATH
              ;;
    esac
}

#Backup ATOM logs
for file in $Log_files ; do
    CreateLogBackUp $file
done

