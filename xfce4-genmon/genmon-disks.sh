#!/bin/bash

# ------------------------------------------------------------------------------
export LC_NUMERIC="C"

SELF_DIR=$(basename -- "${0}")
SELF_DIR=${SELF_DIR%.*}
CONF_IMG="$HOME/.config/${SELF_DIR%.*}/%s.png"
SELF_IMG="$(cd "$(dirname "${0}")" && pwd)/${SELF_DIR}/%s.png"

DEV=""
PART="/home"
TMAX="50" 
GREEN="green"
CLICK="sudo gnome-disks"

# ------------------------------------------------------------------------------
function usage
{
    cat << USAGE
Usage: $(basename "${0}") [options], where options are:
    -d, --disk
        Disk letter (REQUIRED, "a" => "/dev/sda", "b" => "/dev/sdb", etc)
    -p, --part
        Disk partition (default is "/home")
    -t, --tmax
        "Red" temperature (Celsius, default is 50)
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
while [ $# -gt 0 ]; do
    case "${1}" in
        '-d' | '--disk')
            DEV="${2}"
            shift 2
            continue
        ;;
        '-p' | '--part')
            PART="${2}"
            shift 2
            continue
        ;;
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

if [ -z "${DEV}" ]; then
    usage
fi

# ------------------------------------------------------------------------------
TEMPERATURE=$( check_int $(sudo smartctl -A /dev/sd${DEV} | grep -i temperature | awk '{print $10}') )
if ((${TEMPERATURE} == 0 )); then
    TEMPERATURE="?"
    GREEN="red"
elif [ "${TEMPERATURE}" -gt "${TMAX}" ]; then
    GREEN="red"
fi

USED=$(  check_int $(df ${PART} 2>&1 | awk '/\/dev/{print $3}') )
TOTAL=$( check_int $(df ${PART} 2>&1 | awk '/\/dev/{print $2}') )
FREE="?"

if (( ${USED} < ${TOTAL} )); then 
    PERCENTAGE=$(( ${USED} * 100 / ${TOTAL} ))
    FREE=$(( ${TOTAL} - ${USED} ))
    TOTAL=$( numfmt --to iec --format "%.2f" $(( ${TOTAL} * 1024 )) )
    USED=$(  numfmt --to iec --format "%.2f" $(( ${USED}  * 1024 )) )
    FREE=$(  numfmt --to iec --format "%.2f" $(( ${FREE}  * 1024 )) )
else
    PERCENTAGE="?"
    TOTAL="?"
    USED="?"
    GREEN="red"
fi

TOOLTIP="┌ <span weight='bold' fgcolor='blue'>${PART}</span> on <span fgcolor='blue'>/dev/sd${DEV}</span>\n"
TOOLTIP+="├─ Total\t\t\t: ${TOTAL}\n"
TOOLTIP+="├─ Used\t\t\t: ${USED}\n"
TOOLTIP+="├─ Free\t\t\t\t: ${FREE}\n"
TOOLTIP+="└─ Temperature\t: <span weight='bold' fgcolor='$GREEN'>${TEMPERATURE}</span> ℃"

echo -e "<click>${CLICK} &> /dev/null</click><img>$(get_img)</img>"
echo -e "<bar>${PERCENTAGE}</bar>"
echo -e "<tool>${TOOLTIP}</tool>"

# ------------------------------------------------------------------------------
