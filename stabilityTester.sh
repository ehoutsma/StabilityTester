#!/bin/bash

XHPLBINARY="xhpl64"
MINFREQUENCY=640000 #Only test frequencies from this point.
MAXFREQUENCY=1200000 #Only test frequencies upto this point.
COOLDOWNTEMP=55000 #Cool down after a test to mC degrees

CPUFREQ_HANDLER="/sys/devices/system/cpu/cpu0/cpufreq/";
SCALINGAVAILABLEFREQUENCIES="scaling_available_frequencies";
SCALINGMINFREQUENCY="scaling_min_freq";
SCALINGMAXFREQUENCY="scaling_max_freq";

SOCTEMPCMD="/sys/class/thermal/thermal_zone0/temp"

REGULATOR_HANDLER="/sys/class/regulator/regulator.2/"
REGULATOR_MICROVOLT="microvolts"

ROOT=$(pwd)

declare -A VOLTAGES=()

# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

trap "{ killall ${ROOT}/${XHPLBINARY}; exit 0; }" SIGINT SIGTERM

if [ ! -d "${ROOT}/results" ];
then
	echo "Create";
	mkdir ${ROOT}/results;
fi

AVAILABLEFREQUENCIES=$(cat ${CPUFREQ_HANDLER}${SCALINGAVAILABLEFREQUENCIES})

for FREQUENCY in $AVAILABLEFREQUENCIES
do
    if [ $FREQUENCY -ge $MINFREQUENCY ] && [ $FREQUENCY -le $MAXFREQUENCY ];
    then
        echo "Testing frequency ${FREQUENCY}";
        
        if [ $FREQUENCY -gt $(cat ${CPUFREQ_HANDLER}${SCALINGMAXFREQUENCY}) ];
        then
            echo $FREQUENCY > ${CPUFREQ_HANDLER}${SCALINGMAXFREQUENCY}
            echo $FREQUENCY > ${CPUFREQ_HANDLER}${SCALINGMINFREQUENCY}
        else
            echo $FREQUENCY > ${CPUFREQ_HANDLER}${SCALINGMINFREQUENCY}
            echo $FREQUENCY > ${CPUFREQ_HANDLER}${SCALINGMAXFREQUENCY}
        fi

        ${ROOT}/$XHPLBINARY > ${ROOT}/results/xhpl_${FREQUENCY}.log &
        echo -n "Soc temp:"
        while pgrep -x $XHPLBINARY > /dev/null
        do
            SOCTEMP=$(cat ${SOCTEMPCMD})
            CURFREQ=$(cat ${CPUFREQ_HANDLER}${SCALINGMINFREQUENCY})
            CURVOLT=$(cat ${REGULATOR_HANDLER}${REGULATOR_MICROVOLT})
            echo -ne "\rSoc temp: ${SOCTEMP} \tCPU Freq: ${CURFREQ} \tCPU Core: ${CURVOLT} \t"
            if [ $CURFREQ -eq $FREQUENCY ];
            then
                VOLTAGES[$FREQUENCY]=$CURVOLT
            fi
            sleep 1;
        done
        echo -ne "\r"
        echo -n "Cooling down"
        while [ $SOCTEMP -gt $COOLDOWNTEMP ];
        do
            SOCTEMP=$(cat ${SOCTEMPCMD})
            echo -ne "\rCooling down: ${SOCTEMP}"
            
            sleep 1;
        done
    fi
done

echo -e "\nDone testing stability:"
for FREQUENCY in $AVAILABLEFREQUENCIES
do
    if [ $FREQUENCY -ge $MINFREQUENCY ] && [ $FREQUENCY -le $MAXFREQUENCY ];
    then
        FINISHEDTEST=$(grep -Ec "PASSED|FAILED" ${ROOT}/results/xhpl_${FREQUENCY}.log )
        SUCCESSTEST=$(grep -Ec "PASSED" ${ROOT}/results/xhpl_${FREQUENCY}.log )
        DIFF=$(grep -E 'PASSED|FAILED' ${ROOT}/results/xhpl_${FREQUENCY}.log)
        #echo $DIFF
        DIFF="${DIFF#*=}"
        DIFF="${DIFF#* }"
        #echo $DIFF
        RESULTTEST="${DIFF% .*}"
        VOLTAGE=${VOLTAGES[$FREQUENCY]}
        if [ $FINISHEDTEST -eq 1 ]; 
        then
            echo -ne "Frequency: ${FREQUENCY}\t"
            echo -ne "Voltage: ${VOLTAGE}\t"
            echo -ne "Success: ${SUCCESSTEST}\t"
            echo -ne "Result: ${RESULTTEST}\n"
        fi
    fi
done


