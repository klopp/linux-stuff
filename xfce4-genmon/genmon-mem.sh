#!/bin/bash

# ------------------------------------------------------------------------------
export LC_NUMERIC="C"

readonly IMGTPL="$HOME/xxx/Templates/icons/hw/ram-32-1-%s.png"
PMAX="80"
GREEN="green"

# ------------------------------------------------------------------------------
function usage
{
    cat << USAGE
Usage: $(basename "${0}") [options], where options are:
    -p, --proc
        "Red" used memory percentage (< 100, default is 80)
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
while [ $# -gt 0 ]; do
    case "${1}" in
        '-p' | '--pmax')
            shift
            PMAX=$(check_int "${1}")
            (( ${PMAX} < 100 && ${PMAX} > 0 )) || usage
            shift
            continue
        ;;
        *)
            usage
        ;;
    esac
done

# ------------------------------------------------------------------------------
TOTAL=$(cat   /proc/meminfo | cut -d '.' -f1 | awk '/MemTotal:/{print $2}')
FREE=$(cat    /proc/meminfo | cut -d '.' -f1 | awk '/MemFree:/{print $2}')
CACHED=$(cat  /proc/meminfo | cut -d '.' -f1 | awk '/^Ca/{print $2}')
BUFFERS=$(cat /proc/meminfo | cut -d '.' -f1 | awk '/Buffers:/{print $2}')

FREE=$(( ${FREE} + ${CACHED} + ${BUFFERS} ))
PERCENTAGE=$(( ((${TOTAL} - ${FREE}) * 100) / ${TOTAL} ))
TOTAL=$( numfmt --to iec --format "%.2f" $(( ${TOTAL} * 1024 )) )
FREE=$(  numfmt --to iec --format "%.2f" $(( ${FREE}  * 1024 )) )

if [ "${PERCENTAGE}" -gt "${PMAX}" ]; then
    GREEN="red"
fi

TOOLTIP="Total memory: ${TOTAL}\\nFree memory: ${FREE}\\nUsed: <span fgcolor='${GREEN}' weight='bold'>${PERCENTAGE}</span>%\\n"

echo -e "<click>xfce4-taskmanager &> /dev/null</click><img>$(printf ${IMGTPL} ${GREEN})</img>"
echo -e "<bar>${PERCENTAGE}</bar>"
echo -e "<tool>${TOOLTIP}</tool>"

# ------------------------------------------------------------------------------
