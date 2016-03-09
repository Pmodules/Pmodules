#!/bin/bash

declare -r BOOTSTRAP_DIR=$(dirname "$0")

unset PMODULES_HOME
unset PMODULES_VERSION

source "${BOOTSTRAP_DIR}/Pmodules/libstd.bash"
source "${BOOTSTRAP_DIR}/config/environment.bash"

declare force='no'

while (( $# > 0 )); do
	case $1 in
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

#if [[ -n ${PMODULES_DIR} ]] && [[ "${PMODULES_DIR}" != "/" ]] && [[ -d "${PMODULES_DIR}" ]]; then
#	rm -rf "${PMODULES_DIR}"
#fi

build () {
	local -r name="$1"
	local -r version="$2"
	shift 2

	"${BOOTSTRAP_DIR}/Pmodules/modbuild" "${BOOTSTRAP_DIR}/${name}/build" --bootstrap --disable-cleanup "$@" "${version}" || \
		std::die 3 "Compiling '${name}' failed!"
}

if [[ ! -f "${PMODULES_HOME}/bin/base64" ]] || [[ ${force} == 'yes' ]]; then
	build coreutils "${COREUTILS_VERSION}"
fi

if [[ ! -f "${PMODULES_HOME}/bin/xgettext" ]] || [[ ${force} == 'yes' ]]; then
	build gettext "${GETTEXT_VERSION}"
fi

if [[ ! -f "${PMODULES_HOME}/bin/getopt" ]] || [[ ${force} == 'yes' ]]; then
	build getopt "${GETOPT_VERSION}"
fi

if [[ ! -f "${PMODULES_HOME}/bin/dialog" ]] || [[ ${force} == 'yes' ]]; then
	build dialog "${DIALOG_VERSION}"
fi

if [[ ! -f "${PMODULES_HOME}/bin/bash" ]] || [[ ${force} == 'yes' ]]; then
	build bash "4.3.30"
fi

if [[ ! -e "${PMODULES_HOME}/bin/tclsh" ]] || [[ ${force} == 'yes' ]]; then
	build Tcl "${TCL_VERSION}"
fi

if [[ ! -e "${PMODULES_HOME}/libexec/modulecmd.bin" ]] || [[ ${force} == 'yes' ]]; then
	build Modules "${MODULES_VERSION}" --compile && \
	cp -v "${PMODULES_TMPDIR}/build/Modules-${MODULES_VERSION}/modulecmd" "${PMODULES_HOME}/libexec/modulecmd.bin"
fi
echo "Done..."
