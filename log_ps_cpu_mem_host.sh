#!/bin/sh
##################################################################################
# If not stated otherwise in this file or this component's Licenses.txt file the
# following copyright and licenses apply:
#
#  Copyright 2018 RDK Management
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
. /etc/include.properties
ps_names="CcspCMAgentSsp CcspPandMSsp CcspHomeSecurity CcspMoCA CcspTandDSsp CcspXdnsSsp CcspEthAgent CcspLMLite PsmSsp notify_comp"
top_op=$(top -b -n -1 | tr -s ' ' | sed -r 's/S ([^0-9])/S\1/'  | sed 's/^ \s*//' | cut -d ' ' -f 7-)
page_size=4
cpu=0
mem=0
LOG_FILE="$LOG_PATH/CPUInfo.txt.0"

getCPU()
{
    cpu=$(echo "$top_op" | grep $1 | cut -d ' ' -f 1 | sed s/%//)
}

getMem()
{
    total_rss=0
    
    for pid in $1
    do
        rss=$(cat /proc/$pid/stat | cut -d ' ' -f 24)
        let total_rss+=rss
    done
    
    res=$(expr $total_rss * $page_size)
    mem=$res
    
    if [ $res -ge 1024 ];
    then
        mem=$(expr $res / 1024)
    fi
    
    if [ $mem -ge 1024 ];
    then
        mem="${mem}m"
    else
        mem="${mem}k"
    fi
}

for ps_name in $ps_names
do
    pid=$(pidof $ps_name)
    cpu=0
    mem=0
    getCPU $ps_name
    getMem $pid
    
    cpu_mem_info="${cpu_mem_info}\n${ps_name}_cpu:$cpu\n${ps_name}_mem:$mem"
done
echo -e "$cpu_mem_info" >> $LOG_FILE
