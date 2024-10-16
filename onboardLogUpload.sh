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

# Usage : ./onboardLogUpload.sh "upload" <file_to_upload>
# Arguments:
#	upload - This will trigger an upload of <file_to_upload>
#
#
#

source  /etc/log_timestamp.sh

if [ -f /etc/ONBOARD_LOGGING_ENABLE ]; then
    ONBOARDLOGS_NVRAM_BACKUP_PATH="/nvram2/onboardlogs/"
    ONBOARDLOGS_TMP_BACKUP_PATH="/tmp/onboardlogs/"
fi

source /lib/rdk/t2Shared_api.sh
source /etc/waninfo.sh

ARGS=$1
UploadFile=$2
blog_dir="/nvram2/onboardlogs/"

CURL_BIN="curl"

UseCodeBig=0
conn_str="Direct"
CodebigAvailable=0
encryptionEnable=`dmcli eRT retv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.EncryptCloudUpload.Enable`
URLENCODE_STRING=""

CODEBIG_BLOCK_TIME=1800
CODEBIG_BLOCK_FILENAME="/tmp/.lastcodebigfail_olu"
WAN_INTERFACE=$(getWanInterfaceName)
UploadHttpLink=$3

DIRECT_MAX_ATTEMPTS=3
CODEBIG_MAX_ATTEMPTS=3
#to support ocsp
EnableOCSPStapling="/tmp/.EnableOCSPStapling"
EnableOCSP="/tmp/.EnableOCSPCA"

if [ -f $EnableOCSPStapling ] || [ -f $EnableOCSP ]; then
    CERT_STATUS="--cert-status"
fi

if [ "$UploadHttpLink" == "" ]
then
	UploadHttpLink=$URL
fi

# Get the configuration of codebig settings
get_Codebigconfig()
{
   # If GetServiceUrl not available, then only direct connection available and no fallback mechanism
   if [ -f /usr/bin/GetServiceUrl ]; then
      CodebigAvailable=1
   fi

   if [ "$CodebigAvailable" -eq "1" ]; then
       CodeBigEnable=`dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.CodeBigFirst.Enable | grep true 2>/dev/null`
   fi
   if [ "$CodebigAvailable" -eq "1" ] && [ "x$CodeBigEnable" != "x" ] ; then
      UseCodeBig=1 
      conn_str="Codebig"
   fi

   if [ "$CodebigAvailable" -eq "1" ]; then
      echo_t "Using $conn_str connection as the Primary"
   else
      echo_t "Only $conn_str connection is available"
   fi
}

IsCodebigBlocked()
{
    ret=0
    if [ -f $CODEBIG_BLOCK_FILENAME ]; then
        modtime=$(($(date +%s) - $(date +%s -r $CODEBIG_BLOCK_FILENAME)))
        if [ "$modtime" -le "$CODEBIG_BLOCK_TIME" ]; then
            echo "Last Codebig failed blocking is still valid, preventing Codebig" 
            ret=1
        else
            echo "Last Codebig failed blocking has expired, removing $CODEBIG_BLOCK_FILENAME, allowing Codebig" 
            rm -f $CODEBIG_BLOCK_FILENAME
            ret=0
        fi
    fi
    return $ret
}

# Direct connection Download function
useDirectRequest()
{
    # Direct connection will not be tried if .lastdirectfail exists
    retries=0
    while [ "$retries" -lt "$DIRECT_MAX_ATTEMPTS" ]
    do
        WAN_INTERFACE=$(getWanInterfaceName)
        echo_t "Trying Direct Communication"
        CURL_CMD="$CURL_BIN --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" $URLENCODE_STRING -o \"$OutputFile\" \"$S3_URL\" --interface $WAN_INTERFACE $addr_type $CERT_STATUS --connect-timeout 30 -m 30"

        echo_t "File to be uploaded: $UploadFile"
        UPTIME=`uptime`
        echo_t "System Uptime is $UPTIME"
        echo_t "S3 URL is : $S3_URL"

        echo_t "Trial $retries for DIRECT ..."
        #Sensitive info like Authorization signature should not print
        echo_t "Curl Command built: `echo "$CURL_CMD" | sed -ne 's#AWSAccessKeyId=.*Signature=.*&#<hidden key>#p'`"
        HTTP_CODE=`ret= eval $CURL_CMD`

        if [ "x$HTTP_CODE" != "x" ];
        then
            http_code=$(echo "$HTTP_CODE" | awk '{print $0}' )
            echo_t "Direct communication HttpCode received is : $http_code"

            if [ "$http_code" != "" ];then
                 echo_t "Direct Communication - ret:$ret, http_code:$http_code"
                 if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] ;then
			echo $http_code > $UPLOADRESULT
                        return 0
                 fi
                 echo "failed" > $UPLOADRESULT
            fi
        else
            http_code=0
            echo_t "Direct Communication Failure Attempt:$retries  - ret:$ret, http_code:$http_code"
        fi
        retries=`expr $retries + 1`
        sleep 30
    done
   echo "Retries for Direct connection exceeded " 
    return 1
}

# Codebig connection Download function        
useCodebigRequest()
{
    # Do not try Codebig if CodebigAvailable != 1 (GetServiceUrl not there)
    if [ "$CodebigAvailable" -eq "0" ] ; then
        echo "OpsLog Upload : Only direct connection Available"
        return 1
    fi

    IsCodebigBlocked
    if [ "$?" = "1" ]; then
       return 1
    fi

    if [ "$S3_MD5SUM" != "" ]; then
        uploadfile_md5="&md5=$S3_MD5SUM"
    fi

    retries=0
    while [ "$retries" -lt "$CODEBIG_MAX_ATTEMPTS" ]
    do
         echo_t "Trying Codebig Communication"
         SIGN_CMD="GetServiceUrl 1 \"/cgi-bin/rdkb.cgi?filename=$UploadFile$uploadfile_md5\""
         eval $SIGN_CMD > $SIGN_FILE
         if [ -s $SIGN_FILE ]
         then
             echo "Log upload - GetServiceUrl success"
         else
             echo "Log upload - GetServiceUrl failed"
             exit
         fi
         CB_SIGNED=`cat $SIGN_FILE`
         rm -f $SIGN_FILE
         S3_URL_SIGN=`echo $CB_SIGNED | sed -e "s|?.*||g"`
         echo "serverUrl : $S3_URL_SIGN"
         authorizationHeader=`echo $CB_SIGNED | sed -e "s|&|\", |g" -e "s|=|=\"|g" -e "s|.*filename|filename|g"`
         authorizationHeader="Authorization: OAuth realm=\"\", $authorizationHeader\""
         CURL_CMD="$CURL_BIN --tlsv1.2 -w '%{http_code}\n' -d \"filename=$UploadFile\" $URLENCODE_STRING -o \"$OutputFile\" \"$S3_URL_SIGN\" --interface $WAN_INTERFACE $addr_type -H '$authorizationHeader' $CERT_STATUS --connect-timeout 30 -m 30"
        echo_t "File to be uploaded: $UploadFile"
        UPTIME=`uptime`
        echo_t "System Uptime is $UPTIME"
        echo_t "S3 URL is : $S3_URL_SIGN"

        echo_t "Trial $retries for CODEBIG ..."
        #Sensitive info like Authorization signature should not print
        echo_t "Curl Command built: `echo "$CURL_CMD" | sed -ne 's#'"$authorizationHeader"'#<Hidden authorization-header>#p'` "
        HTTP_CODE=`ret= eval $CURL_CMD `

        if [ "x$HTTP_CODE" != "x" ];
        then
             http_code=$(echo "$HTTP_CODE" | awk '{print $0}' )
             echo_t "Codebig connection HttpCode received is : $http_code"

             if [ "$http_code" != "" ];then
                 echo_t "Codebig Communication - ret:$ret, http_code:$http_code"
                 if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] ;then
			echo $http_code > $UPLOADRESULT
                        return 0
                 fi
                 echo "failed" > $UPLOADRESULT
             fi
        else
             http_code=0
             echo_t "Codebig Communication Failure Attempts:$retries - ret:$ret, http_code:$http_code"
        fi

        if [ "$retries" -lt "$CODEBIG_MAX_ATTEMPTS" ]; then
            if [ "$retries" -eq "0" ]; then
                sleep 10
            else
                sleep 30
            fi
        fi
        retries=`expr $retries + 1`
    done
    echo "Retries for Codebig connection exceeded "
    [ -f $CODEBIG_BLOCK_FILENAME ] || touch $CODEBIG_BLOCK_FILENAME
    return 1
}

uploadOnboardLogs()
{
    curDir=`pwd`
    cd $blog_dir
    # If interface doesnt have ipv6 address then we will force the curl to go with ipv4.
    # Otherwise we will not specify the ip address family in curl options
    addr_type=""
if [ "x$BOX_TYPE" = "xHUB4" ] || [ "x$BOX_TYPE" = "xSR300" ] || [ "x$BOX_TYPE" == "xSR213" ] || [ "x$BOX_TYPE" == "xSE501" ] || [ "x$BOX_TYPE" == "xWNXL11BWL" ]; then
   CURRENT_WAN_IPV6_STATUS=`sysevent get ipv6_connection_state`
   if [ "xup" = "x$CURRENT_WAN_IPV6_STATUS" ] ; then   
           [ "x`ifconfig $HUB4_IPV6_INTERFACE | grep Global |  awk '/inet6/{print $3}' | cut -d '/' -f1 | head -n1`" != "x" ] || addr_type="-4"
   else
           [ "x`ifconfig $WAN_INTERFACE | grep inet6 | grep -i 'Global'`" != "x" ] || addr_type="-4"
   fi
else
    [ "x`ifconfig $WAN_INTERFACE | grep inet6 | grep -i 'Global'`" != "x" ] || addr_type="-4"
fi

    S3_URL=$UploadHttpLink
    S3_MD5SUM=""
    echo "RFC_EncryptCloudUpload_Enable:$encryptionEnable"
    if [ "$encryptionEnable" == "true" ]; then
        S3_MD5SUM="$(openssl md5 -binary < $UploadFile | openssl enc -base64)"
        URLENCODE_STRING="--data-urlencode \"md5=$S3_MD5SUM\""
    fi

    if [ "$UseCodeBig" -eq "1" ]; then
       useCodebigRequest
       ret=$?
    else
       useDirectRequest
       ret=$?
    fi

    if [ "$ret" -ne "0" ]; then
         echo "LOG UPLOAD UNSUCCESSFUL, ret = $ret"
         t2CountNotify "SYS_ERROR_LOGUPLOAD_FAILED"
    fi

    # If 200, executing second curl command with the public key.
    if [ "$http_code" = "200" ];then
        #This means we have received the key to which we need to curl again in order to upload the file.
        #So get the key from FILENAME
        Key=$(awk '{print $0}' $OutputFile)
        RemSignature=`echo $Key | sed "s/AWSAccessKeyId=.*Signature=.*&//g;s/\"//g;s/.*https/https/g"`
        if [ "$encryptionEnable" != "true" ]; then
            Key=\"$Key\"
        fi
        echo_t "Generated KeyIs : "
        echo $RemSignature

        CURL_CMD="curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE $Key $CERT_STATUS --connect-timeout 30 -m 30"
        CURL_CMD_FOR_ECHO="curl --tlsv1.2 -w '%{http_code}\n' -T $UploadFile -o \"$OutputFile\" --interface $WAN_INTERFACE \"$RemSignature\" $CERT_STATUS --connect-timeout 30 -m 30"
        echo_t "Curl Command built: $CURL_CMD_FOR_ECHO"

        ret= eval $CURL_CMD > $HTTP_CODE
        if [ -f $HTTP_CODE ];
        then
            http_code=$(awk '{print $0}' $HTTP_CODE)
            if [ "$http_code" != "" ];then
                echo_t "HttpCode received is : $http_code"
                if [ "$http_code" = "200" ];then
                    echo $http_code > $UPLOADRESULT
                    break
                else
                    echo "failed" > $UPLOADRESULT
                fi
            else
                http_code=0
            fi
        fi
        # Response after executing curl with the public key is 200, then file uploaded successfully.
        if [ "$http_code" = "200" ];then
	     echo_t "LOGS UPLOADED SUCCESSFULLY, RETURN CODE: $http_code"
	     t2CountNotify "SYS_INFO_LOGS_UPLOADED"
        fi
    else
        echo_t "LOG UPLOAD UNSUCCESSFUL, http_code = : $http_code"
        t2CountNotify "SYS_ERROR_LOGUPLOAD_FAILED"
    fi
    cd $curDir
}

if [ "$ARGS" = "upload" ]
then
	# Call function to upload onboard log files
	uploadOnboardLogs
fi

if [ "$ARGS" = "delete" ]
then
    echo_t "Deleting all onboard logs from $ONBOARDLOGS_NVRAM_BACKUP_PATH and $ONBOARDLOGS_TMP_BACKUP_PATH"
    rm -rf $ONBOARDLOGS_TMP_BACKUP_PATH
    rm -rf $ONBOARDLOGS_NVRAM_BACKUP_PATH
fi
