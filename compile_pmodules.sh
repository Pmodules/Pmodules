#!/bin/bash

declare -r BOOTSTRAP_DIR=$(dirname "$0")

unset PMODULES_HOME
unset PMODULES_VERSION

source "${BOOTSTRAP_DIR}/Pmodules/libstd.bash"
source "${BOOTSTRAP_DIR}/config/environment.bash"

std::read_versions "${BOOTSTRAP_DIR}/config/versions.conf"

#if [[ -n ${PMODULES_DIR} ]] && [[ "${PMODULES_DIR}" != "/" ]] && [[ -d "${PMODULES_DIR}" ]]; then
#	rm -rf "${PMODULES_DIR}"
#fi

build () {
	local -r name="$1"
	local -r version="$2"

	"${BOOTSTRAP_DIR}/Pmodules/modbuild" "${BOOTSTRAP_DIR}/${name}/build" --disable-cleanup "${version}" || \
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

if [[ ! -e "${PMODULES_HOME}/libexec/modulecmd.tcl" ]]; then
	build Modules "${MODULES_VERSION}" && \
	mv -v "${PMODULES_HOME}/bin/modulecmd" "${PMODULES_HOME}/libexec/modulecmd.tcl"
fi
echo "Done..."
