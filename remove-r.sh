#!/bin/bash

# ------------------------------------------------------------------------------
readonly FILES=".*[.]\(p.\|[it]?html\|php\|cgi\|t\|js\|s?css\|feature\|sql\|yml\|json\|txt|md|c|cpp|h\)$"
readonly QUIET=0
# ------------------------------------------------------------------------------
function process_file
{
    R=$(grep $'\r' "${1}")
    ((${QUIET})) || echo "${2}\"${1}\"..."
    if [ -n "${R}" ]; then
        TEMPFILE=$(mktemp)
        getfacl -p "${1}" > "${TEMPFILE}.acl"
        cat "${1}" | tr -d '\r' > "${TEMPFILE}"
        mv -f "${TEMPFILE}" "${1}"
        setfacl --restore "${TEMPFILE}.acl"
        rm "${TEMPFILE}.acl"
        ((${QUIET})) || echo "${2} all \\r removed"
    else
        ((${QUIET})) || echo "${2} no \\r found"
    fi   
}

# ------------------------------------------------------------------------------
if [ -z "${1}" ]; then
    echo "Usage: $(basename ${0}) {file|dir} [ {file|dir} ... ]"
    exit 1 
fi

while [ $# -gt 0 ]; do
    if [[ -d ${1} ]]; then
        ((${QUIET})) || echo "Directory \"${1}\""
        for FILE in $(find "${1}" -type f -regex "${FILES}"); do
            process_file ${FILE} " "
        done
    elif [[ -f ${1} ]]; then
        process_file ${1} ""
    fi
    shift
done

# ------------------------------------------------------------------------------
