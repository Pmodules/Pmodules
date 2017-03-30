#!/bin/bash
declare    BOOTSTRAP_DIR=$(dirname "$0")

unset PMODULES_HOME
unset PMODULES_VERSION

source "${BOOTSTRAP_DIR}/Pmodules/libstd.bash"

declare -r BOOTSTRAP_DIR=$(std::get_abspath "${BOOTSTRAP_DIR}")
declare -r SRC_DIR="${BOOTSTRAP_DIR}/Pmodules"

std::read_versions "${BOOTSTRAP_DIR}/config/versions.conf"

while (( $# > 0 )); do
	case $1 in
	--install-root )
		PMODULES_ROOT="$2"
		shift 1
		;;
	--install-root=* )
		PMODULES_ROOT="${1#*=}"
		;;
	-* )
		echo "Unknown option: $1" 1>&2
		exit 1
		;;
	* )
		echo "Invalid argument: $1" 1>&2
		exit 1
		;;
	esac
	shift 1
done

if [[ ! -d "${PMODULES_ROOT}" ]]; then
	read -p "The requested root directory does not exist. Create it? [y|N] " -n 1 ans
	case ${ans} in 
	y | Y )
		mkdir -p "${PMODULES_ROOT}"
		;;
	* )
		echo "Aborting ..." 1>&2
		exit 2
		;;
	esac
fi

source "${BOOTSTRAP_DIR}/config/environment.bash"

###
#
# begin installation
#
echo "Installing to ${PMODULES_HOME} ..."
sed_cmd="s:@PMODULES_HOME@:${PMODULES_HOME}:g;"
sed_cmd+="s:@PMODULES_VERSION@:${PMODULES_VERSION}:g;"
sed_cmd+="s:@MODULES_VERSION@:${MODULES_VERSION}:g;"
sed_cmd+="s:@PMODULES_DISTFILESDIR@:${PMODULES_DISTFILESDIR}:g;"
sed_cmd+="s:@PMODULES_TMPDIR@:${PMODULES_TMPDIR}:g;"

sed "${sed_cmd}" "${SRC_DIR}/modulecmd.bash.in"   > "${SRC_DIR}/modulecmd.bash"
sed "${sed_cmd}" "${SRC_DIR}/modulecmd.tcl.in"    > "${SRC_DIR}/modulecmd.tcl"
sed "${sed_cmd}" "${SRC_DIR}/modmanage.bash.in"   > "${SRC_DIR}/modmanage.bash"
sed "${sed_cmd}" "${SRC_DIR}/environment.bash.in" > "${SRC_DIR}/environment.bash"

install -d -m 0755 "${PMODULES_HOME}/bin"
install -d -m 0755 "${PMODULES_HOME}/config"
install -d -m 0755 "${PMODULES_HOME}/init"
install -d -m 0755 "${PMODULES_HOME}/lib"

install -m 0755 "${SRC_DIR}/modulecmd"		"${PMODULES_HOME}/bin"
install -m 0755 "${SRC_DIR}/modulecmd.bash"	"${PMODULES_HOME}/libexec"
install -m 0755 "${SRC_DIR}/modulecmd.tcl"	"${PMODULES_HOME}/libexec"
install -m 0755 "${SRC_DIR}/modmanage"		"${PMODULES_HOME}/bin"
install -m 0755 "${SRC_DIR}/modmanage.bash"	"${PMODULES_HOME}/libexec"
install -m 0755 "${SRC_DIR}/modbuild"		"${PMODULES_HOME}/bin"

install -m 0755 "${SRC_DIR}/environment.bash"	"${PMODULES_HOME}/config/environment.bash.sample"
install -m 0755 "${SRC_DIR}/profile.bash"	"${PMODULES_HOME}/config/profile.bash.sample"

if [[ ! -e "${PMODULES_ROOT}/${PMODULES_CONFIG_DIR}" ]]; then
	mkdir -p "${PMODULES_ROOT}/${PMODULES_CONFIG_DIR}"
fi

if [[ ! -e "${PMODULES_ROOT}/${PMODULES_CONFIG_DIR}/environment.bash" ]]; then
        install -m 0755 "${SRC_DIR}/environment.bash"	"${PMODULES_ROOT}/${PMODULES_CONFIG_DIR}/environment.bash"
fi

if [[ ! -e "${PMODULES_ROOT}/${PMODULES_CONFIG_DIR}/profile.bash" ]]; then
	install -m 0755 "${SRC_DIR}/profile.bash"	"${PMODULES_ROOT}/${PMODULES_CONFIG_DIR}/profile.bash"
fi

mkdir -p "${PMODULES_ROOT}/Tools/modulefiles"
mkdir -p "${PMODULES_ROOT}/Libraries/modulefiles"

install -m 0644 "${SRC_DIR}/bash"		"${PMODULES_HOME}/init"
install -m 0644 "${SRC_DIR}/bash_completion"	"${PMODULES_HOME}/init"

install -m 0644 "${SRC_DIR}/libpmodules.bash"	"${PMODULES_HOME}/lib"
install -m 0644 "${SRC_DIR}/libpbuild.bash"	"${PMODULES_HOME}/lib"
install -m 0644 "${SRC_DIR}/libstd.bash"	"${PMODULES_HOME}/lib"
install -m 0755 -d				"${PMODULES_HOME}/lib/Pmodules"
install -m 0644 "${SRC_DIR}/libmodules.tcl"	"${PMODULES_HOME}/lib/Pmodules"

{
	cd "${PMODULES_HOME}/lib/Pmodules"
	"${BOOTSTRAP_DIR}/mkindex.tcl"
}
