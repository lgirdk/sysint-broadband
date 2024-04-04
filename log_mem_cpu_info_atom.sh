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

while :
do

T2_MSG_CLIENT=/usr/bin/telemetry2_0_client

t2CountNotify() {
    if [ -f $T2_MSG_CLIENT ]; then
        marker=$1
        $T2_MSG_CLIENT  "$marker" "1"
    fi
}

t2ValNotify() {
    if [ -f $T2_MSG_CLIENT ]; then
        marker=$1
        shift
        $T2_MSG_CLIENT "$marker" "$*"
    fi
}

getstat() {
	grep 'cpu ' /proc/stat | sed -e 's/  */x/g' -e 's/^cpux//'
}

STARTSTAT_HOUR=$(getstat)
LOG_FILE="/rdklogs/logs/CPUInfoPeer.txt.0"
LOW_MEM_THRESHOLD=30000

#This script runs once in 1 hour, sleep 45 minutes now and 15 minutes later during cpu usage for last 15 minutes calculation
sleep 45m

uptime=$(cut -d. -f1 /proc/uptime)
echo "before running log_mem_cpu_info_atom.sh.sh printing top output" >> /rdklogs/logs/CPUInfoPeer.txt.0
top -n1 -b >> /rdklogs/logs/CPUInfoPeer.txt.0
if [ $uptime -gt 1800 ] && [ "$(pidof CcspWifiSsp)" != "" ] && [ "$(pidof apup)" == "" ] && [ "$(pidof fastdown)" == "" ] && [ "$(pidof apdown)" == "" ]  && [ "$(pidof aphealth.sh)" == "" ] && [ "$(pidof radiohealth.sh)" == "" ] && [ "$(pidof aphealth_log.sh)" == "" ] && [ "$(pidof bandsteering.sh)" == "" ] && [ "$(pidof l2shealth_log.sh)" == "" ] && [ "$(pidof l2shealth.sh)" == "" ] && [ "$(pidof dailystats_log.sh)" == "" ] && [ "$(pidof dailystats.sh)" == "" ]; then
	if [ -e /rdklogger/log_capture_path_atom.sh ]
	then
		source /rdklogger/log_capture_path_atom.sh 
	else
		echo_t()
		{
			echo $1
		}
	fi

TMPFS_THRESHOLD=85

	COUNTINFO="/tmp/cpuinfocount.txt"

	getDate()
	{
		dandt_now=`date +'%Y:%m:%d:%H:%M:%S'`
		echo "$dandt_now"
	}

	getDateTime()
	{
		dandtwithns_now=`date +'%Y-%m-%d:%H:%M:%S:%6N'`
		echo "$dandtwithns_now"
	}

	extract() {
	    echo $1 | cut -d 'x' -f $2
	}

	change() {
	    local e=$(extract $ENDSTAT $1)
	    local b=$(extract $STARTSTAT $1)
	    local diff=$(( $e - $b ))
	    echo $diff
    }

    calculate_cpu_use()
    {
	    USR=$(change 1)
	    SYS=$(change 3)
	    IDLE=$(change 4)
	    IOW=$(change 5)
	    IRQ=$(change 6)
	    SIRQ=$(change 7)
	    STEAL=$(change 8)

	    ACTIVE=$(( $USR + $SYS + $IOW + $IRQ + $SIRQ + $STEAL))

	    TOTAL=$(($ACTIVE + $IDLE))

	    Curr_CPULoad=$(( $ACTIVE * 100 / $TOTAL ))
	    echo "$Curr_CPULoad"
    }

    print_cpu_usage()
    {
	    if [ "$1" = "" ] || [ "$2" = "" ]; then
		    echo_t "No parameters for the function print_cpu_usage" >> "$LOG_FILE"
		    return
	    fi
	    timestamp=$(getDate)
	    echo_t "RDKB_CPU_USAGE: marker $1 is $2 at timestamp $timestamp" >> "$LOG_FILE"
	    if [ "$2" -ge "90" ]; then
		    echo_t "WARNING RDKB_CPU_USAGE_AVERAGE is more than 90% for marker : $1 : $2  at timestamp $timestamp" >> "$LOG_FILE"
		    if [ $2 -eq 100 ]; then
			    t2CountNotify "SYS_ERROR_CPU100_ATOM"
		    fi
		    if [ "$1" = "USED_CPU_15MIN_ATOM_split" ]; then
			    t2CountNotify "SYS_ERROR_USED_CPU_15MIN_ATOM_Above90"
		    fi
		    if [ "$1" = "USED_CPU_HOURLY_ATOM_split" ]; then
			    t2CountNotify "SYS_ERROR_USED_CPU_HOURLY_ATOM_Above90"
		    fi
		    if [ "$1" = "USED_CPU_DEVICE_BOOT_ATOM_split" ]; then
			    t2CountNotify "SYS_ERROR_USED_CPU_DEVICE_BOOT_ATOM_Above90"
		    fi
	    fi
	    echo_t "$1:$2" >> "$LOG_FILE"
	    t2ValNotify "$1" "$2"
    }

	FIFTEEN_MINUTES=900
	max_count=12
	DELAY=30
	if [ -f $COUNTINFO ]
	then
		count=`cat $COUNTINFO`
	else
		count=0
	fi

	timestamp=`getDate`

		totalMemSys=`free | awk 'FNR == 2 {print $2}'`
		usedMemSys=`free | awk 'FNR == 2 {print $3}'`
		freeMemSys=`free | awk 'FNR == 2 {print $4}'`
		availableMemSys=`free | awk 'FNR == 2 {print $7}'`

		echo "RDKB_SYS_MEM_INFO_ATOM : Total memory in system is $totalMemSys at timestamp $timestamp" >> "$LOG_FILE"
		echo "RDKB_SYS_MEM_INFO_ATOM : Used memory in system is $usedMemSys at timestamp $timestamp" >> "$LOG_FILE"
		echo "RDKB_SYS_MEM_INFO_ATOM : Free memory in system is $freeMemSys at timestamp $timestamp" >> "$LOG_FILE"
		echo "RDKB_SYS_MEM_INFO_ATOM : Available memory in system is $availableMemSys at timestamp $timestamp" >> "$LOG_FILE"

		echo "USED_MEM_ATOM:$usedMemSys" >> "$LOG_FILE"
		echo "FREE_MEM_ATOM:$freeMemSys" >> "$LOG_FILE"
		echo "AVAILABLE_MEM_ATOM:$availableMemSys" >> "$LOG_FILE"

		t2ValNotify "USED_MEM_ATOM_split" "$usedMemSys"
		t2ValNotify "FREE_MEM_ATOM_split" "$freeMemSys"
		t2ValNotify "AVAILABLE_MEM_ATOM_split" "$availableMemSys"

		if [ $freeMemSys -lt $LOW_MEM_THRESHOLD ]; then
			echo_t "ERROR free memory is less than threshold value $LOW_MEM_THRESHOLD FREE_MEM_ATOM:$freeMemSys at timesstamp $timestamp" >> "$LOG_FILE"
			t2CountNotify "SYS_ERROR_LOW_FREE_MEMORY_ATOM"
			echo_t "df -h:" >> "$LOG_FILE"
			echo_t "`df -h`" >> "$LOG_FILE"
			echo_t "ls -lS of tmp folder:" >> "$LOG_FILE"
			echo_t "`ls -lS /tmp/`" >> "$LOG_FILE"
			echo_t "ps wwl:" >> "$LOG_FILE"
			echo_t "`ps wwl`" >> "$LOG_FILE"
			echo_t "cat /proc/meminfo:" >> "$LOG_FILE"
			echo_t "`cat /proc/meminfo`" >> "$LOG_FILE"
		fi

	    LOAD_AVG=`uptime | awk -F'[a-z]:' '{ print $2}' | sed 's/^ *//g' | sed 's/,//g' | sed 's/ /:/g'`
	    echo " RDKB_LOAD_AVERAGE_ATOM : Load Average is $LOAD_AVG at timestamp $timestamp" >> "$LOG_FILE"
	    LOAD_AVG_15=`echo $LOAD_AVG | cut -f3 -d:`
	    echo_t "LOAD_AVERAGE_ATOM:$LOAD_AVG_15" >> "$LOG_FILE"
	    t2ValNotify "LOAD_AVG_ATOM_split" "$LOAD_AVG_15"

	    STARTSTAT_15MIN=$(getstat)
	    sleep `expr $FIFTEEN_MINUTES - $DELAY`
	    STARTSTAT=$(getstat)
	    sleep $DELAY
	    ENDSTAT=$(getstat)
	    Curr_CPULoad=$(calculate_cpu_use)
	    #Average of CPU USAGE from last 30 seconds
	    print_cpu_usage "USED_CPU_ATOM_split" "$Curr_CPULoad"

	    STARTSTAT="$STARTSTAT_15MIN"
	    Curr_CPULoad=$(calculate_cpu_use)
	    #Average of CPU USAGE from last 15 minutes
	    print_cpu_usage "USED_CPU_15MIN_ATOM_split" "$Curr_CPULoad"

	    #Average of CPU USAGE from last 1 hour.
	    ENDSTAT=$(getstat)
	    if [ "$STARTSTAT_HOUR" != "" ]; then
		    STARTSTAT="$STARTSTAT_HOUR"
		    Curr_CPULoad=$(calculate_cpu_use)
		    print_cpu_usage "USED_CPU_HOURLY_ATOM_split" "$Curr_CPULoad"
	    fi

	    #Average of CPU USAGE from the device boot
	    STARTSTAT=0x0x0x0x0x0x0x0x0x0
	    Curr_CPULoad=$(calculate_cpu_use)
	    print_cpu_usage "USED_CPU_DEVICE_BOOT_ATOM_split" "$Curr_CPULoad"

		count=$((count + 1))

		echo_t "Count = $count"
		CPU_INFO=`mpstat | tail -1` 
		echo "RDKB_CPUINFO_ATOM : Cpu Info is $CPU_INFO at timestamp $timestamp"

                TMPFS_CUR_USAGE=0
                TMPFS_CUR_USAGE=`df /tmp | tail -1 | awk '{print $(NF-1)}' | cut -d"%" -f1`

		if [ "$count" -eq "$max_count" ]
		then
			echo "RDKB_PROC_MEM_LOG_ATOM : Process Memory log at $timestamp is" >> /rdklogs/logs/CPUInfoPeer.txt.0
			echo_t "" >> /rdklogs/logs/CPUInfoPeer.txt.0
			top -m -b n 1 >> /rdklogs/logs/CPUInfoPeer.txt.0

			echo_t "================================================================================" >> /rdklogs/logs/CPUInfoPeer.txt.0
			echo_t ""
			echo "RDKB_DISK_USAGE_ATOM : Systems Disk Space Usage log at $timestamp is"
			echo_t ""
			disk_usage="df"
			eval $disk_usage
                	count=0
                        echo_t "TMPFS_USAGE_ATOM_PERIODIC:$TMPFS_CUR_USAGE"
	                t2ValNotify "TMPFS_USAGE_ATOM_PERIODIC" "$TMPFS_CUR_USAGE"	
                        if [ $TMPFS_CUR_USAGE -ge $TMPFS_THRESHOLD ]
                        then
                            echo_t "TMPFS_USAGE_ATOM:$TMPFS_CUR_USAGE"
                            t2ValNotify "TMPFS_USAGE_ATOM" "$TMPFS_CUR_USAGE"
                        fi
		else
			echo "RDKB_PROC_MEM_LOG_ATOM : Process Memory log at $timestamp is" >> /rdklogs/logs/CPUInfoPeer.txt.0
			echo_t "" >> /rdklogs/logs/CPUInfoPeer.txt.0
			top -m -b n 1 | head -n 14 >> /rdklogs/logs/CPUInfoPeer.txt.0
                        if [ $TMPFS_CUR_USAGE -ge $TMPFS_THRESHOLD ]
                        then
                            disk_usage="df"
                            eval $disk_usage
                            echo_t "TMPFS_USAGE_ATOM:$TMPFS_CUR_USAGE"
                            t2ValNotify "TMPFS_USAGE_ATOM" "$TMPFS_CUR_USAGE"
                        fi
		fi

	if [ -f $COUNTINFO ]
	then
		echo $count > $COUNTINFO
	else
		touch $COUNTINFO
		echo $count > $COUNTINFO
	fi

	# do saplogging only if any type of swap is enabled
	swap_devices=`cat /proc/swaps | wc -l`
	if [ $swap_devices -gt 1 ]; then
	    # swap usage information
	    # vmInfoHeader: swpd,free,buff,cache,si,so
	    # vmInfoValues: <int>,<int>,<int>,<int>,<int>,<int>
	    echo "VM STATS SINCE BOOT ATOM"
	    swaped=`free | awk 'FNR == 4 {print $3}'`
	    cache=`cat /proc/meminfo | awk 'FNR == 4 {print $2}'`
	    buff=`cat /proc/meminfo | awk 'FNR == 3 {print $2}'`
        swaped_in=`grep pswpin /proc/vmstat | cut -d ' ' -f2`
        swaped_out=`grep pswpout /proc/vmstat | cut -d ' ' -f2`
	    # conversion to kb assumes 4kb page, which is quite standard
	    swaped_in_kb=$(($swaped_in * 4))
	    swaped_out_kb=$(($swaped_out * 4))
	    echo vmInfoHeader: swpd,free,buff,cache,si,so
	    echo vmInfoValues: $swaped,$freeMemSys,$buff,$cache,$swaped_in,$swaped_out
	    # end of swap usage information block
        fi
        nvram_fsck="/rdklogger/nvram_rw_restore.sh"
	nvram_ro_fs=`mount | grep "nvram " | grep dev | grep "[ (]ro[ ,]"`
	if [ "$nvram_ro_fs" != "" ]; then
		echo "[RDKB_SELFHEAL] : NVRAM ON ATOM IS READ-ONLY" >> "$LOG_FILE"
                if [ -f $nvram_fsck ] && [ ! -e /tmp/atom_ro ]; then
                    source $nvram_fsck
                fi
	fi

	NVRAM_USAGE=$(df /nvram | sed -n 's/.* \([0-9]\+\)% .*/\1/p')
	t2ValNotify "NVRAM_USE_PERCENTAGE_ATOM_split" "$NVRAM_USAGE"
	echo_t "[RDKB_SELFHEAL] : NVRAM_USE_PERCENTAGE_ATOM_split $NVRAM_USAGE" >> "$LOG_FILE"

	if [ "$NVRAM_USAGE" -ge 95 ]; then
		t2CountNotify "SYS_ERROR_NVRAM_ATOM_Above95_split"
		echo_t "WARNING ATOM Nvram usage is $NVRAM_USAGE % at timestamp $timestamp" >> "$LOG_FILE"
		echo_t "*********** dump file usage in atom nvram **************" >> "$LOG_FILE"
		echo_t "`du -ah /nvram`" >> "$LOG_FILE"
		echo_t "******************************" >> "$LOG_FILE"
	fi

        echo "after running log_mem_cpu_info_atom..sh printing top output" >> /rdklogs/logs/CPUInfoPeer.txt.0 
	top -n1 -b >> /rdklogs/logs/CPUInfoPeer.txt.0
else
	echo "skipping log_mem_cpu_info_atom.sh run" >> /rdklogs/logs/AtomConsolelog.txt.0
	#This sleep is to avoid infinite prints in case of error.
	sleep $DELAY
fi

done

