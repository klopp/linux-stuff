#!/bin/bash

# ------------------------------------------------------------------------------
export LC_NUMERIC="C"

SELF_DIR=$(basename -- "${0}")
SELF_DIR=${SELF_DIR%.*}
CONF_IMG="$HOME/.config/${SELF_DIR%.*}/%s.png"
SELF_IMG="$(cd "$(dirname "${0}")" && pwd)/${SELF_DIR}/%s.png"
TOOLTIP_FILE="/tmp/${SELF_DIR}.tooltip"

TMAX="90"
GREEN="green"
CLICK="xfce4-taskmanager"

# ------------------------------------------------------------------------------
function usage
{
    cat << USAGE
Usage: $(basename "${0}") [options], where options are:
    -t, --tmax
        "Red" temperature (Celsius, default is 90)
    -c, --click
        Run on click, default: "${CLICK}"
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
function get_tooltip
{
    local tt="┌ <span weight='bold'>$(grep "model name" /proc/cpuinfo | cut -f2 -d ":" | uniq | sed -e 's/^[ \t]*//')</span>\n"
    local all_cpu=($(awk '/MHz/{print $4}' /proc/cpuinfo | cut -f1 -d"."))
    local all_temp=($(cat /sys/class/thermal/thermal_zone*/temp))
    local temperature=0

    local idx=0
    for mhz in "${all_cpu[@]}"; do
        tt+="├─ CPU ${idx}\t\t: ${mhz} MHz\n"
        (( idx++ ))
    done

    idx=0
    for temp in "${all_temp[@]}"; do
        grn="green"
        (( temp /= 1000 ))
        if (( "${temp}" > "${TMAX}" )); then
            grn="red"
            GREEN="red"
        fi
        (( idx++ ))
        tt+="├─ Core $((idx-1)) \t\t: <span weight='bold' fgcolor='${grn}'>${temp}</span>℃\n"
#        (( idx < ${#all_temp[@]} )) && tt+="\n"
    done
    tt+="└─ Usage\t\t: <span weight='bold' fgcolor='blue'>${1}</span>%\n"

    echo "${tt}"
}

# ------------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "${1}" in
        '-t' | '--tmax')
            TMAX=$(check_int "${2}")
            ((${TMAX})) || usage
            shift 2
            continue
        ;;
        '-c' | '--click')
            if [[ -z "${2}" ]]; then
                usage
            fi
            CLICK="${2}"
            shift 2
            continue
        ;;
        *)
            usage
        ;;
    esac
done

# ------------------------------------------------------------------------------
read CPU_FIRST_SUM CPU_I0 <<< $( awk '{print $1" "$2}' "${TOOLTIP_FILE}" 2>/dev/null)
if [[ -z "${CPU_I0}" ]]; then
    CPU_FIRST=($(head -n1 /proc/stat)) 
    CPU_FIRST_SUM="${CPU_FIRST[@]:1}" 
    CPU_I0=$((CPU_FIRST[4]))
    CPU_FIRST_SUM=$((${CPU_FIRST_SUM// /+}))
    sleep 1
fi

CPU_NOW=($(head -n1 /proc/stat)) 
CPU_SUM="${CPU_NOW[@]:1}" 
CPU_SUM=$((${CPU_SUM// /+})) 
echo "${CPU_SUM} ${CPU_NOW[4]}" > "${TOOLTIP_FILE}"

CPU_DELTA=$((CPU_SUM - CPU_FIRST_SUM)) 
CPU_IDLE=$((CPU_NOW[4] - CPU_I0))
CPU_USED=$((CPU_DELTA - CPU_IDLE)) 

PERCENTAGE=$((100 * CPU_USED / CPU_DELTA)) 

echo ()  { TOOLTIP=$*; }
get_tooltip ${PERCENTAGE}
unset -f echo

#TOOLTIP+="\n└─ Usage\t\t: <span weight='bold' fgcolor='blue'>${PERCENTAGE}</span>%\n"
echo -e "<click>${CLICK} &> /dev/null</click><img>$(get_img)</img>"
echo -e "<bar>${PERCENTAGE}</bar>"
echo -e "<tool>${TOOLTIP}</tool>"

# ------------------------------------------------------------------------------
