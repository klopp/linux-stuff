#!/bin/bash

# ------------------------------------------------------------------------------
export LC_NUMERIC="C"

SELF_DIR=$(basename -- "${0}")
SELF_DIR=${SELF_DIR%.*}
CONF_IMG="$HOME/.config/${SELF_DIR%.*}/%s.png"
SELF_IMG="$(cd "$(dirname "${0}")" && pwd)/${SELF_DIR}/%s.png"

PMAX="80"
GREEN="green"
CLICK="xfce4-taskmanager"

# ------------------------------------------------------------------------------
function usage
{
    cat << USAGE
Usage: $(basename "${0}") [options], where options are:
    -p, --proc
        "Red" used memory percentage (< 100, default is 80)
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
        '-p' | '--pmax')
            shift
            PMAX=$(check_int "${1}")
            (( ${PMAX} < 100 && ${PMAX} > 0 )) || usage
            shift
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
TOTAL=$(     cat /proc/meminfo | cut -d '.' -f1 | awk '/^MemTotal:/{print $2}')
FREE=$(      cat /proc/meminfo | cut -d '.' -f1 | awk '/^MemFree:/{print $2}')
CACHED=$(    cat /proc/meminfo | cut -d '.' -f1 | awk '/^Cached:/{print $2}')
SHARED=$(    cat /proc/meminfo | cut -d '.' -f1 | awk '/^Shmem:/{print $2}')
BUFFERS=$(   cat /proc/meminfo | cut -d '.' -f1 | awk '/^Buffers:/{print $2}')
AVAILABLE=$( cat /proc/meminfo | cut -d '.' -f1 | awk '/^MemAvailable:/{print $2}')
SW_TOTAL=$(  cat /proc/meminfo | cut -d '.' -f1 | awk '/^SwapTotal:/{print $2}')
SW_FREE=$(   cat /proc/meminfo | cut -d '.' -f1 | awk '/^SwapFree:/{print $2}')

PERCENTAGE=$(( ((${TOTAL} - ${AVAILABLE}) * 100) / ${TOTAL} ))
(( "${PERCENTAGE}" > "${PMAX}" )) && GREEN="red"

TOTAL=$(     numfmt --to iec --format "%.2f" $(( ${TOTAL}     * 1024 )) )
FREE=$(      numfmt --to iec --format "%.2f" $(( ${FREE}      * 1024 )) )
CACHED=$(    numfmt --to iec --format "%.2f" $(( ${CACHED}    * 1024 )) )
SHARED=$(    numfmt --to iec --format "%.2f" $(( ${SHARED}    * 1024 )) )
BUFFERS=$(   numfmt --to iec --format "%.2f" $(( ${BUFFERS}   * 1024 )) )
AVAILABLE=$( numfmt --to iec --format "%.2f" $(( ${AVAILABLE} * 1024 )) )
SW_TOTAL=$(  numfmt --to iec --format "%.2f" $(( ${SW_TOTAL}  * 1024 )) )
SW_FREE=$(   numfmt --to iec --format "%.2f" $(( ${SW_FREE}   * 1024 )) )

TOOLTIP="┌ <span weight='bold'>RAM</span>\n";
TOOLTIP+="├─ Total\t\t: ${TOTAL}\n"
TOOLTIP+="├─ Free\t\t\t: ${FREE}\n"
TOOLTIP+="├─ Shared\t\t: ${SHARED}\n"
TOOLTIP+="├─ Cached\t\t: ${CACHED}\n"
TOOLTIP+="├─ Buffers\t\t: ${BUFFERS}\n"
TOOLTIP+="└─ Available\t: <span weight='bold' fgcolor='${GREEN}'>${AVAILABLE}</span>\n"

TOOLTIP+="\n┌ <span weight='bold'>Swap</span>\n";
TOOLTIP+="├─ Total\t\t: ${SW_TOTAL}\n"
TOOLTIP+="└─ Free\t\t\t: ${SW_FREE}"

echo -e "<click>${CLICK} &> /dev/null</click><img>$(get_img)</img>"
echo -e "<bar>${PERCENTAGE}</bar>"
echo -e "<tool>${TOOLTIP}</tool>"

# ------------------------------------------------------------------------------
