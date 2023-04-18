#!/bin/bash

# ------------------------------------------------------------------------------
HDD="sdb2"
DIR="$HOME/${HDD}"
TIMEOUT="600"
LAST=$(date +'%s' -d 'now')

# ------------------------------------------------------------------------------
function check_timeout
{
    CURRENT=$(date +'%s' -d 'now')
    (( DIFF = ${CURRENT} - ${LAST} ))
    if (( ${DIFF} >= ${TIMEOUT} )); then
        echo "Timeout!"
        # на всякий случай проверим не держит ли кто каталог:
        LSOF=$(lsof "${DIR}" | awk 'NR>1 {print $2}' | sort -n | uniq)
        if [[ -z "${LSOF}" ]]; then
        # не держит - OK, размонтируем
            sudo umount -l -q "${DIR}"
            sudo cryptsetup luksClose ${HDD}
            exit 0;
        else
        # держит - продолжаем ждать
            echo "Directory ${DIR} used by:"
            echo -e "$(ps --no-headers -o command -p ${LSOF})"
            echo "Wait more..."
            LAST=${CURRENT}
        fi
    fi
}

# ------------------------------------------------------------------------------
while true; do
    REPLY=""
    inotifywait -q -r -t 10 --timefmt="%Y-%m-%d %X" --format="%T" "${DIR}" | \
    while read -r -t 10; do
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
