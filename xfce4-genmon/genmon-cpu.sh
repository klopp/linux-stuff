#!/bin/bash

# ------------------------------------------------------------------------------
export LC_NUMERIC="C"

SELF_DIR=$(basename -- "${0}")
SELF_DIR=${SELF_DIR%.*}
CONF_IMG="$HOME/.config/${SELF_DIR%.*}/%s.png"
SELF_IMG="$(cd "$(dirname "${0}")" && pwd)/${SELF_DIR}/%s.png"

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
        Run on click, default: xfce4-taskmanager
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
        '-t' | '--tmax')
            TMAX=$(check_int "${2}")
            ((${TMAX})) || usage
            shift 2
            continue
        ;;
        '-c' | '--click')
            CLICK="${2}"
            if [[ -z "${CLICK}" ]]; then
                usage
            fi
            shift 2
            continue
        ;;
        *)
            usage
        ;;
    esac
done

# ------------------------------------------------------------------------------
TOOLTIP="┌ <span weight='bold'>$(grep "model name" /proc/cpuinfo | cut -f2 -d ":" | uniq | sed -e 's/^[ \t]*//')</span>\n"
ALL_CPU=($(awk '/MHz/{print $4}' /proc/cpuinfo | cut -f1 -d"."))
ALL_TEMP=($(cat /sys/class/thermal/thermal_zone*/temp))
TEMPERATURE=0

IDX=0
for mhz in "${ALL_CPU[@]}"; do
    TOOLTIP+="├─ CPU ${IDX}\t\t: ${mhz} MHz\n"
    (( IDX+=1 ))
done

IDX=0
for temp in "${ALL_TEMP[@]}"; do
    grn="green"
    (( temp /= 1000 ))
    if (( "${temp}" > "${TMAX}" )); then
        grn="red"
        GREEN="red"
    fi
    (( IDX+=1 ))
    tchar="├─"
    (( "${IDX}" >= "${#ALL_TEMP[@]}" )) && tchar="└─" 
    TOOLTIP+="${tchar} Core ${IDX} \t\t: <span weight='bold' fgcolor='${grn}'>${temp}</span> ℃\n"
done

echo -e "<click>${CLICK} &> /dev/null</click><img>$(get_img)</img>"
echo -e "<tool>${TOOLTIP}</tool>"

# ------------------------------------------------------------------------------
