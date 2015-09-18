#!/bin/bash
declare    BOOTSTRAP_DIR=$(dirname "$0")
source "${BOOTSTRAP_DIR}/Pmodules/libstd.bash"
source "${BOOTSTRAP_DIR}/config/environment.bash"

declare -r BOOTSTRAP_DIR=$(std::get_abspath "${BOOTSTRAP_DIR}")
declare -r SRC_DIR="${BOOTSTRAP_DIR}/Pmodules"

std::read_versions "${BOOTSTRAP_DIR}/config/versions.conf"


echo "Installing to ${PMODULES_HOME} ..."
sed_cmd="s:@PMODULES_HOME@:${PMODULES_HOME}:g;"
sed_cmd+="s:@PMODULES_VERSION@:${PMODULES_VERSION}:g;"
sed_cmd+="s:@MODULES_VERSION@:${MODULES_VERSION}:g"
sed "${sed_cmd}" "${SRC_DIR}/modulecmd.bash.in" > "${SRC_DIR}/modulecmd.bash"
sed "${sed_cmd}" "${SRC_DIR}/modmanage.bash.in" > "${SRC_DIR}/modmanage.bash"
sed "${sed_cmd}" "${SRC_DIR}/environment.bash.in" > "${SRC_DIR}/environment.bash"

install -d -m 0755 "${PMODULES_HOME}/bin"
install -d -m 0755 "${PMODULES_HOME}/config"
install -d -m 0755 "${PMODULES_HOME}/init"
install -d -m 0755 "${PMODULES_HOME}/lib"

install -m 0755 "${SRC_DIR}/modulecmd"		"${PMODULES_HOME}/bin"
install -m 0755 "${SRC_DIR}/modulecmd.bash"	"${PMODULES_HOME}/libexec"
install -m 0755 "${SRC_DIR}/modmanage"		"${PMODULES_HOME}/bin"
install -m 0755 "${SRC_DIR}/modmanage.bash"	"${PMODULES_HOME}/libexec"
install -m 0755 "${SRC_DIR}/dialog.bash"	"${PMODULES_HOME}/bin"
install -m 0755 "${SRC_DIR}/modbuild"		"${PMODULES_HOME}/bin"

install -m 0755 "${SRC_DIR}/environment.bash"	"${PMODULES_HOME}/config/environment.bash.in"
install -m 0755 "${SRC_DIR}/profile.bash"	"${PMODULES_HOME}/config/profile.bash.in"

install -m 0644 "${SRC_DIR}/bash"		"${PMODULES_HOME}/init"
install -m 0644 "${SRC_DIR}/bash_completion"	"${PMODULES_HOME}/init"

install -m 0644 "${SRC_DIR}/libpmodules.bash"	"${PMODULES_HOME}/lib"
install -m 0644 "${SRC_DIR}/libpbuild.bash"	"${PMODULES_HOME}/lib"
install -m 0644 "${SRC_DIR}/libstd.bash"	"${PMODULES_HOME}/lib"
install -m 0644 "${SRC_DIR}/libmodules.tcl"	"${PMODULES_HOME}/lib/tcl8.6"

{
	cd "${PMODULES_HOME}/lib/tcl8.6"
	"${BOOTSTRAP_DIR}/mkindex.tcl"
}
