#!/bin/bash

declare -r BASE_DIR=$(cd "$(dirname $0)/.." && pwd)
declare -r BOOTSTRAP_DIR="${BASE_DIR}/Bootstrap"

source "${BASE_DIR}/lib/lib.bash"

unset PMODULES_HOME
unset PMODULES_VERSION

read_versions "${BOOTSTRAP_DIR}/Pmodules_version.conf"
source "/opt/psi/config/environment.bash"

#if [[ -n ${PMODULES_DIR} ]] && [[ "${PMODULES_DIR}" != "/" ]] && [[ -d "${PMODULES_DIR}" ]]; then
#	rm -rf "${PMODULES_DIR}"
#fi

build () {
	local -r name="$1"
	local -r version="$2"

	"${BOOTSTRAP_DIR}/${name}/build" --bootstrap --disable-cleanup "${version}" || \
		std::die 3 "Compiling '${name}' failed!"
}

if [[ ! -f "${PMODULES_HOME}/bin/base64" ]]; then
	build coreutils "${COREUTILS_VERSION}"
fi

if [[ ! -f "${PMODULES_HOME}/bin/xgettext" ]]; then
	build gettext "${GETTEXT_VERSION}"
fi

if [[ ! -f "${PMODULES_HOME}/bin/getopt" ]]; then
	build getopt "${GETOPT_VERSION}"
fi

if [[ ! -f "${PMODULES_HOME}/bin/dialog" ]]; then
	build dialog "${DIALOG_VERSION}"
fi

if [[ ! -f "${PMODULES_HOME}/bin/bash" ]]; then
	build bash "4.3.30"
fi

if [[ ! -e "${PMODULES_HOME}/bin/tclsh" ]]; then
	build Tcl "${TCL_VERSION}"
fi

if [[ ! -e "${PMODULES_HOME}/bin/modulecmd.tcl" ]]; then
	build Modules "${MODULES_VERSION}"
	mv -v "${PMODULES_HOME}/bin/modulecmd" "${PMODULES_HOME}/libexec/modulecmd.tcl"
fi
echo "Done..."
