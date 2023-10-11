#!/bin/sh

LOG_FOLDER="/rdklogs"

. /etc/device.properties

curl_logs="$LOG_FOLDER/logs/Curlmtlslog.txt.0"

if [ ! -f $curl_logs ]; then
    touch $curl_logs
fi

echo_log()
{
    echo "`date +"%y%m%d-%T.%6N"` : $0: $*" >> $curl_logs
}

CURL_BIN=/usr/bin/curl

certlist0="/nvram/certs/devicecert_2.pk12"
certlist1="/nvram/certs/devicecert_1.pk12"
certlist2="/etc/ssl/certs/staticXpkiCrt.pk12"

passlist0="kjvrverlzhlo"
passlist1="kquhqtoczcbx"
passlist2="mamjwwgtfwpa"

getConfigFile_id1="/tmp/.cfgDynamicxpki"
getConfigFile_id2="/tmp/.cfgStaticxpki"

exec_curl_mtls () {

        CURL_ARGS=$1
        TLSRet=1

        for certnum in 0 1 2 ; do
            eval cert="\$certlist$certnum"
            if [ ! -f $cert ] ; then
                if [[ "$cert" == *"devicecert_2.pk12"* ]] && [ "$MODEL_NUM" != "CGM4981COM" ]; then
                     echo_log "Device operational cert2 not supported"
                else
                     echo_log "$cert not found!!!"
                fi
                continue
            else
                eval passcode="\$passlist$certnum"

                if [ -x /usr/bin/rdkssacli ] ; then
                    CURL_CMD="$CURL_BIN --cert-type P12 --cert $cert:$(/usr/bin/rdkssacli "{STOR=GET,SRC=$passcode,DST=/dev/stdout}") $CURL_ARGS"
                elif [ -x /usr/bin/GetConfigFile ] ; then
                    eval ID="\$getConfigFile_id$certnum"
                    GetConfigFile $ID
                    if [ ! -f "$ID" ]; then
                       echo_log "Getconfig failed for $cert"
                       continue
                    else
                       CURL_CMD="$CURL_BIN --cert-type P12 --cert $cert:$(cat $ID) $CURL_ARGS"
                    fi
                fi
                echo_log "CURL_CMD: `echo "$CURL_CMD" | sed -e 's#devicecert_1.pk12[^[:space:]]\+#devicecert_1.pk12<hidden key>#g' \
                                       -e 's#devicecert_2.pk12[^[:space:]]\+#devicecert_2.pk12<hidden key>#g' \
                                       -e 's#staticXpkiCrt.pk12[^[:space:]]\+#staticXpkiCrt.pk12<hidden key>#g' \
                                       -e 's#configsethash:[^[:space:]]\+#configsethash:#g' \
                                       -e 's#configsettime:[^[:space:]]\+#configsettime:#g' \
                                       -e 's#AWSAccessKeyId=.*Signature=.*&##g' \
                                       -e 's#-H .*https#https#g' \
                                       `"

                result=` eval $CURL_CMD > $HTTP_CODE`
                TLSRet=$?
            fi

            if [ -f $ID ]; then
               rm -rf $ID
            fi

            if [ -f $HTTP_CODE ] ; then
                http_code=$(awk '{print $1}' $HTTP_CODE )
                if [ "x$http_code" == "x200" ] && [ "x$TLSRet" == "x0" ] ; then
                    echo_log "curl connection success with ret=$TLSRet http_code=$http_code"
                    break
                elif [ "x$http_code" == "x404" ] ; then
                    echo_log "HTTP Response code received is 404"
                    break
                else
                    case $TLSRet in
                    35|51|53|54|58|59|60|64|66|77|80|82|83|90|91)
                           echo_log "curl ret $TLSRet http_code $http_code"
                           continue
                    ;;
                    esac

                    echo_log "curl connection failed with ret=$TLSRet http_code=$http_code"
                    break
                fi
            fi
        done

echo $TLSRet
}
