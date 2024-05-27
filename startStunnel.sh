#!/bin/sh
. /etc/include.properties
. /etc/device.properties
. /usr/bin/stunnelCertUtil.sh
source /etc/log_timestamp.sh

if [ -f /lib/rdk/t2Shared_api.sh ]; then
        source /lib/rdk/t2Shared_api.sh
fi

export TERM=xterm
export HOME=/home/root
LOG_FILE="$LOG_PATH/stunnel.log"

usage()
{
  echo_t "STUNNEL USAGE:  startSTunnel.sh <localport> <jumpfqdn> <umpserver> <jumpserverport> <reverseSSHArgs> <shortshostLogin> <nonshortshostLogin>"
}

if [ $# -lt 5 ]; then
   usage
   exit 1
fi

if [ $DEVICE_TYPE == "broadband" ]; then
    DEVICE_CERT_PATH=/nvram/certs
elif [ $DEVICE_TYPE == "mediaclient" -o $DEVICE_TYPE == "hybrid" ]; then
    DEVICE_CERT_PATH=/opt/certs
else
    echo_t "STUNNEL: Unexpected device type: $DEVICE_TYPE"
    exit 1
fi

#collect the arguments
#    1) CPE's available port starting from 3000
#    2) FQDN of jump server
#    3) Port number of stunnel's server instance at jump server
LOCAL_PORT=$1
JUMP_FQDN=$2
JUMP_SERVER=$3
JUMP_PORT=$4
REVERSESSHARGS=$5
SHORTSHOSTLOGIN=$6
NONSHORTSHOSTLOGIN=$7

t2ValNotify "SSH_INFO_SOURCE_IP" "$JUMP_SERVER"
isShortsenabled=$(dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Feature.SHORTS.Enable | grep value | cut -d ":" -f 3 | tr -d ' ')
echo_t "isShortsenabled = $isShortsenabled " >> $LOG_FILE
if [ $isShortsenabled == "false" ];then
        /bin/sh /lib/rdk/startTunnel.sh start ${REVERSESSHARGS}${NONSHORTSHOSTLOGIN}
        exit 0
fi

STUNNEL_PID_FILE=/tmp/stunnel_$LOCAL_PORT.pid
REVSSH_PID_FILE=/var/tmp/rssh.pid
STUNNEL_CONF_FILE=/tmp/stunnel_$LOCAL_PORT.conf

echo  "pid = $STUNNEL_PID_FILE"           > $STUNNEL_CONF_FILE
echo  "output=$LOG_FILE"                 >> $STUNNEL_CONF_FILE
echo  "debug = 7"                        >> $STUNNEL_CONF_FILE
echo  "[ssh]"                            >> $STUNNEL_CONF_FILE
echo  "client = yes"                     >> $STUNNEL_CONF_FILE

# Use localhost to listen on both IPv4 and IPv6
echo "accept = localhost:$LOCAL_PORT"    >> $STUNNEL_CONF_FILE
echo "connect = $JUMP_SERVER:$JUMP_PORT" >> $STUNNEL_CONF_FILE

extract_stunnel_client_cert

if [ ! -f $CERT_PATH -o ! -f $CA_FILE ]; then
    echo_t "STUNNEL: Required cert/CA file not found. Exiting..." >> $LOG_FILE
    t2CountNotify "SHORTS_STUNNEL_CERT_FAILURE"
    exit 1
fi

# Specify cert, CA file and verification method
DEV_SAN=tstcpedev.xcal.tv
PROD_SAN=tstcpeprod.xcal.tv

# this might change once we get proper certificates
echo "cert = $CERT_PATH"                 >> $STUNNEL_CONF_FILE
echo "CAfile = $CA_FILE"                 >> $STUNNEL_CONF_FILE
echo "verifyChain = yes"                 >> $STUNNEL_CONF_FILE
echo "checkHost = $JUMP_FQDN"            >> $STUNNEL_CONF_FILE

DEVICETYPE=$(dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_RFC.Identity.DeviceType | grep value | cut -d ":" -f 3 | tr -d ' ')
echo_t "STUNNEL: Device type is $DEVICETYPE"
if [ ! -z "$DEVICETYPE" ]; then
    if [ "$DEVICETYPE" == "TEST" ] || [ "$DEVICETYPE" == "test" ];  then
        echo_t "STUNNEL: Device type is TEST" >> $LOG_FILE
        t2CountNotify "SHORTS_DEVICE_TYPE_TEST"
        echo "checkHost   = $DEV_SAN"    >> $STUNNEL_CONF_FILE
    else
        echo_t "STUNNEL: Device type is PROD" >> $LOG_FILE
        t2CountNotify "SHORTS_DEVICE_TYPE_PROD"
        echo "checkHost   = $PROD_SAN"         >> $STUNNEL_CONF_FILE
    fi
else
    echo_t "STUNNEL: Device type is Unknown" >> $LOG_FILE
    t2CountNotify "SHORTS_DEVICE_TYPE_UNKNOWN"
fi

export P12PASSCODE=$(eval "$PASSCODE")

/usr/bin/stunnel $STUNNEL_CONF_FILE

# cleanup sensitive files early
rm -f $STUNNEL_CONF_FILE
rm -f $D_FILE

REVSSHPID1=`cat $REVSSH_PID_FILE`
STUNNELPID=`cat $STUNNEL_PID_FILE`
count=0
while [ -z "$STUNNELPID" ]; do
    if [ $count -lt 2 ]; then
	sleep 1
        echo_t "STUNNEL: stunnel PID file is not available, Retrying..." >> $LOG_FILE
        STUNNELPID=`cat $STUNNEL_PID_FILE`
        count=$((count + 1))
    else
        rm -f $STUNNEL_PID_FILE
    	rm -f $CA_FILE
    	if [ "x$CRED_INDEX" == "x0" ]; then
        	touch /tmp/.$SE_DEVICE_CERT
    	fi
    	echo_t "STUNNEL: stunnel-client failed to establish. Exiting..." >> $LOG_FILE
        t2CountNotify "SHORTS_STUNNEL_CLIENT_FAILURE"
        exit
    fi
done

#Starting startTunnel
/bin/sh /lib/rdk/startTunnel.sh start ${REVERSESSHARGS}${SHORTSHOSTLOGIN}

REVSSHPID2=`cat $REVSSH_PID_FILE`

#Terminate stunnel if revssh fails.
if [ -z "$REVSSHPID2" ] || [ "$REVSSHPID1" == "$REVSSHPID2" ]; then
    kill -9 $STUNNELPID
    rm -f $STUNNEL_PID_FILE
    if [ "x$CRED_INDEX" == "x0" ]; then
        touch /tmp/.$SE_DEVICE_CERT
    fi
    echo_t "STUNNEL: Reverse SSH failed to connect. Exiting..." >> $LOG_FILE
    t2CountNotify "SHORTS_SSH_CLIENT_FAILURE"
    exit
fi

echo_t "STUNNEL: Reverse SSH pid = $REVSSHPID2, Stunnel pid = $STUNNELPID" >> $LOG_FILE
t2CountNotify "SHORTS_CONN_SUCCESS"
#watch for termination of ssh-client to terminate stunnel
while test -d "/proc/$REVSSHPID2"; do
     sleep 5
done

echo_t "STUNNEL: Reverse SSH session ended. Exiting..." >> $LOG_FILE
kill -9 $STUNNELPID
rm -f $STUNNEL_PID_FILE
