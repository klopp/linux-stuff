#!/bin/bash

# ------------------------------------------------------------------------------
export LC_NUMERIC="C"

X="0"
Q="0"
DIR=""
EXE=""
TIMEOUT="600"
INTERVAL="10"
LAST=$(date +'%s' -d 'now')

# ------------------------------------------------------------------------------
function usage
{
    cat << USAGE
Usage: $(basename "${0}") [options], where options are:
    -t, --timeout
        Activity timeout (seconds, >= 10, default: ${TIMEOUT})
    -d, --dir, -p, --path
        Directory to watch
    -e, --exec
        Run on activity timeout
    -i, --interval
        Poll interval (seconds, >=10 and <= 60, default: ${INTERVAL})
    -q
        Be quiet
    -x
        Exit if executable return OK
    -xx
        Exit on any executable result
USAGE
    exit 1
}

# ------------------------------------------------------------------------------
function check_timeout
{
    CURRENT=$(date +'%s' -d 'now')
    (( DIFF = ${CURRENT} - ${LAST} ))
    if (( ${DIFF} >= ${TIMEOUT} )); then
        (("${Q}")) || echo "Timeout!"
        if [[ $? -eq 0 ]]; then
            if [[ ${X} -eq 1 ]]; then
                exit 0;
            fi                        
        elif [[ ${X} -eq 2 ]]; then
            exit 0;
        fi
        LAST=${CURRENT}
    fi
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
        '-t' | '--timeout')
            TIMEOUT=$(check_int "${2}")
            ((${TIMEOUT})) || usage
            shift 2
            continue
        ;;
        '-i' | '--interval')
            INTERVAL=$(check_int "${2}")
            ((${INTERVAL})) || usage
            shift 2
            continue
        ;;
        '-d' | '--dir' | '-p' | '--path')
            if [[ -z "${2}" ]]; then
                usage
            fi
            DIR="${2}"
            shift 2
            continue
        ;;
        '-e' | '--exec')
            if [[ -z "${2}" ]]; then
                usage
            fi
            EXE="${2}"
            shift 2
            continue
        ;;
        '-x')
            X="1"
            shift
            continue
        ;;
        '-xx')
            X="2"
            shift
            continue
        ;;
        '-q')
            Q="1"
            shift
            continue
        ;;
        *)
            usage
        ;;
    esac
done

if [[ -z "${DIR}" || -z "${EXE}" ]]; then
    usage
fi
if [[ ! -d "${DIR}" ]]; then
    echo "Can not find directory \"${DIR}\"!"
    usage
fi
if [[ ! -x "${EXE}" ]]; then
    echo "Can not execute \"${EXE}\"!"
    usage
fi
if (( ${TIMEOUT} < 10 )); then
    echo "Timeout too small, must be >= 10 seconds!"
    usage
fi
if (( ${INTERVAL} < 10 || ${INTERVAL} > 60 )); then
    echo "Interval must be >= 10 and <= 60seconds!"
    usage
fi

# ------------------------------------------------------------------------------
while true; do
    REPLY=""
    inotifywait -q -r -t ${INTERVAL} --timefmt="%Y-%m-%d %X" --format="%T" "${DIR}" | \
    while read -r -t ${INTERVAL}; do
        if [[ -n "${REPLY}" ]]; then
            LAST=$(date +'%s' -d "${REPLY}")
        fi
        check_timeout
    done
    if [[ -z "${REPLY}" ]]; then
        check_timeout
    fi
done
exit 0

# ------------------------------------------------------------------------------
