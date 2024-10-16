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
boot_up_log_synced="false"

#source /etc/utopia/service.d/log_env_var.sh
#source /etc/utopia/service.d/log_capture_path.sh
source /lib/rdk/utils.sh
source $RDK_LOGGER_PATH/logfiles.sh
source /lib/rdk/t2Shared_api.sh
source $RDK_LOGGER_PATH/logUpload_default_params.sh
if [ -f /nvram/logupload.properties -a $BUILD_TYPE != "prod" ];then
    . /nvram/logupload.properties
fi
# We will keep max line size as 2 so that we will not lose any log message


#---------------------------------
# Initialize Variables
#---------------------------------
# As per ARRISXB3-3149


# File to save curl response 
FILENAME="$PERSISTENT_PATH/DCMresponse.txt"
# File to save http code
HTTP_CODE="$PERSISTENT_PATH/http_code"
rm -rf $HTTP_CODE
# Timeout value
timeout=10
# http header
HTTP_HEADERS='Content-Type: application/json'

## RETRY DELAY in secs
RETRY_DELAY=60
## RETRY COUNT
RETRY_COUNT=3
#default_IP=$DEFAULT_IP
upload_protocol='HTTP'
upload_httplink='None'

LOGBACKUP_ENABLE='false'
LOGBACKUP_INTERVAL=30

loop=1

minute_count=0
#tmp disable the flag now 
#UPLOAD_ON_REBOOT="/nvram/uploadonreboot"

#For rdkb-4260
SW_UPGRADE_REBOOT="/nvram/reboot_due_to_sw_upgrade"

#echo "Build Type is: $BUILD_TYPE"
#echo "SERVER is: $SERVER"
DeviceUP=0
# ARRISXB3-2544 :
# Check if upload on reboot flag is ON. If "yes", then we will upload the 
# log files first before starting monitoring of logs.

#---------------------------------
# Function declarations
#---------------------------------

## FW version from version.txt 
getFWVersion()
{
    sed -n 's/^imagename[:=]"\?\([^"]*\)"\?/\1/p' /version.txt
}

## Identifies whether it is a VBN or PROD build
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

random_sleep()
{

	   randomizedNumber=`awk -v min=0 -v max=30 -v seed="$(date +%N)" 'BEGIN{srand(seed);print int(min+rand()*(max-min+1))}'`
	   RANDOM_SLEEP=`expr $randomizedNumber \\* 60`
	   echo_t "Random sleep for $RANDOM_SLEEP"
	   sleep $RANDOM_SLEEP
}

## Process the responce and update it in a file DCMSettings.conf
processJsonResponse()
{   
    if [ -f "$FILENAME" ]
    then
        OUTFILE='/tmp/DCMSettings.conf'
        sed -i 's/,"urn:/\n"urn:/g' $FILENAME # Updating the file by replacing all ',"urn:' with '\n"urn:'
        sed -i 's/{//g' $FILENAME    # Deleting all '{' from the file 
        sed -i 's/}//g' $FILENAME    # Deleting all '}' from the file
        echo "" >> $FILENAME         # Adding a new line to the file 

        #rm -f $OUTFILE #delete old file
        cat /dev/null > $OUTFILE #empty old file

        while read line
        do  
            
            # Parse the settings  by
            # 1) Replace the '":' with '='
            # 2) Delete all '"' from the value 
            # 3) Updating the result in a output file
            echo "$line" | sed 's/":/=/g' | sed 's/"//g' >> $OUTFILE 
            #echo "$line" | sed 's/":/=/g' | sed 's/"//g' | sed 's,\\/,/,g' >> $OUTFILE
            sleep 1
        done < $FILENAME
        
        rm -rf $FILENAME #Delete the /opt/DCMresponse.txt
    else
        echo "$FILENAME not found." >> $LOG_PATH/dcmscript.log
        return 1
    fi
}

totalSize=0
getLogfileSize()
{
	# Argument may be a file or a directory
	totalSize=$(du -c $1 | tail -n1 | awk '{print $1}')
}

getTFTPServer()
{
        if [ "$1" != "" ]
        then
        logserver=`grep $1 $RDK_LOGGER_PATH/dcmlogservers.txt | cut -f2 -d"|"`
		echo $logserver
	fi
}

getLineSizeandRotate()
{
 	curDir=`pwd`
	cd $LOG_PATH

	FILES=`ls`
	tempSize=0
	totalLines=0

	for f in $FILES
	do
        	totalLines=`wc -l $f | cut -f1 -d" "`

		if [ "$totalLines" -ge "$MAXLINESIZE" ]
		then
        		rotateLogs $f
			totalLines=0
		fi
	done
	cd $curDir
}

reset_offset()
{
	# Suppress ls errors to prevent constant prints in non supported devices
	file_list=`ls 2>/dev/null $LOG_SYNC_PATH`

	for file in $file_list
	do
		echo "1" > $LOG_SYNC_PATH$file # Setting Offset as 1 and clearing the file
	done

}

BUILD_TYPE=`getBuildType`
SERVER=`getTFTPServer $BUILD_TYPE`

get_logbackup_cfg()
{
	if [ "$NVRAM2_SUPPORTED" = "yes" ]
	then
		backupenable=$(syscfg get logbackup_enable)

		if [ "$backupenable" = "true" ] || [ -n "$(echo $backupenable | grep -i 'error')" ]
		then
			LOGBACKUP_ENABLE="true"
			LOGBACKUP_INTERVAL=$(syscfg get logbackup_interval)
		else
			LOGBACKUP_ENABLE="false"
		fi
	fi
}

upload_nvram2_logs()
{
	curDir=`pwd`

	cd $LOG_SYNC_BACK_UP_PATH

	UploadFile=`ls | grep "tgz"`
	if [ "$UploadFile" != "" ]
	then
	   echo_t "File to be uploaded from is $UploadFile "
		if [ "$UPLOADED_AFTER_REBOOT" == "true" ]
		then
			$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false"
		else
			while [ "$loop" = "1" ]
			do
		    	echo_t "Waiting for stack to come up completely to upload logs..."
			     t2CountNotify "SYS_INFO_WaitingFor_Stack_Init"
		      	     sleep 30
			     WEBSERVER_STARTED=`sysevent get webserver`
		 	     if [ "$WEBSERVER_STARTED" == "started" ]
			     then
				echo_t "Webserver $WEBSERVER_STARTED..., uploading logs after 2 mins"
				break
			    fi
			done
			sleep 120
			random_sleep
			$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false"
			UPLOADED_AFTER_REBOOT="true"
		fi
	fi

	cd $curDir

	echo_t "uploading over from nvram2 "
}

bootup_remove_old_backupfiles()
{
	if [ "$LOGBACKUP_ENABLE" == "true" ]; then
		#Check whether $LOG_BACK_UP_REBOOT directory present or not
		if [ -d "$LOG_BACK_UP_REBOOT" ]; then
			cd $LOG_BACK_UP_REBOOT
			filesPresent=`ls $LOG_BACK_UP_REBOOT | grep -v tgz`
			
			#To remove not deleted old nvram/logbackupreboot/ files  
			if [ "$filesPresent" != "" ]
			then
				echo "Removing old files from $LOG_BACK_UP_REBOOT path during reboot..."
				rm -rf $LOG_BACK_UP_REBOOT*.log*
				rm -rf $LOG_BACK_UP_REBOOT*.txt*
				rm -rf $LOG_BACK_UP_REBOOT*core*
				rm -rf $LOG_BACK_UP_REBOOT*.bin*

				if [ "$BOX_TYPE" == "HUB4" ] || [ "$BOX_TYPE" == "SR300" ] || [ "x$BOX_TYPE" == "xSR213" ] || [ "$BOX_TYPE" == "SE501" ] || [ "$BOX_TYPE" == "WNXL11BWL" ]; then
					rm -rf $LOG_BACK_UP_REBOOT*tar.gz*
				fi
			fi 
			
			cd -
		fi
	fi
}

bootup_tarlogs()
{
	#dt may be epoc time at the time of sourceing.So defining again here.
	dt=`date "+%m-%d-%y-%I-%M%p"`
	echo_t "RDK_LOGGER: bootup_tarlogs"

	#Remove old backup log files	
	bootup_remove_old_backupfiles

	if [ -e "$UPLOAD_ON_REBOOT" ]
	then
	        curDir=`pwd`

		if [ "$LOGBACKUP_ENABLE" == "true" ]; then
		    if [ ! -d $LOG_SYNC_BACK_UP_REBOOT_PATH ]
		    then
		        mkdir $LOG_SYNC_BACK_UP_REBOOT_PATH
		    fi
			cd $LOG_SYNC_BACK_UP_REBOOT_PATH
                        filesPresent=`ls $LOG_SYNC_BACK_UP_REBOOT_PATH | grep -v tgz`
		else
	   		cd $LOG_BACK_UP_REBOOT
                        filesPresent=`ls $LOG_BACK_UP_REBOOT | grep -v tgz`
		fi
		UploadFile=`ls $LOG_SYNC_BACK_UP_REBOOT_PATH | grep "tgz"`
		if [ "$UploadFile" != "" ]
		then
			if [ "$BOX_TYPE" = "XB3" ]
			then
				echo_t "RDK_LOGGER: moving the tar file to tmp for xb3 "
				if [ ! -d "$TMP_UPLOAD" ]; then
				 mkdir -p $TMP_UPLOAD
				fi
				mv $LOG_SYNC_BACK_UP_REBOOT_PATH/$UploadFile  $TMP_UPLOAD
			else
				echo_t "RDK_LOGGER: bootup_tarlogs moving tar $UploadFile to preserve path for non xb3"
				if [ ! -d $PRESERVE_LOG_PATH ] ; then
					mkdir -p $PRESERVE_LOG_PATH
				fi
				preserveThisLog $UploadFile $LOG_SYNC_BACK_UP_REBOOT_PATH
			fi
		fi
            if [ "$filesPresent" != "" ]
            then

               
               if [ ! -d "$TMP_UPLOAD" ]; then
               mkdir -p $TMP_UPLOAD
               fi
               # Print sys descriptor value if bootup is not after software upgrade.
               # During software upgrade, we print this value before reboot.
               # This is done to reduce user triggered reboot time 
               if [ ! -f "/nvram/reboot_due_to_sw_upgrade" ]
               then
                   echo "Create sysdescriptor before creating tar ball after reboot.."
                   createSysDescr >> $ARM_LOGS_NVRAM2
               fi 

               if [ "$BOX_TYPE" = "XB3" ]
               then
                    cd $TMP_UPLOAD
                    CopyToTmp
                    TarCreatePath=$TMP_UPLOAD
                    echo_t "Create tar in $TarCreatePath for xb3"
               else
                    TarCreatePath=$LOG_SYNC_PATH
                    echo_t "Create tar of $LOG_SYNC_PATH in $TarCreatePath  for non-xb3 "
                    cd $TarCreatePath
               fi

               echo "*.tgz" > $PATTERN_FILE # .tgz should be excluded while tar
               if [ -f /tmp/backup_onboardlogs ] && [ -f /nvram/.device_onboarded ]; then
                echo "tar activation logs from bootup_tarlogs"
                copy_onboardlogs "$TarCreatePath"
                tar -X $PATTERN_FILE -cvzf ${MAC}_Logs_${dt}_activation_log.tgz $TarCreatePath
                rm -rf /tmp/backup_onboardlogs
               else
                echo "tar logs from bootup_tarlogs"
                tar -X $PATTERN_FILE -cvzf ${MAC}_Logs_${dt}.tgz $TarCreatePath
               fi
               echo "Copy logs $LOG_SYNC_PATH/$SelfHealBootUpLogFile & $LOG_SYNC_PATH$PcdLogFile to $LOG_PATH for telemetry processing"
               cp $TarCreatePath/$SelfHealBootUpLogFile $LOG_PATH
               cp $TarCreatePath$PcdLogFile $LOG_PATH
               rm $PATTERN_FILE
               rm -rf $TarCreatePath*.txt*
	       rm -rf $TarCreatePath*.log*
	       rm -rf $TarCreatePath*core*
	       rm -rf $TarCreatePath*.bin*
	       if [ "$BOX_TYPE" == "HUB4" ] || [ "$BOX_TYPE" == "SR300" ] || [ "x$BOX_TYPE" == "xSR213" ] || [ "$BOX_TYPE" == "SE501" ] || [ "$BOX_TYPE" == "WNXL11BWL" ]; then
		rm -rf $TarCreatePath*tar.gz*
	       fi
	       rm -rf $TarCreatePath$PcdLogFile
	       rm -rf $TarCreatePath$RAM_OOPS_FILE
	       echo_t "RDK_LOGGER: tar activation logs from bootup_tarlogs ${MAC}_Logs_${dt}.tgz"
           if [ "$BOX_TYPE" = "XB3" ]
           then
               echo_t "RDK_LOGGER: keeping the tar file in $TarCreatePath for xb3 "
            else
               UploadFile=`ls $TarCreatePath | grep "tgz"`
               if [ "$UploadFile" != "" ]
                then
                    logThreshold=`syscfg get log_backup_threshold`
                    logBackupEnable=`syscfg get log_backup_enable`
                    if [ "$logBackupEnable" = "true" ] && [ "$logThreshold" -gt "0" ]; then
                        echo_t "RDK_LOGGER: Moving file  $TarCreatePath/$UploadFile to preserve folder for non-xb3 "
                        if [ ! -d $PRESERVE_LOG_PATH ] ; then
                            mkdir -p $PRESERVE_LOG_PATH
                        fi
                        preserveThisLog $UploadFile $TarCreatePath
                    else
                        echo_t "RDK_LOGGER: Keeping the tar in $TarCreatePath for non-xb3".
                    fi
                fi
            fi
        fi
	fi
}	

bootup_upload()
{

	echo_t "RDK_LOGGER: bootup_upload"

	if [ -e "$UPLOAD_ON_REBOOT" ]
	then

            if [ "$LOGBACKUP_ENABLE" == "true" ]; then
               #Sync log files immediately after reboot
               echo_t "RDK_LOGGER: Sync logs to nvram2 after reboot"
               syncLogs_nvram2
               cd $TMP_UPLOAD
            else
               BACKUPENABLE=`syscfg get logbackup_enable`
               if [ "$BACKUPENABLE" = "true" ]; then
                  # First time call syncLogs after boot,
                  #  remove existing log files (in $LOG_FILES_NAMES) in $LOG_BACK_UP_REBOOT
                  curDir=`pwd`
                  cd $LOG_BACK_UP_REBOOT
                  for fileName in $LOG_FILES_NAMES
                  do
                     rm 2>/dev/null $fileName #avoid error message
                  done
                  cd $curDir
                  syncLogs
               fi
            fi

	   macOnly=`getMacAddressOnly`
	   fileToUpload=`ls | grep tgz`
	   # This check is to handle migration scenario from /nvram to /nvram2
	   if [ "$fileToUpload" = "" ] && [ "$LOGBACKUP_ENABLE" = "true" ]
	   then
	       echo_t "Checking if any file available in $LOG_BACK_UP_REBOOT"
               if [ -d $LOG_BACK_UP_REBOOT ]; then
	          fileToUpload=`ls $LOG_BACK_UP_REBOOT | grep tgz`
               fi
	   fi
	       
	   echo_t "File to be uploaded is $fileToUpload ...."

	   HAS_WAN_IP=""
	   
	   while [ "$loop" = "1" ]
	   do
	      echo_t "Waiting for stack to come up completely to upload logs..."
	      t2CountNotify "SYS_INFO_WaitingFor_Stack_Init"
	      sleep 30
	      WEBSERVER_STARTED=`sysevent get webserver`
	      if [ "$WEBSERVER_STARTED" == "started" ]
	      then
		   echo_t "Webserver $WEBSERVER_STARTED..., uploading logs after 2 mins"
		   break
	      fi

		bootup_time_sec=$(cut -d. -f1 /proc/uptime)
		if [ "$bootup_time_sec" -ge "600" ] ; then
			echo_t "Boot time is more than 10 min, Breaking Loop"
			break
		fi
	   done
	   sleep 120

	   if [ "$fileToUpload" = "" ] && [ "$LOGBACKUP_ENABLE" = "true" ]
	   then
	       echo_t "Checking if any file available in $TMP_LOG_UPLOAD_PATH"
	       if [ -d $TMP_LOG_UPLOAD_PATH ]; then
	          fileToUpload=`ls $TMP_LOG_UPLOAD_PATH | grep tgz`
               fi
	   fi

	   if [ "$fileToUpload" = "" ] && [ "$LOGBACKUP_ENABLE" = "true" ]
	   then
	       echo_t "Checking if any file available in $TMP_UPLOAD"
	       if [ -d $TMP_UPLOAD ]; then
	          fileToUpload=`ls $TMP_UPLOAD | grep tgz`
           fi
	   fi

	   echo_t "File to be uploaded is $fileToUpload ...."
	   #RDKB-7196: Randomize log upload within 30 minutes
	   # We will not remove 2 minute sleep above as removing that may again result in synchronization issues with xconf
		boot_up_log_synced="true"
	   if [ "$fileToUpload" != "" ]
	   then
	   	
            random_sleep
	      $RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "true" "" $TMP_LOG_UPLOAD_PATH "true"
	   else 
	      echo_t "No log file found in logbackupreboot folder"
	   fi
	   
        #Venu
	logBackupEnable=`syscfg get log_backup_enable` 
        if [ "$logBackupEnable" = "true" ];then
          if [ -d $PRESERVE_LOG_PATH ] ; then
            cd $PRESERVE_LOG_PATH
            fileToUpload=`ls | grep tgz`
            if [ "$fileToUpload" != "" ]
            then
              sleep 60
              echo_t "Uploading backup logs found in $PRESERVE_LOG_PATH"
              $RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "true" "" $PRESERVE_LOG_PATH "true"
            else 
             echo_t "No backup logs found in $PRESERVE_LOG_PATH"
            fi
          fi #end if [ -d $PRESERVE_LOG_PATH 
        fi #end if [ "$logBackupEnable" = "true" ]
        
	   UPLOADED_AFTER_REBOOT="true"
	   sleep 2
	   rm $UPLOAD_ON_REBOOT
	   cd $curDir
	fi

	echo_t "Check if any tar file available in /logbackup/ "
	curDir=`pwd`

        if [ "$LOGBACKUP_ENABLE" == "true" ]; then
            cd $TMP_UPLOAD
        else
            cd $LOG_BACK_UP_PATH
        fi

	UploadFile=`ls | grep "tgz"`

	if [ "$UploadFile" = "" ] && [ "$LOGBACKUP_ENABLE" = "true" ]
	then
		echo_t "Checking if any file available in $TMP_LOG_UPLOAD_PATH"
                 if [ -d $TMP_LOG_UPLOAD_PATH ]; then
		    UploadFile=`ls $TMP_LOG_UPLOAD_PATH | grep tgz`
                 fi
	fi
    if [ "$UploadFile" = "" ] && [ "$LOGBACKUP_ENABLE" = "true" ]
	then
	    echo_t "Checking if any file available in $LOG_SYNC_BACK_UP_REBOOT_PATH"
        if [ -d $LOG_SYNC_BACK_UP_REBOOT_PATH ]; then
            UploadFile=`ls $LOG_SYNC_BACK_UP_REBOOT_PATH | grep tgz`
        fi
	fi
	
        files_exist_in_preserve="false"
	if [ "$UploadFile" = "" ] && [ "$LOGBACKUP_ENABLE" = "true" ]
	then
		echo_t "Checking if any file available in $PRESERVE_LOG_PATH"
        	if [ -d $PRESERVE_LOG_PATH ]; then
			UploadFile=`ls $PRESERVE_LOG_PATH | grep tgz`
                        if [ "$UploadFile" != "" ]
            		then
            			files_exist_in_preserve="true"
                        fi
        	fi
	fi

	echo_t "File to be uploaded is $UploadFile ...."

	if [ "$UploadFile" != "" ]
	then	
	        echo_t "File to be uploaded from logbackup/ is $UploadFile "
		if [ "$UPLOADED_AFTER_REBOOT" == "true" ]
		then
			random_sleep		
			$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false" "" $TMP_LOG_UPLOAD_PATH "true"
		else
			while [ "$loop" = "1" ]
			do
		    	     echo_t "Waiting for stack to come up completely to upload logs..."
			     t2CountNotify "SYS_INFO_WaitingFor_Stack_Init"
		      	     sleep 30
			     WEBSERVER_STARTED=`sysevent get webserver`
		 	     if [ "$WEBSERVER_STARTED" == "started" ]
			     then
				echo_t "Webserver $WEBSERVER_STARTED..., uploading logs after 2 mins"
				break
			     fi

                             bootup_time_sec=$(cut -d. -f1 /proc/uptime)
                             if [ "$bootup_time_sec" -ge "600" ] ; then
                                  echo_t "Boot time is more than 10 min, Breaking Loop"
                                  break
                             fi
			done
			sleep 120

			if [ "$files_exist_in_preserve" == "true" ]
			then
				random_sleep
				echo_t "Uploading backup logs found in $PRESERVE_LOG_PATH"
				$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "true" "" $PRESERVE_LOG_PATH "true"
			else
				random_sleep
				$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false" "" $TMP_LOG_UPLOAD_PATH "true"
                        fi
                        UPLOADED_AFTER_REBOOT="true"
		fi
	fi

	cd $curDir
}	

#ARRISXB6-5184 : Remove hidden files coming up in /rdklogs/logs and /nvram/logs
remove_hidden_files()
{
    if [ -d "$1" ] ; then
        cd $1
        HIDDEN_FILES=`ls -A | grep "^\." | xargs echo -n`
        if [ "$HIDDEN_FILES" != "" ] ; then
            echo "Removing following hidden files in `pwd` : $HIDDEN_FILES"
            rm -f $HIDDEN_FILES
        fi
        cd - >/dev/null
    fi
}


#---------------------------------
#        Main App
#---------------------------------
# "remove_old_logbackup" if to remove old logbackup from logbackupreboot directory
triggerType=$1
echo_t "rdkbLogMonitor: Trigger type is $triggerType"

get_logbackup_cfg

if [ "$triggerType" == "remove_old_logbackup" ]; then	
	echo "Remove old log backup files"
	bootup_remove_old_backupfiles
	exit
fi

########################################################
#               RDKB-26588 && TRDKB-355 - Mitigation   #
#         To Ensure only one instance is running       #
########################################################
RDKLOG_LOCK_DIR="/tmp/locking_logmonitor"

if mkdir $RDKLOG_LOCK_DIR
then
    echo "Got the first instance running"
else
    echo "Already a instance is running; No 2nd instance"
    exit
fi
########################################################

PEER_COMM_ID="/tmp/elxrretyt-logm.swr"

RebootReason=`syscfg get X_RDKCENTRAL-COM_LastRebootReason`

if [ "$BOX_TYPE" = "XB3" ]; then
        if [ "$RebootReason" = "RESET_ORIGIN_ATOM_WATCHDOG" ] || [ "$RebootReason" = "RESET_ORIGIN_ATOM" ]; then
               if [ ! -f $PEER_COMM_ID ]; then
	              GetConfigFile $PEER_COMM_ID
               fi
	       scp -i $PEER_COMM_ID -r root@$ATOM_INTERFACE_IP:$RAM_OOPS_FILE_LOCATION$RAM_OOPS_FILE  $LOG_SYNC_PATH > /dev/null 2>&1
	fi
        if [ "$RebootReason" = "HOST-OOPS-REBOOT" ]; then
	       cp $RAM_OOPS_FILE_LOCATION$RAM_OOPS_FILE0  $LOG_SYNC_PATH$RAM_OOPS_FILE0_HOST
	       cp $RAM_OOPS_FILE_LOCATION$RAM_OOPS_FILE1  $LOG_SYNC_PATH$RAM_OOPS_FILE1_HOST
        fi
fi

if [ "$LOGBACKUP_ENABLE" == "true" ]; then		

	#ARRISXB6-3045 - This is speific to Axb6. If nvram2 supported hardware found, all syncing should switch to nvram2/logs.
	#While switching from nvram to nvram2, old logs should be backed-up, uploaded and cleared from old sync path.
#	model=`cat /etc/device.properties | grep MODEL_NUM  | cut -f2 -d=`
	if [ "$BOX_TYPE" = "XB6" -a "$MANUFACTURE" = "Arris" ];then
		isNvram2Mounted=`grep nvram2 /proc/mounts`
		if [ -d "/nvram2" ];then
			if [ "$isNvram2Mounted" != "" ];then
				if [ -d "/nvram/logs" ];then
					file_list=`ls /nvram/logs/`
					if [ "$file_list" != "" ]; then
						echo_t "nvram/logs contains older logs"
						if [ ! -d "$LOG_SYNC_PATH" ];then
							echo_t "Creating new sync path - nvram2/logs"
							mkdir $LOG_SYNC_PATH
						fi
						echo_t "nvram2 detected first time. Copying nvram/logs to nvram2/logs for boottime logupload"
						cp /nvram/logs/* "$LOG_SYNC_PATH"
					fi
					echo_t "logs copied to nvram2. Removing old log path - nvram/logs"
					rm -rf "/nvram/logs"
				fi
			else
			echo_t "nvram2 available, but not mounted."
			fi
		fi
	fi

	PCIE_REBOOT_INDICATOR="/nvram/pcie_error_reboot_occurred"
	PCIE_REBOOT_LOG="/rdklogs/logs/pcie_reboot.txt"

	if [ -f $PCIE_REBOOT_INDICATOR ]
	then
		echo "Previous Reboot reason:PCIE ENUM failed" > $PCIE_REBOOT_LOG
		cat "$PCIE_REBOOT_INDICATOR" >> $PCIE_REBOOT_LOG
		rm $PCIE_REBOOT_INDICATOR
		if [ -f /nvram/pcie_error_reboot_needed ];then
			rm /nvram/pcie_error_reboot_needed
		fi
        if [ -f /nvram/pcie_error_reboot_counter ];then
            rm /nvram/pcie_error_reboot_counter
        fi
	fi
	
	#ARRISXB6-2821:
        #DOCSIS_TIME_SYNC_NEEDED=yes for devices where DOCSIS and RDKB are in different processors 
        #and time sync needed before logbackup.
        #Checking TimeSync-status before doing backupnvram2logs_on_reboot to ensure uploaded tgz file 
        #having correct timestamp.
        #Will use default time if time not synchronized even after 2 mini of bootup to unblock 
        #other rdkbLogMonitor.sh functionality

	#TCCBR-4723 To handle all log upload with epoc time cases. Brought this block of code just 
	#above to the prevoius condition for making all cases to wait for timesync before log upload.
	
	if [ "`sysevent get wan-status`" != "started" ] || [ "x`sysevent get ntp_time_sync`" != "x1" ];then
		loop=1
		retry=1
		while [ "$loop" = "1" ]
		do
			echo_t "Waiting for time synchronization between processors before logbackup"
			WAN_STATUS=`sysevent get wan-status`
			NTPD_STATUS=`sysevent get ntp_time_sync`
			if [ "$WAN_STATUS" == "started" ] && [ "x$NTPD_STATUS" == "x1" ]
			then
				echo_t "wan status is $WAN_STATUS, and time sync status $NTPD_STATUS"
				echo_t "Time is synced, breaking the loop"
				break
			elif [ "$retry" -gt "9" ]
			then
					echo_t "wan status is $WAN_STATUS, and time sync status $NTPD_STATUS"
					echo_t "Time is not synced after 3 min retry. Breaking loop and using default time for logbackup"
					break
			else
					echo_t "Time is not synced. Sleeping.. Retry:$retry"
					retry=`expr $retry + 1`
					sleep 20
			fi
		done
	fi
    
    echo_t "RDK_LOGGER: creating $TMP_UPLOAD"
    if [ ! -d "$TMP_UPLOAD" ]; then
        mkdir -p $TMP_UPLOAD
    fi
    file_list=`ls $LOG_SYNC_PATH | grep -v tgz`
	#TCCBR-4275 to handle factory reset case.
	if ( [ "$file_list" != "" ] && [ ! -f "$UPLOAD_ON_REBOOT" ] ) || ( [ "$RebootReason" == "factory-reset" ] ); then
	 	echo_t "RDK_LOGGER: creating tar from nvram2 on reboot"

		#HUB4 uses NTP for syncing time. It doesnt have DOCSIS time sync, Hence waiting for NTP time sync.
		if [ "$BOX_TYPE" == "HUB4" ] || [ "$BOX_TYPE" == "SR300" ] || [ "x$BOX_TYPE" == "xSR213" ] || [ "$BOX_TYPE" == "SE501" ] || [ "$BOX_TYPE" == "WNXL11BWL" ]; then
			loop=1
			retry=1
			while [ "$loop" = "1" ]
			do
				echo_t "Waiting for time synchronization before logbackup"
				TIME_SYNC_STATUS=`timedatectl status | grep "NTP synchronized" | cut -d " " -f 3`
				if [ "$TIME_SYNC_STATUS" == "yes" ]
				then
					echo_t "Time synced. Breaking loop"
					break
				elif [ "$retry" = "12" ]
				then
					echo_t "Time not synced even after 2 min retry. Breaking loop and using default time for logbackup"
					break
				else
					echo_t "Time not synced yet. Sleeping.. Retry:$retry"
					retry=`expr $retry + 1`
					sleep 10
				fi
			done
		fi
		backupnvram2logs_on_reboot
		#upload_nvram2_logs

                if [ "$LOGBACKUP_ENABLE" == "true" ]; then
                   #Sync log files immediately after reboot
                   echo_t "RDK_LOGGER: Sync logs to nvram2 after reboot"
                   syncLogs_nvram2
                else
                   BACKUPENABLE=`syscfg get logbackup_enable`
                   if [ "$BACKUPENABLE" = "true" ]; then
                       # First time call syncLogs after boot,
                       #  remove existing log files (in $LOG_FILES_NAMES) in $LOG_BACK_UP_REBOOT
                       curDir=`pwd`
                       cd $LOG_BACK_UP_REBOOT
                       for fileName in $LOG_FILES_NAMES
                       do
                          rm 2>/dev/null $fileName #avoid error message
                       done
                       cd $curDir
                       syncLogs
                   fi
                fi
	elif [ "$file_list" == "" ] && [ ! -f "$UPLOAD_ON_REBOOT" ]; then
		if [ "$LOGBACKUP_ENABLE" == "true" ]; then
			#Sync log files immediately after reboot
			echo_t "RDK_LOGGER: Sync logs to nvram2 after reboot"
			syncLogs_nvram2
		fi
	fi
fi

# rdkb-24823 create tar file, then do upload in the background,
bootup_tarlogs
bootup_upload &

UPLOAD_LOGS=`processDCMResponse`
while [ "$loop" = "1" ]
do
	    if [ "$DeviceUP" = "0" ]; then
	        #for rdkb-4260
		t2CountNotify "SYS_INFO_bootup"
	        if [ -f "$SW_UPGRADE_REBOOT" ]; then
	           echo_t "RDKB_REBOOT: Device is up after reboot due to software upgrade"
		   t2CountNotify "SYS_INFO_SW_upgrade_reboot"
	           #deleting reboot_due_to_sw_upgrade file
	           echo_t "Deleting file /nvram/reboot_due_to_sw_upgrade"
	           rm -rf /nvram/reboot_due_to_sw_upgrade
	           DeviceUP=1
	        else
	           echo_t "RDKB_REBOOT: Device is up after reboot"
	           DeviceUP=1
	        fi
	    fi

	    sleep 60
	    if [ ! -e $REGULAR_UPLOAD ]
	    then
		getLogfileSize "$LOG_PATH"

	        if [ "$totalSize" -ge "$MAXSIZE" ]; then
                        echo_t "Log size max reached"
			get_logbackup_cfg

			if [ "$UPLOAD_LOGS" = "" ] || [ ! -f "$DCM_SETTINGS_PARSED" ]
			then
				echo_t "processDCMResponse to get the logUploadSettings"
				UPLOAD_LOGS=`processDCMResponse`
			fi  
    
			echo_t "UPLOAD_LOGS val is $UPLOAD_LOGS"
			if [ "$UPLOAD_LOGS" = "true" ] || [ "$UPLOAD_LOGS" = "" ]
			then
				UPLOAD_LOGS="true"
				# this file is touched to indicate log upload is enabled
				# we check this file in logfiles.sh before creating tar ball.
				# tar ball will be created only if this file exists.
				echo_t "Log upload is enabled. Touching indicator in regular upload"         
				touch /tmp/.uploadregularlogs
			else
				echo_t "Log upload is disabled. Removing indicator in regular upload"         
				rm -rf /tmp/.uploadregularlogs                                
			fi
			
			cd $TMP_UPLOAD
			FILE_NAME=`ls | grep "tgz"`
			# This event is set to "yes" whenever wan goes down. 
			# So, we should not move tar to /tmp in that case.
			wan_event=`sysevent get wan_event_log_upload`
			wan_status=`sysevent get wan-status`
			if [ "$FILE_NAME" != "" ] && [ "$boot_up_log_synced" = "false" ]; then
				mkdir $TMP_LOG_UPLOAD_PATH
				mv $FILE_NAME $TMP_LOG_UPLOAD_PATH
			fi
			cd -
			boot_up_log_synced="true"
			if [ "$LOGBACKUP_ENABLE" == "true" ]; then	
				createSysDescr
				syncLogs_nvram2

                                # Check if there is any tar ball to be preserved
                                # else tar ball will be removed in backupnvram2logs
                                logBackupEnable=`syscfg get log_backup_enable`
                                if [ "$logBackupEnable" = "true" ];then
                                   echo_t "Back up to preserve location is enabled"
                                   fileName=`ls -tr $TMP_UPLOAD | grep tgz | head -n 1`
                                   if [ "$fileName" != "" ]
                                   then
                                      # Call PreserveLog which will move logs to preserve location
                                      preserveThisLog $fileName $TMP_UPLOAD
                                   fi
                                fi 	

				backupnvram2logs "$TMP_UPLOAD"
			else
				syncLogs
				backupAllLogs "$LOG_PATH" "$LOG_BACK_UP_PATH" "cp"
			fi
		        if [ "$UPLOAD_LOGS" = "true" ]
			then
				$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false"
                                http_ret=$?
                                echo_t "Logupload http_ret value = $http_ret"
                                if [ "$http_ret" = "200" ] || [ "$http_ret" = "302" ] ;then
                                      logBackupEnable=`syscfg get log_backup_enable`

                                      if [ "$logBackupEnable" = "true" ] ; then
                                            if [ -d $PRESERVE_LOG_PATH ] ; then
                                                 cd $PRESERVE_LOG_PATH
                                                 fileToUpload=`ls | grep tgz`
                                                 if [ "$fileToUpload" != "" ] ;then
                                                     file_list=$fileToUpload
                                                     echo_t "Direct comm. available preserve logs = $fileToUpload"
                                                     $RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "true" "" $PRESERVE_LOG_PATH
                                                 else
                                                        echo_t "Direct comm. No preserve logs found in $PRESERVE_LOG_PATH"
                                                 fi
                                             fi
                                       fi
                                else
                                      echo_t "Preserve Logupload not success because of http val $http_ret"
                                fi

			else
				echo_t "Regular log upload is disabled"
			fi
	    	fi
	    fi
	    
	# Syncing logs after particular interval
	get_logbackup_cfg
	if [ "$LOGBACKUP_ENABLE" == "true" ]; then # nvram2 supported and backup is true
		minute_count=$((minute_count + 1))
		bootup_time_sec=$(cut -d. -f1 /proc/uptime)
		if [ "$bootup_time_sec" -le "2400" ] && [ $minute_count -eq 10 ]; then
			minute_count=0
			echo_t "RDK_LOGGER: Syncing every 10 minutes for initial 30 minutes"
			syncLogs_nvram2
		elif [ "$minute_count" -ge "$LOGBACKUP_INTERVAL" ]; then
			minute_count=0
			syncLogs_nvram2
			if [ "$ATOM_SYNC" == "" ]; then
			   syncLogs
			fi
			#ARRISXB6-5184
			if [ "$BOX_TYPE" = "XB6" -a "$MANUFACTURE" = "Arris" ] ; then
			    remove_hidden_files "/rdklogs/logs"
			    remove_hidden_files "/nvram/logs"
			    remove_hidden_files "/nvram2/logs"
			fi
		fi
	else
		# Suppress ls errors to prevent constant prints in non supported devices
		file_list=`ls 2>/dev/null $LOG_SYNC_PATH`
		if [ "$file_list" != "" ]; then
			echo_t "RDK_LOGGER: Disabling nvram2 logging"
			createSysDescr
                        
			if [ "$UPLOAD_LOGS" = "" ] || [ ! -f "$DCM_SETTINGS_PARSED" ]
			then
				echo_t "processDCMResponse to get the logUploadSettings"
				UPLOAD_LOGS=`processDCMResponse`
			fi  
    
			echo_t "UPLOAD_LOGS val is $UPLOAD_LOGS"
			if [ "$UPLOAD_LOGS" = "true" ] || [ "$UPLOAD_LOGS" = "" ]		
			then
				UPLOAD_LOGS="true"
				echo_t "Log upload is enabled. Touching indicator in maintenance window"         
				touch /tmp/.uploadregularlogs
			else
				echo_t "Log upload is disabled. Removing indicator in maintenance window"         
				rm /tmp/.uploadregularlogs
			fi

			syncLogs_nvram2
			if [ "$ATOM_SYNC" == "" ]; then
				syncLogs
			fi
			backupnvram2logs "$TMP_UPLOAD"

		        if [ "$UPLOAD_LOGS" = "true" ]
			then			
				$RDK_LOGGER_PATH/uploadRDKBLogs.sh $SERVER "HTTP" $URL "false" "true"
			else
				echo_t "Regular log upload is disabled"         
			fi

		fi
	fi
              	
done

########################################################
#               RDKB-26588 && TRDKB-355 - Mitigation   #
#         To Ensure only one instance is running       #
########################################################
rm -rf $RDKLOG_LOCK_DIR
########################################################

