#!/bin/bash

# ========================================================================================
# check Process/user Utilization plugin for Nagios
#
# Written by            : Leon Samuel (Leon.Samuel@gmail.com)
# Release               : 1.0
# Creation date         : 6 Feb 2017
# Revision date         :
# Package               :
# Description           : Nagios plugin (script) to check user or process utilization in the system.
#                         With this plugin you can define whether you would like to see a users CPU, real mem,
#                         Virt Memory, utilization in the system. This should work on all Unix systems.
#
#
#                         This script has been designed and written on Linux plateform.
#
# Usage                 : ./check_ps_util -u <Username> or -c <ps command to look for>
#
#                       Check username with warning of raw cpu usage of 10 cores and critical of 12 memory critical 64G and warning of 56G:
#                       check_ps_util -u genedata -wrc 10 -wrm 56 -crc 12 -crm 64
#                       Check username with warning of 85% and critical of 95% of total resources of memory or cpu:
#                       check_ps_util -u genedata -w 85 -c 95
#
#                       Check command utilization :
#                       check_ps_util -c genedata
#
# -----------------------------------------------------------------------------------------
#
#
#
# =========================================================================================
#
# HISTORY :
#     Release   |     Date      |    Authors            |       Description
# --------------+---------------+-----------------------+----------------------------------
# 1.0	        | 06.02.2017    | Leon Samuel           | First Version
# =========================================================================================

# Paths to commands used in this script
#set -x
PATH=$PATH:/usr/sbin:/usr/bin

# Nagios return codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
NAGIOS_WARNING=85
NAGIOS_CRITICAL=95

# Plugin variable description
PROGNAME=$(basename $0)
PROGPATH=$(echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,')
REVISION="Revision 1.0"
AUTHOR="(c) 2017 Leon Samuel (Leon.Samuel@gmail.com)"

# Functions plugin usage
print_revision() {
    echo "$PROGNAME $REVISION $AUTHOR"
}

print_usage() {
        echo "Usage: $PROGNAME (-u /--user <Username> | -c / --command <Command> ) \\"
		echo "(-cpu{XX:XX}% <CPU Thesholds {Warning:Critical} /%>) "
		echo "(-mem{XX:XX}% <Memory Thesholds {Warning:Critical} /%>) "
        echo ""
        echo "-h Show this page"
        echo "-v Script version + -h"
        echo "-cpu{XX:XX}%   	Threshhold for CPU usage: example {5:12} will be for warning at 5+ critical 12+ "
        echo "-mem{XX:XX}%		Threshhold for CPU usage: example {40:48}% will be for warning at 40% critical 48%"
        echo "					If % appears for the mem or cpu then the relative usage will be calculated"
}

print_help() {
        print_revision
        echo ""
        print_usage
        echo ""
        exit 0
}


# -------------------------------------------------------------------------------------
# Grab the command line arguments
# --------------------------------------------------------------------------------------
while [ $# -gt 0 ]; do
        case "$1" in
                -h | --help)
                print_help
                exit $STATE_OK
                ;;
                -v | --version)
                print_revision
                exit $STATE_OK
                ;;
                -u | --user)
                shift
                SEARCHSTR=$1
				Field=1
                ;;
                -c | --command)
                shift
                SEARCHSTR=$1
				Field=11
				if [${USERNAME} != "" ]; then
					print_usage
					exit 1
                ;;
                -cpu | --cpu)
                shift
                CPU=$1
				 if [ "`echo $CPU | grep \% > /dev/null ; echo $?`" == "0" ]
					CPUSYSTEM=`cat /proc/cpuinfo | grep "processor" | tail -1 | awk '{print $3+1}'`
					CPUMAX=$(echo "scale=0;$CPUSYSTEM*`echo $CPU|awk -F\: '{print $2}' | sed 's/}%//'`/100"|bc)
					CPUMIN=$(echo "scale=0;$CPUSYSTEM*`echo $CPU |awk -F\: '{print $1}' | sed 's/{//'`/100"| bc)
					CPUPERCENT=true
				else
					CPUMAX=`echo $CPU|awk -F\: '{print $2}' | sed 's/}//'`
					CPUMIN=`echo $CPU |awk -F\: '{print $1}' | sed 's/{//'`
					CPUPERCENT=false
				fi
                ;;
                -mem | --mem )
                shift
                MEM=$1
				if [ "`echo $CPU | grep \% > /dev/null ; echo $?`" == "0" ]
					MEMSYSTEM=`cat /proc/meminfo | grep MemTotal | awk '{print $2/1000000}'| awk -F\. '{print $1}'`
					MEMMAX=$(echo "scale=0;$MEMSYSTEM*`echo $MEM|awk -F\: '{print $2}' | sed 's/}%//'`/100"|bc)
					MEMMIN=$(echo "scale=0;$MEMSYSTEM*`echo $MEM |awk -F\: '{print $1}' | sed 's/{//'`/100"| bc)
					MEMPERCENT=TRUE
				else
					MEMMAX=`echo $MEM|awk -F\: '{print $2}' | sed 's/}//'`
					MEMMIN=`echo $MEM |awk -F\: '{print $1}' | sed 's/{//'`
					MEMPERCENT=FALSE
				fi
                ;;
                *)  echo "Unknown argument: $1"
                print_usage
                exit $STATE_UNKNOWN
                ;;
                esac
        shift
done


# -----------------------------------------------------------------------------------------
# Building the command.
# -----------------------------------------------------------------------------------------

PIDS=`ps aux | awk '\$${Field} ~ /${SEARCHSTR}/ {print \$2}'| grep -v awk`

# -----------------------------------------------------------------------------------------
# For each process find threads and get the CPU and mem utilization
# -----------------------------------------------------------------------------------------

for I in ${PIDS}; do
	STR1=` ps   -p $I u | grep ${SEARCHSTR} | awk '{printf("%d  %d  %d  %d",$3, $4,$5,$6 )}'`
    STR=`ps -T -p $I u | awk '{cpu +=$4 ; mem +=$5 ; vsz =$6 ; rss =$7 } END {printf("%d  %d  %d  %d", cpu,  mem ,vsz ,rss)}'`
	CPUSUM=$[$CPUSUM + `echo $STR | awk '{print $1}'` + `echo $STR1 | awk '{print $1}'`]
	MEMSUM=$[$MEMSUM + `echo $STR | awk '{print $4}'` + `echo $STR1 | awk '{print $4}'`]
done





# -----------------------------------------------------------------------------------------
# Check and output the findings to nagios
# -----------------------------------------------------------------------------------------
if [ "$NFS_SIDE" = "server" ]; then
        NFS_EXPORTS=`showmount -e | awk '{ print $1 }' | sed "1,1d" | tr -s "\n" " "`
        if [ -z "$NFS_EXPORTS" ]; then
                echo "NFS UNKNOWN : NFS server no export Filesystem"
                exit $STATE_UNKNOWN
        fi
        # Check exportfs
        for i in ${NFS_EXPORTS[@]}; do
                if [ ! -d $i ]; then
                FAULT_ARRAY=( ${FAULT_ARRAY[@]} $i )
                fi
        done
        if [ ${#FAULT_ARRAY[@]} != 0 ]; then
        echo "NFS CRITICAL : Export ${FAULT_ARRAY[@]} directory not exist."
        exit $STATE_CRITICAL
        fi
fi

#



# Convert $NFS_ADD_MOUNTS to array and add to $NFS_FSTAB_MOUNTS list

if [ "${NFS_ADD_MOUNTS}" != "none" ];then
        TAB_ADDLIST=(`echo $NFS_ADD_MOUNTS| sed 's/,/ /g'`)
        NBR_INDEX=${#TAB_ADDLIST[@]}
        i=0
        ARRAY=${NFS_MOUNTS[@]}
        while [ $i -lt ${NBR_INDEX} ]; do
                BL_ITEM="${TAB_ADDLIST[$i]}"
                ARRAY=`echo ${ARRAY[@]} "${BL_ITEM} "`
                let "i += 1"
        done
        NFS_MOUNTS=(`echo ${ARRAY[@]}`)
fi

# Convert $NFS_EXCLUDE_MOUNTS to array and exclude to array to $NFS_MOUNTS list

if [ "${NFS_EXCLUDE_MOUNTS}" != "none" ]; then
        TAB_BLACKLIST=(`echo $NFS_EXCLUDE_MOUNTS | sed 's/,/ /g'`)
        NBR_INDEX=${#TAB_BLACKLIST[@]}
        i=0
        ARRAY=${NFS_MOUNTS[@]}
        while [ $i -lt ${NBR_INDEX} ]; do
                BL_ITEM="${TAB_BLACKLIST[$i]}"
                ARRAY=(`echo ${ARRAY[@]/"$BL_ITEM"/}`)
                let "i += 1"
        done
        NFS_MOUNTS=(`echo ${ARRAY[@]}`)
fi

#NFS_MOUNTS=`mount | egrep '( nfs | nfs3 | type nfs )'  | awk '{print $3}'`

sleep 1

PROC_NFSCHECK=`ps -ef | grep "/tmp/nfs_health_monitor $i" | grep -v grep | awk '{print $2}'`
if [ -n "$PROC_NFSCHECK" ]; then
        case $NFS_SIDE in
                server) echo "NFS CRITICAL : NFS server services ${NFS_SERVICES[@]} running. Stale NFS mountpoint $i. NFS exports ${NFS_EXPORTS[@]} healthy | NFS Perfdata"
                        kill -9 $PROC_NFSCHECK
                        exit $STATE_CRITICAL;;
                client) echo "NFS CRITICAL : NFS client services ${NFS_SERVICES[@]} running. Stale NFS mountpoint $i | NFS perfdata"
                        kill -9 $PROC_NFSCHECK
                        exit $STATE_CRITICAL;;
        esac

else
        case $NFS_SIDE in
                server) echo "NFS OK : NFS server services ${NFS_SERVICES[@]} running. NFS mountpoint "${NFS_MOUNTS[@]}" healthy. NFS exports ${NFS_EXPORTS[@]} healthy | NFS perfdat
a"
                        exit $STATE_OK;;
                client) echo "NFS OK : NFS client services ${NFS_SERVICES[@]} running. NFS mountpoint "${NFS_MOUNTS[@]}" healthy | NFS perfdata"
                        exit $STATE_OK;;
        esac
fi
