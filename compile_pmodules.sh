#!/bin/bash

declare -r BOOTSTRAP_DIR=$(dirname "$0")

unset PMODULES_HOME
unset PMODULES_VERSION

source "${BOOTSTRAP_DIR}/Pmodules/libstd.bash"

declare force='no'

declare opts='--bootstrap'
while (( $# > 0 )); do
	case $1 in
		--disable-cleanup )
			opts+=" $1"
			;;
		--debug )
			opts+=" $1"
			;;
		-f | --force )
			force='yes'
			;;
		-* )
			std::die 1 "$1: illegal option"
			;;
		* )
			std::die 1 "No arguments are allowed."
			;;
	esac
	shift 1
done

std::read_versions "${BOOTSTRAP_DIR}/config/versions.conf"
source "${BOOTSTRAP_DIR}/config/environment.bash"
PMODULES_VERSION=''
declare -x PMODULES_VERSION
echo $PMODULES_VERSION

#if [[ -n ${PMODULES_DIR} ]] && [[ "${PMODULES_DIR}" != "/" ]] && [[ -d "${PMODULES_DIR}" ]]; then
#	rm -rf "${PMODULES_DIR}"
#fi

build () {
	local -r name="$1"
	local -r version="$2"
	shift 2

	"${BOOTSTRAP_DIR}/Pmodules/modbuild" "${BOOTSTRAP_DIR}/${name}/build" ${opts} "$@" "${version}" || \
		std::die 3 "Compiling '${name}' failed!"
}

if [[ ! -f "${PMODULES_HOME}/sbin/base64" ]] || [[ ${force} == 'yes' ]]; then
	build coreutils "${COREUTILS_VERSION}"
fi

if [[ ! -f "${PMODULES_HOME}/sbin/xgettext" ]] || [[ ${force} == 'yes' ]]; then
	build gettext "${GETTEXT_VERSION}"
fi

if [[ ! -f "${PMODULES_HOME}/bin/getopt" ]] || [[ ${force} == 'yes' ]]; then
	build getopt "${GETOPT_VERSION}"
fi

if [[ ! -f "${PMODULES_HOME}/sbin/bash" ]] || [[ ${force} == 'yes' ]]; then
	build bash "4.3.30"
fi

if [[ ! -e "${PMODULES_HOME}/sbin/tclsh" ]] || [[ ${force} == 'yes' ]]; then
	build Tcl "${TCL_VERSION}"
fi

if [[ ! -e "${PMODULES_HOME}/libexec/modulecmd.bin" ]] || [[ ${force} == 'yes' ]]; then
	build Modules "${MODULES_VERSION}" --compile
fi
echo "Done..."
