#!/bin/bash

# ------------------------------------------------------------------------------
export LC_NUMERIC="C"

SELF_DIR=$(basename -- "${0}")
SELF_DIR=${SELF_DIR%.*}
CONF_IMG="$HOME/.config/${SELF_DIR%.*}/%s.png"
SELF_IMG="$(cd "$(dirname "${0}")" && pwd)/${SELF_DIR}/%s.png"

TMAX="90000"
GREEN="green"

# ------------------------------------------------------------------------------
function usage
{
    cat << USAGE
Usage: $(basename "${0}") [options], where options are:
    -t, --tmax
        "Red" temperature (Celsius, default is 90)
USAGE
    exit 1
}

# ------------------------------------------------------------------------------
function check_int 
{
    readonly int_rx="^[0-9]+$"
    if ! [[ "${1}" =~ $int_rx ]]; then
        echo "0"
    else
        echo "${1}"
    fi
}

# ------------------------------------------------------------------------------
function get_img
{
    local img=$(printf ${CONF_IMG} ${GREEN})
    if [[ -f ${img} ]]; then
        echo ${img}
    else
        printf ${SELF_IMG} ${GREEN}
    fi   
}

# ------------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "${1}" in
        '-p' | '--pmax')
            shift
            PMAX=$(check_int "${1}")
            (( ${PMAX} < 100 && ${PMAX} > 0 )) || usage
            (( PMAX*=1000 ))
            shift
            continue
        ;;
        *)
            usage
        ;;
    esac
done

# ------------------------------------------------------------------------------
TEMPERATURE="0"

TOOLTIP="┌ <span weight='bold'>$(grep "model name" /proc/cpuinfo | cut -f2 -d ":" | sed -n 1p | sed -e 's/^[ \t]*//')</span>\n"

declare -r ALL_CPU=($(awk '/MHz/{print $4}' /proc/cpuinfo | cut -f1 -d"."))

IDX=0
FREQ=0
for mhz in "${ALL_CPU[@]}"; do
    (( FREQ+=mhz ))
    TOOLTIP+="├─ CPU ${IDX}: ${mhz} MHz\n"
    (( IDX+=1 ))
done

declare -r ALL_TEMP=($(cat /sys/class/thermal/thermal_zone*/temp))

IDX=0
for temp in "${ALL_TEMP[@]}"; do
    grn="green"
    (( "${temp}" > "${TMAX}" )) && grn="red"
    temp=$( numfmt --to iec --format "%.2f" $(( ${temp} / 1000 )) )
    TOOLTIP+=" Core ${IDX}: <span weight='bold' fgcolor='${grn}'>${temp}</span> ℃\n"
    (( IDX+=1 ))
    if [[ ${IDX} -lt ${#ALL_TEMP[@]} ]]; then
        TOOLTIP="├─"+${TOOLTIP}
    else
        TOOLTIP="└─"+${TOOLTIP}
    fi
done

# vmstat 1 2|tail -1|awk '{print $15}'
# cat /proc/stat |grep cpu |tail -1|awk '{print ($5*100)/($2+$3+$4+$5+$6+$7+$8+$9+$10)}'|awk '{print "CPU Usage: " 100-$1}'
# awk '{u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t;} else print ($2+$4-u1) * 100 / (t-t1) "%"; }' <(grep 'cpu ' /proc/stat) <(sleep 1;grep 'cpu ' /proc/stat)
# grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage "%"}'
# echo "%CPU %MEM ARGS $(date)" && ps -e -o pcpu,pmem,args --sort=pcpu | cut -d" " -f1-5 | tail

echo -e "<click>xfce4-taskmanager &> /dev/null</click><img>$(get_img)</img>"
#echo -e "<bar>${PERCENTAGE}</bar>"
echo -e "<tool>${TOOLTIP}</tool>"

# ------------------------------------------------------------------------------
