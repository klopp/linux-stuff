#!/bin/bash

# ------------------------------------------------------------------------------
export LC_NUMERIC="C"

readonly IMGTPL="$HOME/xxx/Templates/icons/hw/ram-32-1-%s.png"
PMAX="80"
GREEN="green"

# ------------------------------------------------------------------------------
function req
{
    while [ $# -gt 0 ]; do
        if ! hash ${1} &> /dev/null; then
            echo "No required command: \"${1}\""
            exit 2
        fi
        shift
    done
}

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

req "cat" "awk" "cut" "numfmt"

# ------------------------------------------------------------------------------
TOTAL=$(     cat /proc/meminfo | cut -d '.' -f1 | awk '/^MemTotal:/{print $2}')
FREE=$(      cat /proc/meminfo | cut -d '.' -f1 | awk '/^MemFree:/{print $2}')
CACHED=$(    cat /proc/meminfo | cut -d '.' -f1 | awk '/^Cached:/{print $2}')
SHARED=$(    cat /proc/meminfo | cut -d '.' -f1 | awk '/^Shmem:/{print $2}')
BUFFERS=$(   cat /proc/meminfo | cut -d '.' -f1 | awk '/^Buffers:/{print $2}')
AVAILABLE=$( cat /proc/meminfo | cut -d '.' -f1 | awk '/^MemAvailable:/{print $2}')

TOTAL=$(     numfmt --to iec --format "%.2f" $(( ${TOTAL}     * 1024 )) )
FREE=$(      numfmt --to iec --format "%.2f" $(( ${FREE}      * 1024 )) )
CACHED=$(    numfmt --to iec --format "%.2f" $(( ${CACHED}    * 1024 )) )
SHARED=$(    numfmt --to iec --format "%.2f" $(( ${SHARED}    * 1024 )) )
BUFFERS=$(   numfmt --to iec --format "%.2f" $(( ${BUFFERS}   * 1024 )) )
AVAILABLE=$( numfmt --to iec --format "%.2f" $(( ${AVAILABLE} * 1024 )) )

PERCENTAGE=$(( ((${TOTAL} - ${AVAILABLE}) * 100) / ${TOTAL} ))
if [ "${PERCENTAGE}" -gt "${PMAX}" ]; then
    GREEN="red"
fi

TOOLTIP="┌ RAM\n";
TOOLTIP+="├─ Total\t\t: ${TOTAL}\n"
TOOLTIP+="├─ Free\t\t\t: ${FREE}\n"
TOOLTIP+="├─ Shared\t\t: ${SHARED}\n"
TOOLTIP+="├─ Cached\t\t: ${CACHED}\n"
TOOLTIP+="├─ Buffers\t\t: ${BUFFERS}\n"
TOOLTIP+="└─ Available\t: ${AVAILABLE}\n"

echo -e "<click>xfce4-taskmanager &> /dev/null</click><img>$(printf ${IMGTPL} ${GREEN})</img>"
echo -e "<bar>${PERCENTAGE}</bar>"
echo -e "<tool>${TOOLTIP}</tool>"

# ------------------------------------------------------------------------------
