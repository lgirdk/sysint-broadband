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

RDK_LOGGER_PATH="/rdklogger"

NVRAM2_SUPPORTED="no"
source $RDK_LOGGER_PATH/logfiles.sh
source /lib/rdk/utils.sh
source $RDK_LOGGER_PATH/logUpload_default_params.sh

LOG_UPLOAD_PID="/tmp/.log_upload.pid"
REBOOT_PENDING_DELAY=2
SE05x_rdk_logs="se05x_daemon.log"
SE05x_tmp_logs="/tmp/rdkssa.txt"

IHC_Enable="`syscfg get IHC_Mode`"
#starting the IHC now
if [[ "$IHC_Enable" = "Monitor" ]]
then
    echo_t "Starting the ImageHealthChecker from store-health mode"
    /usr/bin/ImageHealthChecker store-health &
fi

# exit if an instance is already running
if [ ! -f $LOG_UPLOAD_PID ];then
    # store the PID
    echo $$ > $LOG_UPLOAD_PID
else
    pid=`cat $LOG_UPLOAD_PID`
    if [ -d /proc/$pid ];then
          echo_t "backupLogs.sh already running..."
          if [ "$1" = "true" ] || [ "$1" = "" ] ; then
              echo_t "backupLogs.sh wait time started..."
              while [ -d /proc/$pid ] ; do 
                  sleep 10
              done
              echo_t "backupLogs.sh wait time ended..."
              echo $$ > $LOG_UPLOAD_PID
          else
               echo_t "backupLogs.sh other instance exited..."
               exit 0
          fi
    else
          echo $$ > $LOG_UPLOAD_PID
    fi
fi

PING_PATH="/usr/sbin"
MAC=`getMacAddressOnly`
dt=`date "+%m-%d-%y-%I-%M%p"`
LOG_FILE=$MAC"_Logs_$dt.tgz"
needReboot="true"
PATTERN_FILE="/tmp/pattern_file"

if [ "$NVRAM2_SUPPORTED" = "yes" ] && [ "$(syscfg get logbackup_enable)" = "true" ]
then
   nvram2Backup="true"
else
   nvram2Backup="false"
fi

backup_log_pidCleanup()
{
   # PID file cleanup
   if [ -f $LOG_UPLOAD_PID ];then
        rm -rf $LOG_UPLOAD_PID
   fi
}

getTFTPServer()
{
        if [ "$1" != "" ]
        then
        logserver=`grep $1 $RDK_LOGGER_PATH/dcmlogservers.txt | cut -f2 -d"|"`
		echo $logserver
	fi
}

Trigger_RebootPendingNotify()
{
	#Trigger RebootPendingNotification prior to device reboot for all software managed types of reboots
	echo_t "RDKB_REBOOT : Setting RebootPendingNotification before reboot"
	dmcli eRT setv Device.DeviceInfo.X_RDKCENTRAL-COM_xOpsDeviceMgmt.RPC.RebootPendingNotification uint $REBOOT_PENDING_DELAY
	echo_t "RDKB_REBOOT  : RebootPendingNotification SET succeeded"
}

getBuildType()
{
   IMAGENAME=$(sed -n 's/^imagename[:=]"\?\([^"]*\)"\?/\1/p' /version.txt)

   TEMPDEV=`echo $IMAGENAME | grep DEV`
   if [ "$TEMPDEV" != "" ]
   then
       echo "DEV"
   fi
 
   TEMPVBN=`echo $IMAGENAME | grep VBN`
   if [ "$TEMPVBN" != "" ]
   then
       echo "VBN"
   fi

   TEMPPROD=`echo $IMAGENAME | grep PROD`
   if [ "$TEMPPROD" != "" ]
   then
       echo "PROD"
   fi
   
   TEMPCQA=`echo $IMAGENAME | grep CQA`
   if [ "$TEMPCQA" != "" ]
   then
       echo "CQA"
   fi
   
}


BUILD_TYPE=`getBuildType`
SERVER=`getTFTPServer $BUILD_TYPE`

backupLogsonReboot()
{
	curDir=`pwd`
	if [ ! -d "$LOG_BACK_UP_REBOOT" ]
	then
	    mkdir $LOG_BACK_UP_REBOOT
	fi

	rm -rf $LOG_BACK_UP_REBOOT*
	
	cd $LOG_BACK_UP_REBOOT
	mkdir $dt

	# Put system descriptor string in log file
	#createSysDescr

	cd $LOG_PATH
	FILES=`ls`

	for fname in $FILES
	do
		# Copy all log files from the log directory to non-volatile memory
		cp $fname $LOG_BACK_UP_REBOOT$dt ; >$fname;

	done



    # No need of checking whether file exists. Move everything

    #ret=`allFileExists $LOG_PATH`
	
	#if [ "$ret" = "yes" ]
	#then
	    #moveFiles $LOG_PATH $LOG_BACK_UP_REBOOT$dte
	#    moveFiles $LOGTEMPPATH $LOG_BACK_UP_REBOOT$dte
	#elif [ "$ret" = "no" ]
	#then

	#	for fname in $LOG_FILES_NAMES
	#	do
	#	    	if [ -f "$LOGTEMPPATH$fname" ] ; then moveFile $LOGTEMPPATH$fname $LOG_BACK_UP_REBOOT$dte; fi
	#	done

	#fi
	cd $LOG_BACK_UP_REBOOT
	cp /version.txt $LOG_BACK_UP_REBOOT$dt
	if [ "$MODEL_NUM" = "CGM4981COM" ] || [ "${MODEL_NUM}" = "CGM601TCOM" ] || [ "${MODEL_NUM}" = "SG417DBCT" ] || [ "$MODEL_NUM" == "SR213" ]; then
	      cp $SE05x_tmp_logs $LOG_BACK_UP_REBOOT$dt$SE05x_rdk_logs
	fi

	if [ "$ATOM_SYNC" = "yes" ]
	then
		echo_t "Check whether ATOM ip accessible before syncing ATOM side logs"
		if [ -f $PING_PATH/ping_peer ]
		then

   		        PING_RES=`ping_peer`
			CHECK_PING_RES=`echo $PING_RES | grep "packet loss" | cut -d"," -f3 | cut -d"%" -f1`

			if [ "$CHECK_PING_RES" != "" ]
			then
				if [ "$CHECK_PING_RES" != "100" ]
				then
					echo_t "Ping to ATOM ip success, syncing ATOM side logs"					
					sync_atom_log_files $LOG_BACK_UP_REBOOT$dt/
#nice -n 20 rsync root@$ATOM_IP:$ATOM_LOG_PATH$ATOM_FILE_LIST $LOG_BACK_UP_REBOOT$dt/ > /dev/null 2>&1
				else
					echo_t "Ping to ATOM ip falied, not syncing ATOM side logs"
				fi
			else
				echo_t "Ping to ATOM ip falied, not syncing ATOM side logs"
			fi
		fi

	fi
	if [ -f /tmp/backup_onboardlogs ]; then
        backup_onboarding_logs
    fi
	#echo "*.tgz" > $PATTERN_FILE # .tgz should be excluded while tar
	#tar -X $PATTERN_FILE -cvzf $MAC"_Logs_$dt.tgz" $dt
	#rm $PATTERN_FILE
	echo_t "Created backup of all logs..."
	rm -rf $dt	
 	ls

	# ARRISXB3-2544 :
	# It takes too long for the unit to reboot after TFTP is completed.
	# Hence we can upload the logs once the unit boots up. We will flag it before reboot.
	touch $UPLOAD_ON_REBOOT
	#$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "TFTP" "URL" "true"
	cd $curDir
   
}

backupLogsonReboot_nvram2()
{
        echo_t "[DEBUG] ++IN Function backupLogsonReboot_nvram2" >> /rdklogs/logs/telemetry2_0.txt.0
	curDir=`pwd`
	if [ ! -d "$LOG_SYNC_BACK_UP_REBOOT_PATH" ]; then
	    mkdir $LOG_SYNC_BACK_UP_REBOOT_PATH
	fi

        DCA_COMPLETED="/tmp/.dca_done"

	#rm -rf $LOG_SYNC_BACK_UP_REBOOT_PATH*

	# Put system descriptor string in log file if it is a software upgrade.
        # For non-software upgrade reboots, sysdescriptor will be printed during bootup
	if [ -f "/nvram/reboot_due_to_sw_upgrade" ]
        then
             createSysDescr
        fi 

        echo_t  "[DEBUG] $0 Notify telemetry to execute now before log upload !!!" >> /rdklogs/logs/telemetry2_0.txt.0
	if [ "$needReboot" = "true" ]; then
            # Similar to RDKB-9204 - Avoid telemetry computation from GUI or SNMP initiated reboot
            echo_t  "[DEBUG] $0 telemetry reports excluded to avoid delays in reboot from SNMP/TR181/GUI !!!" >> /rdklogs/logs/telemetry2_0.txt.0
	else 
            sh /lib/rdk/dca_utility.sh 2 &
            local loop=0
            while :
            do
                sleep 10
                loop=$((loop+1))
                if [ -f "$DCA_COMPLETED" ] || [ "$loop" -ge 6 ]
                then
                    echo_t "[DEBUG] $0 telemetry operation completed loop count = $loop" >> /rdklogs/logs/telemetry2_0.txt.0
                    rm -rf $DCA_COMPLETED
                    break
                fi
            done
        fi

	syncLogs_nvram2

        if [ -e $HAVECRASH ]
        then
            if [ "$ATOM_SYNC" = "yes" ]
            then
               # Remove the contents of ATOM side log files.
                echo_t "Call dca for log processing and then flush ATOM logs"
                flush_atom_logs 
            fi
            rm -rf $HAVECRASH
        fi

	cd $LOG_PATH
	FILES=`ls`

        echo_t "[DEBUG] backupLogsonReboot_nvram2: flushing logs" >> /rdklogs/logs/telemetry2_0.txt.0
	for fname in $FILES
	do
		>$fname;
	done

	cd $LOG_SYNC_BACK_UP_REBOOT_PATH
        cp /version.txt $LOG_SYNC_PATH
	if [ "$MODEL_NUM" = "CGM4981COM" ] || [ "${MODEL_NUM}" = "CGM601TCOM" ] || [ "${MODEL_NUM}" = "SG417DBCT" ] || [ "$MODEL_NUM" == "SR213" ]; then
	      cp $SE05x_tmp_logs $LOG_SYNC_PATH$SE05x_rdk_logs
	fi

	#echo "*.tgz" > $PATTERN_FILE # .tgz should be excluded while tar
	#tar -X $PATTERN_FILE -cvzf $MAC"_Logs_$dt.tgz" $LOG_SYNC_PATH
	#rm $PATTERN_FILE
	echo_t "Created backup of all logs..."
 	ls
	#rm -rf $LOG_SYNC_PATH*.txt*
	#rm -rf $LOG_SYNC_PATH*.log
	touch $UPLOAD_ON_REBOOT
	cd $curDir

        echo_t "[DEBUG] --OUT Function backupLogsonReboot_nvram2" >> /rdklogs/logs/telemetry2_0.txt.0
}

if [ "$2" = "l2sd0" ]
then
	if [ "$nvram2Backup" == "true" ]; then	
                createSysDescr
                syncLogs_nvram2	
                backupnvram2logs "$TMP_UPLOAD"
	else
                syncLogs
                backupAllLogs "$LOG_PATH" "$LOG_BACK_UP_PATH" "cp"
	fi

    $RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false" 
    backup_log_pidCleanup
    exit 0
else
  Crashed_Process_Is=$2
fi
#Call function to upload log files on reboot
if [ -e $HAVECRASH ]
then
    if [ "$Crashed_Process_Is" != "" ]
    then
	    echo_t "RDKB_REBOOT : Rebooting due to $Crashed_Process_Is PROCESS_CRASH"
    fi
    # We will remove the HAVECRASH flag after handling the log back up.
    #rm -f $HAVECRASH
fi

if [ "$3" == "wan-stopped" ] || [ "$3" == "Atom_Max_Log_Size_Reached" ] || [ "$2" == "DS_MANAGER_HIGH_CPU" ] || [ "$2" == "ATOM_RO" ]
then
	echo_t "Taking log back up"
	if [ "$nvram2Backup" == "true" ]; then	
                # Setting event to protect tar backup to /tmp whenever wan goes down and file size reached more than threshold
		sysevent set wan_event_log_upload yes
		createSysDescr
		syncLogs_nvram2	
		backupnvram2logs "$TMP_UPLOAD"
                if [ "$3" = "wan-stopped" ]
                then
                   isBackupEnabled=`syscfg get log_backup_enable`
                   if [ "$isBackupEnabled" = "true" ]
                   then
                      fileName=`ls $TMP_UPLOAD | grep tgz`
                      echo_t "Back up to preserve location is enabled"
                      # Call PreserveLog which will move logs to preserve location
                      preserveThisLog $fileName $TMP_UPLOAD $3
                   else
                      echo_t "Back up to preserve location is disabled"
                   fi
                fi
	else
	    syncLogs
		backupAllLogs "$LOG_PATH" "$LOG_BACK_UP_PATH" "cp"
	fi
else
	if [ "$nvram2Backup" == "true" ]; then	
		backupLogsonReboot_nvram2
	else
		backupLogsonReboot
	fi	

#TCCBR-6447: Removed condition for CBR, as the additional files wifi_config_nvram and wifi_config_nvram_bak
# are making "/data" full, leading to nvram corruption
	if [ "$BOX_TYPE" = "XF3" ]; then
		echo "Taking backup of /data/nvram and /data/nvram_bkup " >> "$LOG_SYNC_BACK_UP_PATH"Consolelog.txt.0
		cp /data/nvram /data/wifi_config_nvram
		cp /data/nvram_bak /data/wifi_config_nvram_bak
		echo "Logging ssid info and /data/ file information to Consolelog file" >> "$LOG_SYNC_BACK_UP_PATH"Consolelog.txt.0
		nvram show | grep ssid >> "$LOG_SYNC_BACK_UP_PATH"Consolelog.txt.0
		ls -lh /data/ >> "$LOG_SYNC_BACK_UP_PATH"Consolelog.txt.0
		
	fi
fi
#sleep 3

if [ "$4" = "upload" ]
then
	/rdklogger/uploadRDKBLogs.sh "" HTTP "" false
fi

if [ "$1" != "" ]
then
     needReboot=$1
fi

backup_log_pidCleanup

if [ "$needReboot" = "true" ]
then
	# RebootPendingNotifications are applicable only for residential devices and not applicable for business gateways.
	if [ "$IS_BCI" != "yes" ] || [ "$MODEL_NUM" = "CGA4332COM" ]; then
		echo_t "Trigger RebootPendingNotification in background"
		Trigger_RebootPendingNotify &
		echo_t "sleep for 1 sec to send reboot pending notification"
		sleep 1
	fi
	# kill parodus with SIGTERM
	if [ -f /lib/systemd/system/parodus.service ]; then
		echo_t "Shutdown parodus"
		systemctl stop parodus.service
	else
		echo_t "Properly shutdown parodus by sending SIGTERM kill signal"
		killall -s SIGTERM parodus
	fi
    #stop IGD process before reboot
    sysevent set igd-stop

    #check if IGD has stopped or not
    igd_running=`ps | grep -c IGD`
    if [ $igd_running -gt 1 ];
    then
        echo_t "IGD is not stopped, So shutting it down."
        killall -s SIGTERM IGD
    fi

    sleep 1
    
    #wait until IHC completed
    if [ "$IHC_Enable" = "Monitor" ]
    then
        iter=0
        while [ $iter -le 8 ]
        do
            if [ -f /tmp/IHC_completed ]
            then
                echo_t "IHC execution completed ....."
                rm -rf /tmp/IHC_completed
                break;
            fi
            echo_t "waiting for IHC execution to be completed ....."
            sleep 1
            iter=$((iter+1))
        done
    fi

    rebootFunc
fi

