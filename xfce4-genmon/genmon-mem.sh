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
function mem_fmt
{
    if [[ -n "${1}" ]]; then
        echo $( numfmt --to iec --format "%.2f" $((${1} * 1024)) )
    else
        echo ""
    fi
}

# ------------------------------------------------------------------------------
while read -r; do 
    [ -n "${TOTAL}" ]     || TOTAL=$(awk '/^MemTotal:/{print $2}'         <<< ${REPLY})
    [ -n "${AVAILABLE}" ] || AVAILABLE=$(awk '/^MemAvailable:/{print $2}' <<< ${REPLY})

    [ -n "${FREE}" ]     || FREE=$(    mem_fmt $(awk '/^MemFree:/{print $2}'   <<< ${REPLY}))
    [ -n "${BUFFERS}" ]  || BUFFERS=$( mem_fmt $(awk '/^Buffers:/{print $2}'   <<< ${REPLY}))
    [ -n "${CACHED}" ]   || CACHED=$(  mem_fmt $(awk '/^Cached:/{print $2}'    <<< ${REPLY}))
    [ -n "${SHARED}" ]   || SHARED=$(  mem_fmt $(awk '/^Shmem:/{print $2}'     <<< ${REPLY}))
    [ -n "${SW_TOTAL}" ] || SW_TOTAL=$(mem_fmt $(awk '/^SwapTotal:/{print $2}' <<< ${REPLY}))
    [ -n "${SW_FREE}" ]  || SW_FREE=$( mem_fmt $(awk '/^SwapFree:/{print $2}'  <<< ${REPLY}))
done <<< $(cat /proc/meminfo)

PERCENTAGE=$(( ((${TOTAL} - ${AVAILABLE}) * 100) / ${TOTAL} ))
(( "${PERCENTAGE}" > "${PMAX}" )) && GREEN="red"

TOTAL=$(mem_fmt ${TOTAL})
AVAILABLE=$(mem_fmt ${AVAILABLE})

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
