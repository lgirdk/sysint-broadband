#! /bin/sh
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

#######################################################################
#   Copyright [2014] [Cisco Systems, Inc.]
# 
#   Licensed under the Apache License, Version 2.0 (the \"License\");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
# 
#       http://www.apache.org/licenses/LICENSE-2.0
# 
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an \"AS IS\" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#######################################################################

source /lib/rdk/t2Shared_api.sh

if [ -z $1 ] && [ ! -f /tmp/webuifwbundle ]; then
    fwbundlename=$(basename `find /etc/ -name "webui-cert-bundle*.tar"`)
    if [ ! -f /nvram/certs/myrouter.io.cert.pem ] || [ -f /etc/$fwbundlename ]; then
        if [ -f /lib/rdk/check-webui-update.sh ]; then
            sh /lib/rdk/check-webui-update.sh
        else
            echo "check-webui-update.sh not available means webuiupdate support is disabled"
        fi
    else
        echo "certificate /nvram/certs/myrouter.io.cert.pem or webui bundle not available"
    fi
fi

#WEBGUI_SRC=/fss/gw/usr/www/html.tar.bz2
#WEBGUI_DEST=/var/www

#if test -f "$WEBGUI_SRC"
#then
#	if [ ! -d "$WEBGUI_DEST" ]; then
#		/bin/mkdir -p $WEBGUI_DEST
#	fi
#	/bin/tar xjf $WEBGUI_SRC -C $WEBGUI_DEST
#else
#	echo "WEBGUI SRC does not exist!"
#fi

# start lighttpd
source /etc/utopia/service.d/log_capture_path.sh
source /fss/gw/etc/utopia/service.d/log_env_var.sh
REVERT_FLAG="/nvram/reverted"
LIGHTTPD_CONF="/var/lighttpd.conf"
LIGHTTPD_DEF_CONF="/etc/lighttpd.conf"

ATOM_PROXY_SERVER="192.168.251.254"

LIGHTTPD_PID=`pidof lighttpd`
if [ "$LIGHTTPD_PID" != "" ]; then
	/bin/kill $LIGHTTPD_PID
fi

HTTP_ADMIN_PORT=`syscfg get http_admin_port`
HTTP_PORT=`syscfg get mgmt_wan_httpport`
HTTP_PORT_ERT=`syscfg get mgmt_wan_httpport_ert`
HTTPS_PORT=`syscfg get mgmt_wan_httpsport`
BRIDGE_MODE=`syscfg get bridge_mode`

if [ "$BRIDGE_MODE" != "0" ]; then
    INTERFACE="lan0"
else
    INTERFACE="l2sd0.4090"
fi

cp $LIGHTTPD_DEF_CONF $LIGHTTPD_CONF

#sed -i "s/^server.port.*/server.port = $HTTP_PORT/" /var/lighttpd.conf
#sed -i "s#^\$SERVER\[.*\].*#\$SERVER[\"socket\"] == \":$HTTPS_PORT\" {#" /var/lighttpd.conf

HTTP_SECURITY_HEADER_ENABLE=`syscfg get HTTPSecurityHeaderEnable`

if [ "$HTTP_SECURITY_HEADER_ENABLE" = "true" ]; then
	echo "setenv.add-response-header = (\"X-Frame-Options\" => \"deny\",\"X-XSS-Protection\" => \"1; mode=block\",\"X-Content-Type-Options\" => \"nosniff\",\"Content-Security-Policy\" => \"img-src 'self'; font-src 'self'; form-action 'self';\")"  >> $LIGHTTPD_CONF
fi

echo "server.port = $HTTP_ADMIN_PORT" >> $LIGHTTPD_CONF
echo "server.bind = \"$INTERFACE\"" >> $LIGHTTPD_CONF

echo "\$SERVER[\"socket\"] == \"brlan0:80\" { server.use-ipv6 = \"enable\" }" >> $LIGHTTPD_CONF
echo "\$SERVER[\"socket\"] == \"wan0:80\" { server.use-ipv6 = \"enable\" }" >> $LIGHTTPD_CONF

if [ "x$HTTP_PORT_ERT" != "x" ];then
    echo "\$SERVER[\"socket\"] == \"erouter0:$HTTP_PORT_ERT\" { server.use-ipv6 = \"enable\" }" >> $LIGHTTPD_CONF
else
    echo "\$SERVER[\"socket\"] == \"erouter0:$HTTP_PORT\" { server.use-ipv6 = \"enable\" }" >> $LIGHTTPD_CONF
fi

echo "\$SERVER[\"socket\"] == \"brlan0:443\" { server.use-ipv6 = \"enable\" ssl.engine = \"enable\" ssl.pemfile = \"/etc/server.pem\" }" >> $LIGHTTPD_CONF

#If video analytics test is enabled in device.properties file, open 58081 securely.
if [ "$VIDEO_ANALYTICS" = "enabled" ]
then
    echo "\$SERVER[\"socket\"] == \"brlan0:58081\" { server.use-ipv6 = \"enable\" server.document-root = \"/usr/video_analytics\" ssl.engine = \"enable\" ssl.verifyclient.activate = \"enable\" ssl.ca-file = \"/etc/webui/certs/comcast-rdk-ca-chain.cert.pem\" ssl.pemfile = \"/tmp/.webui/rdkb-video.pem\" }" >> $LIGHTTPD_CONF
fi

echo "\$SERVER[\"socket\"] == \"$INTERFACE:443\" { server.use-ipv6 = \"enable\" ssl.engine = \"enable\" ssl.pemfile = \"/etc/server.pem\" }" >> $LIGHTTPD_CONF
echo "\$SERVER[\"socket\"] == \"wan0:443\" { server.use-ipv6 = \"enable\" ssl.engine = \"enable\" ssl.pemfile = \"/etc/server.pem\" }" >> $LIGHTTPD_CONF
if [ $HTTPS_PORT -ne 0 ]
then
    echo "\$SERVER[\"socket\"] == \"erouter0:$HTTPS_PORT\" { server.use-ipv6 = \"enable\" ssl.engine = \"enable\" ssl.pemfile = \"/etc/server.pem\" }" >> $LIGHTTPD_CONF
else
    # When the httpsport is set to NULL. Always put default value into database.
    syscfg set mgmt_wan_httpsport 8081
    syscfg commit
    HTTPS_PORT=`syscfg get mgmt_wan_httpsport`
    echo "\$SERVER[\"socket\"] == \"erouter0:$HTTPS_PORT\" { server.use-ipv6 = \"enable\" ssl.engine = \"enable\" ssl.pemfile = \"/etc/server.pem\" }" >> $LIGHTTPD_CONF
fi

echo "\$SERVER[\"socket\"] == \"brlan0:21515\" { server.use-ipv6 = \"enable\"
                                                
proxy.server      =    ( \"\" =>              
                               ( \"localhost\" =>
                                 (                                      
                                  \"host\" => \"$ATOM_PROXY_SERVER\",
                                   \"port\" => 21515              
                                 )                            
                               )                              
                             )                                
}" >> $LIGHTTPD_CONF

# No RF captive portal 
if [ "$BOX_TYPE" = "XB6" ] || [ "$BOX_TYPE" = "MV2PLUS" ]
then
   echo "\$SERVER[\"socket\"] == \"brlan0:31515\" { server.use-ipv6 = \"enable\" 
proxy.server      =    ( \"\" =>
                               ( \"localhost\" =>
                                 (
                                  \"host\" => \"$ATOM_PROXY_SERVER\",
                                   \"port\" => 31515
                                 )
                               )
                             )
}" >> $LIGHTTPD_CONF
fi

echo "proxy.server      =    ( \"\" =>
                               ( \"localhost\" =>
                                 (
                                   \"host\" => \"$ATOM_PROXY_SERVER\",
                                   \"port\" => $HTTP_ADMIN_PORT
                                 )
                               )
                             ) " >> $LIGHTTPD_CONF

restartEventsForRfCp()
{
    echo "WEBGUI : restart norf cp events restart"
    sysevent set norf_webgui 1
    sysevent set firewall-restart
    sysevent set zebra-restart
    sysevent set dhcp_server-stop
    # Let's make sure dhcp server restarts properly
    sleep 1
    sysevent set dhcp_server-start
    dibbler-server stop
    dibbler-server start
}

# Check if unit has proper RF signal
checkRfStatus()
{
   noRfCp=0
   RF_SIGNAL_STATUS=`dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_CableRfSignalStatus | grep value | cut -f3 -d : | cut -f2 -d" "`
   isInRfCp=`syscfg get rf_captive_portal`
   echo_t "WEBGUI: values RF_SIGNAL_STATUS : $RF_SIGNAL_STATUS , isInRfCp: $isInRfCp"
   if [ "$RF_SIGNAL_STATUS" = "false" ] || [ "$isInRfCp" = "true" ]
   then
      noRfCp=1
   else
      noRfCp=0
   fi

   if [ $noRfCp -eq 1 ]
   then
      echo_t "WEBGUI: Set rf_captive_portal true"
      syscfg set rf_captive_portal true
      syscfg commit
      return 1
   else
      return 0
   fi
} 

WIFIUNCONFIGURED=`syscfg get redirection_flag`
SET_CONFIGURE_FLAG=`psmcli get eRT.com.cisco.spvtg.ccsp.Device.WiFi.NotifyWiFiChanges`

iter=0
max_iter=2
while [ "$SET_CONFIGURE_FLAG" = "" ] && [ "$iter" -le $max_iter ]
do
	iter=$((iter+1))
	echo "$iter"
	SET_CONFIGURE_FLAG=`psmcli get eRT.com.cisco.spvtg.ccsp.Device.WiFi.NotifyWiFiChanges`
done
echo_t "WEBGUI : NotifyWiFiChanges is $SET_CONFIGURE_FLAG"
echo_t "WEBGUI : redirection_flag val is $WIFIUNCONFIGURED"

# No RF captive portal
if [ "$BOX_TYPE" = "XB6" ] || [ "$BOX_TYPE" = "MV2PLUS" ]
then

	if [ -f "/tmp/.gotnetworkresponse" ]
	then
	    echo_t "WEBGUI : File /tmp/.gotnetworkresponse exists, no rf check not needed."
	else
	    # P&M up will make sure CM agent is up as well as
	    # RFC values are picked
	    echo_t "No RF CP: Check PAM initialized"
	    PAM_UP=0
	    while [ $PAM_UP -ne 1 ]
	    do
	    sleep 1
	    #Check if CcspPandMSsp is up
	    # PAM_PID=`pidof CcspPandMSsp`

	    if [ -f "/tmp/pam_initialized" ]
	    then
		 PAM_UP=1
	    fi
	    done
	    echo_t "RF CP: PAM is initialized"

	    enableRFCaptivePortal=`syscfg get enableRFCaptivePortal`
	    ethWanEnabled=`syscfg get eth_wan_enabled`
	    cpFeatureEnbled=`syscfg get CaptivePortal_Enable`

	    # Enable RF CP in first iteration. network_response.sh will run once WAN comes up
	    # network_response.sh will take the unit out of RF CP 
	    if [ "$enableRFCaptivePortal" != "false" ] && [ "$ethWanEnabled" != "true" ] && [ "$cpFeatureEnbled" = "true" ]
	    then
               checkRfStatus
	       isRfOff=$?
               echo_t "WEBGUI: RF status returned is: $isRfOff"
	       if [ "$isRfOff" = "1" ]
	       then
		  echo_t "WEBGUI: Restart events for RF CP"
		  restartEventsForRfCp
	       fi
	    fi
	fi
fi

if [ "$WIFIUNCONFIGURED" = "true" ]
then
    if [ "$SET_CONFIGURE_FLAG" = "true" ]
    then
        while : ; do
           echo_t "WEBGUI : Waiting for PandM to initalize completely to set ConfigureWiFi flag"
           CHECK_PAM_INITIALIZED=`find /tmp/ -name "pam_initialized"`
           # This check is to see if P&M is initialized 
           if [ "$CHECK_PAM_INITIALIZED" != "" ]
           then
               echo_t "WEBGUI : CHECK_PAM_INITIALIZED is $CHECK_PAM_INITIALIZED"
               break
           fi
           sleep 2
        done

        iter=0
        max_iter=21

        while : ; do
           echo_t "WEBGUI : Waiting for network reponse to run at least once"
           # This check is to see if network response ran at least once
           if [ -f "/tmp/.gotnetworkresponse" ]
           then
               echo_t "WEBGUI : File /tmp/.gotnetworkresponse exists, break loop."
               break
           fi
           
           if [ $iter -eq $max_iter ]
           then
               echo_t "WEBGUI : Max iteration for /tmp/.gotnetworkresponse reached, break loop " 
               break
           else
               iter=$((iter+1))
           fi
           sleep 5
        done

        # Read the http response value
        NETWORKRESPONSEVALUE=`cat /var/tmp/networkresponse.txt`

        # Check if the response received is 204 from google client.
        # If the response received is 204, then we should configure local captive portal.
        # This check is to make sure that we got response from network_response.sh and not from utopia_init.sh
        # /tmp/.gotnetworkresponse is touched from network_response.sh
        if [ "$NETWORKRESPONSEVALUE" = "204" ] && [ -f "/tmp/.gotnetworkresponse" ]
        then
            if [ ! -f "/tmp/.configurewifidone" ]
            then
               echo_t "WEBGUI : WiFi is not configured, setting ConfigureWiFi to true"
               output=`dmcli eRT setvalues Device.DeviceInfo.X_RDKCENTRAL-COM_ConfigureWiFi bool TRUE`
               check_success=`echo $output | grep  "Execution succeed."`
               if [ "$check_success" != "" ]
               then
                  echo_t "WEBGUI : Setting ConfigureWiFi to true is success"
                  uptime=$(cut -d. -f1 /proc/uptime)
                  echo_t "Enter_WiFi_Personalization_captive_mode:$uptime"
		  t2ValNotify "btime_wcpenter_split" $uptime
                  touch /tmp/.configurewifidone
               fi
            else
                echo_t "WEBGUI : No need to set ConfigureWiFi to true"
            fi
        fi
    else
       if [ ! -e "$REVERT_FLAG" ]
       then

          # We reached here as redirection_flag is "true". But WiFi is configured already as per notification status.
          # Set syscfg value to false now.
          echo_t "WEBGUI : WiFi is already personalized... Setting redirection_flag to false"
          syscfg set redirection_flag false
          syscfg commit
          echo_t "WEBGUI: WiFi is already personalized. Set reverted flag in nvram"	
          touch $REVERT_FLAG
       fi
    fi
fi		

if [ "$VIDEO_ANALYTICS" = "enabled" ]
then
    if [ -d /etc/webui/certs ]; then
        if [ ! -f /usr/bin/GetConfigFile ];then
            echo "Error: GetConfigFile Not Found"
            exit 127
        fi
        mkdir -p /tmp/.webui/
        ID="/tmp/.webui/rdkb-video.pem"
        cp /etc/webui/certs/comcast-rdk-ca-chain.cert.pem /tmp/.webui/
        GetConfigFile $ID
        if [ -f /tmp/.webui/rdkb-video.pem ]; then
            chmod 600 /tmp/.webui/rdkb-video.pem
        fi
    fi
fi

#echo "\$SERVER[\"socket\"] == \"$INTERFACE:10443\" { server.use-ipv6 = \"enable\" ssl.engine = \"enable\" ssl.pemfile = \"/etc/server.pem\" server.document-root = \"/fss/gw/usr/walled_garden/parcon/siteblk\" server.error-handler-404 = \"/index.php\" }" >> /var/lighttpd.conf
#echo "\$SERVER[\"socket\"] == \"$INTERFACE:18080\" { server.use-ipv6 = \"enable\"  server.document-root = \"/fss/gw/usr/walled_garden/parcon/siteblk\" server.error-handler-404 = \"/index.php\" }" >> /var/lighttpd.conf

LOG_PATH_OLD="/var/tmp/logs/"

if [ "$LOG_PATH_OLD" != "$LOG_PATH" ]
then
	sed -i "s|${LOG_PATH_OLD}|${LOG_PATH}|g" $LIGHTTPD_CONF
fi

LD_LIBRARY_PATH=/fss/gw/usr/ccsp:$LD_LIBRARY_PATH lighttpd -f $LIGHTTPD_CONF

if [ -f /tmp/.webui/rdkb-video.pem ]; then
       rm -rf /tmp/.webui/rdkb-video.pem
fi

echo_t "WEBGUI : Set event"
sysevent set webserver started
