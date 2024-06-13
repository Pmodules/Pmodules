#!/bin/bash

set -x
set -o errexit
set -o pipefail
shopt -s nullglob

if (( $# == 0 )); then
	echo "Usage: $0 <dest-dir>" 1>&2 
	exit 1
fi

PREFIX="$1"
if [[ ! -d ${PREFIX} ]]; then
	echo "Destinstion directory '${PREFIX}' does not exist! Aborting..." 1>&2
	exit 2
fi
TMP_DIR="${PMODULES_TMPDIR:-/var/tmp/${USER}}"
DOWNLOADS_DIR="${PMODULES_DISTFILESDIR:-${TMP_DIR}/Downloads}"
SRC_DIR="${TMP_DIR}/$P-$V/src"
BUILD_DIR="${TMP_DIR}/$P-$V/build"
SRC_FILE="${DOWNLOADS_DIR}/${FNAME}"
UTILBIN_DIR='libexec'

declare -ix PB_ERR_ARG=1
declare -ix PB_ERR_SETUP=2
declare -ix PB_ERR_SYSTEM=3
declare -ix PB_ERR_DOWNLOAD=4
declare -ix PB_ERR_UNTAR=5
declare -ix PB_ERR_CONFIGURE=6
declare -ix PB_ERR_MAKE=7
declare -ix PB_ERR_PRE_INSTALL=8
declare -ix PB_ERR_INSTALL=9
declare -ix PB_ERR_POST_INSTALL=10
declare -ix PB_ERR=255
declare -ix NJOBS=4

pb_exit() {
        local -i ec=$?
        if [[ -n "${BASH_VERSION}" ]]; then
                local -i n=${#BASH_SOURCE[@]}
                local -r recipe_name="${BASH_SOURCE[n]}"
        else
                local -r recipe_name="${ZSH_ARGZERO}"
        fi
        echo -n "${recipe_name}: "
        if (( ec == 0 )); then
                echo "done!"
        elif (( ec == PB_ERR_ARG )); then
                echo "argument error!"
        elif (( ec == PB_ERR_SETUP )); then
                echo "error in setting everything up!"
        elif (( ec == PB_ERR_SYSTEM )); then
                echo "unexpected system error!"
        elif (( ec == PB_ERR_DOWNLOAD )); then
                echo "error in downloading the source file!"
        elif (( ec == PB_ERR_UNTAR )); then
                echo "error in un-taring the source file!"
        elif (( ec == PB_ERR_CONFIGURE )); then
                echo "error in configuring the software!"
        elif (( ec == PB_ERR_MAKE )); then
                echo "error in compiling the software!"
        elif (( ec == PB_ERR_PRE_INSTALL )); then
                echo "error in pre-installing the software!"
        elif (( ec == PB_ERR_INSTALL )); then
                echo "error in installing the software!"
        elif (( ec == PB_ERR_POST_INSTALL )); then
                echo "error in post-installing the software!"
        else
                echo "oops, unknown error!!!"
        fi
        exit ${ec}
}
#export -f pb_exit > /dev/null
trap "pb_exit" EXIT

#---
# download
mkdir -p "${DOWNLOADS_DIR}" || exit ${PB_ERR_SYSTEM}
test -r "${SRC_FILE}" || curl -L --output "$_" "${DOWNLOAD_URL}" || exit ${PB_ERR_DOWNLOAD}

strip_components="${strip_components:-1}"
#---
# unpack
mkdir -p "${SRC_DIR}" && cd "$_" || exit ${PB_ERR_SYSTEM}
tar --directory "${SRC_DIR}" --strip-components ${strip_components} -xv -f "${SRC_FILE}" || exit ${PB_ERR_UNTAR}

#---
# Local Variables:
# mode: shell-script-mode
# sh-basic-offset: 8
# End:
