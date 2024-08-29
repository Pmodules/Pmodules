#!/bin/bash

#.............................................................................
# disable auto-echo feature of 'cd'
unset CDPATH

#.............................................................................
# define constants
declare -r FNAME_RDEPS='.dependencies'
declare -r FNAME_IDEPS='.install_dependencies'

# relative path of documentation
# abs. path is "${PREFIX}/${_docdir}/${module_name}"
declare -r  _DOCDIR='share/doc'

declare -a SOURCE_URLS=()
declare -a SOURCE_SHA256_SUMS=()
declare -a SOURCE_NAMES=()
declare -a SOURCE_STRIP_DIRS=() 
declare -a SOURCE_UNPACKER=()
declare -A SOURCE_UNPACK_DIRS=()
declare -ax CONFIGURE_ARGS=()
declare -a PATCH_FILES=()
declare -a PATCH_STRIPS=()
declare -- PATCH_STRIP_DEFAULT='1'
declare -- configure_with='auto'
declare -- SRC_DIR=''
declare -- BUILD_DIR=''
declare -- is_subpkg='no'

declare -i group_depth=0

declare -- COMPILER=''
declare -- MPI=''

#.............................................................................
#
# Exit script on errror.
#
# $1	exit code
#
#set -o errexit

_error_handler() {
	local -i ec=$?

	std::die ${ec} "Oops"
}
readonly -f _error_handler

trap "_error_handler" ERR

#..............................................................................
#
# write number of cores to stdout
#
_get_num_cores() {
	case "${KernelName}" in
	Linux )
		${grep} -c ^processor /proc/cpuinfo
		;;
	Darwin )
		${sysctl} -n hw.ncpu
		;;
	* )
		std::die 1 "OS ${KernelName} is not supported\n"
		;;
	esac
}
readonly -f _get_num_cores

#..............................................................................
# global variables which can be set/overwritten by command line args
# and their corresponding functions
#
declare force_rebuild='no'
pbuild.force_rebuild() {
	force_rebuild="$1"
}
readonly -f pbuild.force_rebuild

declare dry_run=''
pbuild.dry_run() {
	dry_run="$1"
}
readonly -f pbuild.dry_run

declare enable_cleanup_build=''
pbuild.enable_cleanup_build() {
	enable_cleanup_build="$1"
}
readonly -f pbuild.enable_cleanup_build

declare enable_cleanup_src=''
pbuild.enable_cleanup_src() {
	enable_cleanup_src="$1"
}
readonly -f pbuild.enable_cleanup_src

declare build_target=''
pbuild.build_target() {
	build_target="$1"
}
readonly -f pbuild.build_target

declare opt_update_modulefiles=''
pbuild.update_modulefiles() {
	opt_update_modulefiles="$1"
}
readonly -f pbuild.update_modulefiles

pbuild.set_prefix(){
	PREFIX="$1"
	is_subpkg='yes'
}

# number of parallel make jobs
declare -i JOBS=0
pbuild.jobs() {
	if (( $1 == 0 )); then
		JOBS=$(_get_num_cores)
		(( JOBS > 10 )) && JOBS=10 || :
	else
        	JOBS="$1"
	fi
}
readonly -f pbuild.jobs

declare system=''
pbuild.system() {
        system="$1"
}
readonly -f pbuild.system

declare verbose=''
pbuild.verbose() {
        verbose="$1"
}
readonly -f pbuild.verbose


#******************************************************************************
#
# function in the "namespace" (with prefix) 'pbuild::' can be used in
# build-scripts
#

###############################################################################
#
# general functions
#

#..............................................................................
#
# Install module in given group.
#
# Note:
#	This function is deprecated with YAML module configuration files.
#
# Arguments:
#	$1: group
#
pbuild::add_to_group() {
	if (( $# == 0 )); then
		std::die 42 \
                         "%s " "${module_name}/${module_version}:" \
                         "${FUNCNAME[0]}: missing group argument."
	fi
	if (( $# > 1 )); then
		std::die 42 \
                         "%s " "${module_name}/${module_version}:" \
                         "${FUNCNAME[0]}: only one argument is allowed."
	fi
	std::info \
		"Using ${FUNCNAME[0]} is deprecated with YAML module configuration files."
	pbuild.add_to_group "$@"
}
readonly -f pbuild::add_to_group

declare -gx GROUP=''
pbuild.add_to_group(){
	GROUP="$1"
}
readonly -f pbuild.add_to_group

#..............................................................................
#
# Test whether a module with the given name is available. If yes, return
# release
#
# Arguments:
#   $1: module name
#   $2: optional variable name to return release
#
# Notes:
#   The passed module name must be module/version!
#
# Exit codes:
#   0 if module/version is available
#   1 otherwise
#
pbuild::module_is_avail() {
	local -- name=''
	local -- release=''
	while read -r name release; do
		if [[ "${name}" == "$1" || "${name}" == "${1}.lua" ]]; then
			if (( $# > 1 )); then
				local -n _result="$2"
				_result="${release}"
			fi
			return 0
		fi
	done < <(${modulecmd} bash avail -a -m "$1" 2>&1 1>/dev/null)
	return 1
}
readonly -f pbuild::module_is_avail

#..............................................................................
#
# compare two version numbers
#
# pbuild::version_compare
#	- returns 0 if the version numbers are equal
#	- returns 1 if first version number is higher
#	- returns 2 if second version number is higher
#
# pbuild::version_lt
#	- returns 0 if second version number is higher
# pbuild::version_le
#	- returns 0 if second version number is higher or equal
# pbuild::version_gt
#	- returns 0 if first version number is higher
# pbuild::version_ge
#	- returns 0 if first version number is higher or equal
# pbuild::version_eq
#	- returns 0 if version numbers are equal
#
# otherwise a value != 0 is returned
#
# Arguments:
#	$1 first version number
#	$2 second version number
#
# Note:
#	Original implementation found on stackoverflow:
# https://stackoverflow.com/questions/4023830/how-to-compare-two-strings-in-dot-separated-version-format-in-bash
#
pbuild::version_compare () {
        is_uint() {
                [[ $1 =~ ^[0-9]+$ ]]
        }

        [[ "$1" == "$2" ]] && return 0
	local ver1 ver2
        IFS='.' read -r -a ver1 <<<"$1"
        IFS='.' read -r -a ver2 <<<"$2"

        # fill empty fields in ver1 with zeros
        local i
        for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
                ver1[i]=0
        done
        for ((i=0; i<${#ver1[@]}; i++)); do
                [[ -z ${ver2[i]} ]] && ver2[i]=0
                if is_uint "${ver1[i]}" && is_uint "${ver2[i]}"; then
                        ((10#${ver1[i]} > 10#${ver2[i]})) && return 1
                        ((10#${ver1[i]} < 10#${ver2[i]})) && return 2
                else
                        [[ ${ver1[i]} > ${ver2[i]} ]] && return 1
                        [[ ${ver1[i]} < ${ver2[i]} ]] && return 2
                fi
        done
        return 0
}
readonly -f pbuild::version_compare

pbuild::version_lt() {
	if (( $# == 1 )); then
		local vers1="${V_PKG}"
		local vers2="$1"
	else
		local vers1="$1"
		local vers2="$2"
	fi
        pbuild::version_compare "${vers1}" "${vers2}"
        (( $? == 2 ))
}
readonly -f pbuild::version_lt

pbuild::version_le() {
	if (( $# == 1 )); then
		local vers1="${V_PKG}"
		local vers2="$1"
	else
		local vers1="$1"
		local vers2="$2"
	fi
        pbuild::version_compare "${vers1}" "${vers2}"
        local -i exit_code=$?
        (( exit_code == 0 || exit_code == 2 ))
}
readonly -f pbuild::version_le

pbuild::version_gt() {
	if (( $# == 1 )); then
		local vers1="${V_PKG}"
		local vers2="$1"
	else
		local vers1="$1"
		local vers2="$2"
	fi
        pbuild::version_compare "${vers1}" "${vers2}"
        (( $? == 1 ))
        local -i exit_code=$?
        (( exit_code == 1 ))
}
readonly -f pbuild::version_gt

pbuild::version_ge() {
	if (( $# == 1 )); then
		local vers1="${V_PKG}"
		local vers2="$1"
	else
		local vers1="$1"
		local vers2="$2"
	fi
        pbuild::version_compare "${vers1}" "${vers2}"
        (( $? == 1 ))
        local -i exit_code=$?
        (( exit_code == 0 || exit_code == 1 ))
}
readonly -f pbuild::version_gt

pbuild::version_eq() {
	if (( $# == 1 )); then
		local vers1="${V_PKG}"
		local vers2="$1"
	else
		local vers1="$1"
		local vers2="$2"
	fi
        pbuild::version_compare "${vers1}" "${vers2}"
}
readonly -f pbuild::version_eq

#..............................................................................
#
# Check whether the loaded compiler is supported.
#
# Arguments:
#   $@: supported compiler (like GCC, Intel, PGI).
#       Default is all.
#
pbuild::supported_compilers() {
	std::info \
		"Using ${FUNCNAME[0]} is deprecated with YAML module configuration files."
	pbuild.supported_compilers "$@"
}
readonly -f pbuild::supported_compilers

declare SUPPORTED_COMPILERS=()
pbuild.supported_compilers(){
	SUPPORTED_COMPILERS+=( "$@" )
}
readonly -f pbuild.supported_compilers

#..............................................................................
#
# Check whether the script is running on a supported OS.
#
# Arguments:
#   $@: supported opertating systems (something like RHEL6, macOS10.14, ...).
#       Default is all.
#
pbuild::supported_systems() {
	std::info \
		"Using ${FUNCNAME[0]} is deprecated with YAML module configuration files."
	pbuild.supported_systems "$@"
}
readonly -f pbuild::supported_systems

declare SUPPORTED_SYSTEMS=()
pbuild.supported_systems() {
	SUPPORTED_SYSTEMS+=( "$@" )
}
readonly -f pbuild.supported_systems

#..............................................................................
#
pbuild::use_flag() {
	[[ "${USE_FLAGS}" == *:${1}:* ]]
}
readonly -f pbuild::use_flag

##############################################################################
#
# functions to prepare the sources

#..............................................................................
#
# Set the download URL and name of downloaded file.
#
# Arguments:
#	$1	download URL
#	$2	optional file-name (of)
pbuild::set_download_url() {
	std::info \
		"Using ${FUNCNAME[0]} is deprecated with YAML module configuration files."
	local -i _i=${#SOURCE_URLS[@]}
	SOURCE_URLS[_i]="$1"
	if (( $# > 1 )); then
		SOURCE_NAMES[_i]="${2:-${1##*/}}"
	else
		SOURCE_NAMES[_i]="${1##*/}"
	fi
	SOURCE_STRIP_DIRS[_i]='1'
}
readonly -f pbuild::set_download_url

pbuild.set_urls(){
	local -i _i=${#SOURCE_URLS[@]}
	SOURCE_URLS[_i]="$1"
	SOURCE_NAMES[_i]="$2"
	SOURCE_STRIP_DIRS[_i]="$3"
	SOURCE_UNPACKER[_i]="$4"
}

#..............................................................................
#
# Set hash sum for file.
#
# Arguments:
#	$1	filen-name:hash-sum
#
# :FIXME:
#	Maybe we should use a dictionary in the future.
#
pbuild::set_sha256sum() {
	std::info \
		"Using ${FUNCNAME[0]} is deprecated with YAML module configuration files."
	SOURCE_SHA256_SUMS+=("$1")
}
readonly -f pbuild::set_sha256sum

#..............................................................................
#
# Unpack file $1 in directory $2
#
# Arguments:
#	$1	file-name
#	$2	directory
#
pbuild::set_unpack_dir() {
	SOURCE_UNPACK_DIRS[$1]="$2"
}
readonly -f pbuild::set_unpack_dir

#..............................................................................
#
pbuild::add_patch() {
	std::info \
		"Using ${FUNCNAME[0]} is deprecated with YAML module configuration files."
	[[ -z "$1" ]] && \
		std::die 1 \
			 "%s " "${module_name}/${module_version}:" \
			 "${FUNCNAME[0]}: missing argument!"
	PATCH_FILES+=( "$1" )
	if (( $# >= 2 )); then
		PATCH_STRIPS+=( "$2" )
	else
		PATCH_STRIPS+=( "${PATCH_STRIP_DEFAULT}" )
	fi
}
readonly -f pbuild::add_patch

pbuild.add_patch_files(){
	local -- arg=''
	for arg in "$@"; do
		[[ -z "${arg}" ]] && continue
 		if [[ ${arg} == *:* ]]; then
			PATCH_FILES+=( "${arg%%:*}" )
			PATCH_STRIPS+=( "${arg##*:}" )
		else
			PATCH_FILES+=( "${arg}" )
			PATCH_STRIPS+=( "${PATCH_STRIP_DEFAULT}" )
		fi
	done
}
readonly -f pbuild.add_patch_files

#..............................................................................
#
pbuild::set_default_patch_strip() {
	std::info \
		"Using ${FUNCNAME[0]} is deprecated with YAML module configuration files."
	[[ -n "$1" ]] || \
		std::die 1 \
			 "%s " "${module_name}/${module_version}:" \
			 "${FUNCNAME[0]}: missing argument!"

	PATCH_STRIP_DEFAULT="$1"
}
readonly -f pbuild::set_default_patch_strip

#..............................................................................
#
pbuild::unpack(){
	local -r fname="$1"
	local -r dir="${2:-${SRC_DIR}}"
	local -r strip="${3:-1}"
	local -r unpacker="${4:-${tar}}"
	case "${unpacker}" in
		tar )
			${tar} \
				--directory="${dir}" \
				-xv \
				--strip-components "${strip}" \
				-f "${fname}"
			;;
		7z )
			${sevenz} \
				x \
				-y \
				-o"${dir}" \
				"${fname}"
			;;
		none )
			:
			;;
		* )
			std::die 1 "Unsupportet tool for unpacking -- '${unpacker}'"
			;;
	esac
}

#..............................................................................
#
# extract sources. For the time being only tar-files are supported.
#
pbuild::prep() {
	#......................................................................
	#
	# download the source file if not already downloaded and validate
	# checksum (if known).
	# Abort on any error!
	#
	# Arguments:
	#	$1	reference varibale to return result
	#	$2	download URL
	#	$3	save downloaded file with this name. If the empty
	#		string is passed, derive file name from URL
	#	$4...	directories the source file might be already in. If the
	#		file does not exist in one of these directories, it
	#		is downloaded and stored in the first given directory.
	#
	download_source_file() {
		download_with_curl() {
			local -r output="$1"
			local -r url="$2"
			${curl} \
				--location \
				--fail \
				--output "${output}" \
				"${url}"
			# :FIXME: How to handle insecure downloads? 
			#if (( $? != 0 )); then
			#	curl \
			#		--insecure \
			#		--output "${output}" \
			#		"${url}"
			#fi
		}

		check_hash_sum() {
			local -r fname="$1"
			local -r expected_hash_sum="$2"
			local hash_sum=''

			hash_sum=$(${sha256sum} "${fname}" | awk '{print $1}')
			test "${hash_sum}" == "${expected_hash_sum}" || \
				std::die 42 \
					 "%s " \
					 "${module_name}/${module_version}:" \
					 "hash-sum missmatch for file '${fname}'!"
		}

		local -n _result="$1"
		local -r url="$2"
		local    fname="$3"
		shift 3
		dirs+=( "$@" )

		[[ -n "${fname}" ]] || fname="${url##*/}"
		local dir=''
		dirs+=( 'not found' )
		for dir in "${dirs[@]}"; do
			[[ -r "${dir}/${fname}" ]] && break
		done
		if [[ "${dir}" == 'not found' ]]; then
			dir="${dirs[0]}"
			download_with_curl "${dir}/${fname}" "${url}" || \
				std::die 42 \
					 "%s " \
					 "${module_name}/${module_version}:" \
					 "downloading source file '${fname}' failed!"
		fi
		_result="${dir}/${fname}"
		[[ -r "${_result}" ]] || \
			std::die 42 \
				 "%s " \
				 "${module_name}/${module_version}:" \
				 "source file '${_result}' is not readable!"

		local -- sha256_sum=''
		if [[ "${opt_yaml}" == 'yes' ]]; then
			if [[ -v SHASUMS[${fname}] ]]; then
				sha256_sum="${SHASUMS[${fname}]}"
			fi
		else
			local hash=''
			for hash in "${SOURCE_SHA256_SUMS[@]}"; do
				if [[ ${hash} =~ $fname: ]]; then
					sha256_sum="${hash#*:}"
					break
				fi
			done
		fi
		if [[ -n "${sha256_sum}" ]]; then
			check_hash_sum "${dir}/${fname}" "${sha256_sum}"
			std::info "${module_name}/${module_version}: SHA256 hash sum is OK ..." 
		else
			std::info "${module_name}/${module_version}: SHA256 hash sum missing NOK ..." 
		fi
	}

	unpack() {
		local -r fname="$1"
		local -r dir="$2"
		local -r strip="$3"
		local -r unpacker="$4"
		{
			mkdir -p "${dir}"
			pbuild::unpack "${fname}" "${dir}" "${strip}" "${unpacker}"
		} || {
			${rm} -f "${fname}"
			std::die 4 \
				 "%s " \
				 "${module_name}/${module_version}:" \
				 "cannot unpack sources!"
		}
	}

	patch_sources() {
		cd "${SRC_DIR}"
		local i=0
		for ((_i = 0; _i < ${#PATCH_FILES[@]}; _i++)); do
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"Appling patch '${PATCH_FILES[_i]}' ..."
			local -i strip_val="${PATCH_STRIPS[_i]:-${PATCH_STRIP_DEFAULT}}"
			${patch} -p${strip_val} < "${BUILDBLOCK_DIR}/${PATCH_FILES[_i]}" || \
				std::die 4 \
					 "%s " \
					 "${module_name}/${module_version}:" \
					 "error patching sources!"
		done
	}
	(( ${#SOURCE_URLS[@]} == 0 )) && return 0
	${mkdir} -p "${PMODULES_DISTFILESDIR}"
	local i=0
	local source_fname
	for ((i = 0; i < ${#SOURCE_URLS[@]}; i++)); do
		download_source_file \
			source_fname \
			"${SOURCE_URLS[i]}" \
			"${SOURCE_NAMES[i]}" \
			"${PMODULES_DISTFILESDIR}" \
			"${BUILDBLOCK_DIR}" ||
			std::die 4 \
				 "%s " "${module_name}/${module_version}:" \
				 "sources for not found."
		local dir=''
		local key="${SOURCE_NAMES[i]}"
		if [[ -v SOURCE_UNPACK_DIRS[${key}] ]]; then
			dir="${SOURCE_UNPACK_DIRS[${key}]}"
		else
			dir="${SRC_DIR}"
		fi
		local strip_dirs="${SOURCE_STRIP_DIRS[i]}"
		local unpacker="${SOURCE_UNPACKER[i]}"
		unpack "${source_fname}" "${dir}" "${strip_dirs}" "${unpacker}"
	done
	patch_sources
	# create build directory
	${mkdir} -p "${BUILD_DIR}"
}

###############################################################################
#
# functions to configure the sources

#..............................................................................
#
pbuild::add_configure_args() {
	CONFIGURE_ARGS+=( "$@" )
}
readonly -f pbuild::add_configure_args

pbuild.add_configure_args(){
	CONFIGURE_ARGS+=( "$@" )
}
readonly -f pbuild.add_configure_args

#..............................................................................
#
pbuild::use_autotools() {
	std::info \
		"Using ${FUNCNAME[0]} is deprecated with YAML module configuration files."
	configure_with='autotools'
}
readonly -f pbuild::use_autotools

#..............................................................................
#
pbuild::use_cmake() {
	std::info \
		"Using ${FUNCNAME[0]} is deprecated with YAML module configuration files."
	configure_with='cmake'
}
readonly -f pbuild::use_cmake

pbuild.configure_with(){
	configure_with="$1"
}

#..............................................................................
#
# Use this C-compiler
#
# Arguments:
#	$1	C-compiler to use.
#
pbuild::use_cc() {
	[[ -x "$1" ]] || std::die 3 \
				  "%s " "${module_name}/${module_version}:" \
				  "Error in setting CC:" \
				  "'$1' is not an executable!"
	export CC="$1"
}
readonly -f pbuild::use_cc

#..............................................................................
#
# Set flag to build module in source tree.
#
# Arguments:
#   none
#
declare -- compile_in_sourcetree='no'

pbuild::compile_in_sourcetree() {
	std::info \
		"Using ${FUNCNAME[0]} is deprecated with YAML module configuration files."
	compile_in_sourcetree='yes'
}
readonly -f pbuild::compile_in_sourcetree
pbuild.compile_in_sourcetree(){
	if [[ "${1,,}" == 'yes' ]]; then
		compile_in_sourcetree='yes'
	fi
}

#..............................................................................
#
# Configure the software to be compiled.
#
# Arguments:
#	none
#
pbuild::configure() {
	case "${configure_with}" in
		autotools )
        		if [[ ! -r "${SRC_DIR}/configure" ]]; then
				std::die 3 \
					 "%s " "${module_name}/${module_version}:" \
					 "${FNCNAME[0]}:" \
					 "autotools configuration not available, aborting..."
			fi
			;;
		cmake )
			if [[ ! -r "${SRC_DIR}/CMakeLists.txt" ]]; then
				std::die 3 \
					 "%s " "${module_name}/${module_version}:" \
					 "${FNCNAME[0]}:" \
					 "CMake script not available, aborting..."
			fi
			;;
	esac
	local -a config_args=()
	local -- arg=''
	for arg in "${CONFIGURE_ARGS[@]}"; do
		config_args+=( "$(envsubst <<<"${arg}")" )
	done
	if [[ -r "${SRC_DIR}/configure" ]] && \
		   [[ "${configure_with}" == 'auto' ]] || \
			   [[ "${configure_with}" == 'autotools' ]]; then
		"${SRC_DIR}/configure" \
			  --prefix="${PREFIX}" \
			  "${config_args[@]}" || \
			std::die 3 \
				 "%s " "${module_name}/${module_version}:" \
				 "configure failed"
	elif [[ -r "${SRC_DIR}/CMakeLists.txt" ]] && \
		     [[ "${configure_with}" == 'auto' ]] || \
			     [[ "${configure_with}" == "cmake" ]]; then
		# note: in most/many cases a cmake module is used!
		cmake \
			-DCMAKE_INSTALL_PREFIX="${PREFIX}" \
			"${config_args[@]}" \
			"${SRC_DIR}" || \
			std::die 3 \
				 "%s " "${module_name}/${module_version}:" \
				 "cmake failed"
	else
		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"${FUNCNAME[0]}: skipping..."
	fi
}


##############################################################################
#
# functions to compile the sources

#..............................................................................
#
# Default compile function.
#
# Note:
# Makefiles generated by autotools can fail if the environemnt variable
# V is set.
#
# Arguments:
#	none
#
pbuild::compile() {
	local v_save="$V"
	unset V
	(( JOBS == 0 )) && JOBS=$(_get_num_cores)
	${make} -j${JOBS} || \
		std::die 3 \
			 "%s " "${module_name}/${module_version}:" \
			 "compilation failed!"
	declare -g V="${v_save}"
}

##############################################################################
#
# functions to install everything

#..............................................................................
#
# Set documentation file to be installed.
#
# Arguments:
#   $@: documentation files relative to source
#
pbuild::install_docfiles() {
	std::info \
		"Using ${FUNCNAME[0]} is deprecated with YAML module configuration files."
	MODULE_DOCFILES+=("$@")
}
readonly -f pbuild::install_docfiles

#..............................................................................
#
# Default install function.
#
# Arguments:
#	none
#
pbuild::install() {
	${make} install || \
		std::die 3 \
			 "%s " "${module_name}/${module_version}:" \
			 "compilation failed!"
}

#..............................................................................
#
pbuild::install_shared_libs() {
	local -r binary="$1"
	local -r dstdir="$2"
	local -r pattern="${3//\//\\/}" # escape slash

	install_shared_libs_Linux() {
		local -a libs=()
		mapfile -t libs < <(${ldd} "${binary}" | \
				       ${awk} "/ => \// && /${pattern}/ {print \$3}")
		if (( ${#libs[@]} > 0 )); then
			${cp} -vL "${libs[@]}" "${dstdir}" || return $?
		fi
		return 0
	}

	install_shared_libs_Darwin() {
		# https://stackoverflow.com/questions/33991581/install-name-tool-to-update-a-executable-to-search-for-dylib-in-mac-os-x
		local -a libs=()
		mapfile -t libs < <(${otool} -L "${binary}" | \
				       ${awk} "/${pattern}/ {print \$1}")
		if (( ${#libs[@]} > 0 )); then
			${cp} -vL "${libs[@]}" "${dstdir}" || return $?
		fi
		return 0
	}

	test -e "${binary}" || \
		std::die 3 \
			 "%s " "${module_name}/${module_version}:" \
			 "${binary}: does not exist or is not executable!"
	${mkdir} -p "${dstdir}"
	case "${KernelName}" in
		Linux )
			install_shared_libs_Linux
			;;
		Darwin )
			install_shared_libs_Darwin
			;;
	esac
}

###############################################################################
#
# The following two functions are the entry points called by modbuild!
#

declare opt_yaml='yes'
pbuild.build_module_legacy(){
	opt_yaml='no'
	_build_module "$@"
}
readonly -f pbuild.build_module_legacy

declare -n Config
declare -a Systems
declare -a UseOverlays
pbuild.build_module_yaml(){
	local -- module_name="$1"
	local -- module_version="$2"
	Config="$3"
	local -- module_relstage="${Config['relstage']}"
	readarray -t Systems <<< "${Config['systems']}"
	readarray -t UseOverlays <<< "${Config['use_overlays']}"
	shift 3
	_build_module "${module_name}" "${module_version}" "${module_relstage}" "$@"
}
readonly -f pbuild.build_module_yaml

#..............................................................................
#
# The real worker function.
#
_build_module() {
	declare -gx module_name="$1"
	declare -gx module_version="$2"
	declare -gx module_release="$3"
	shift 3
	with_modules=( "$@" )

	# used in _make_all
	declare -a runtime_dependencies=()
	declare -a install_dependencies=()

	#......................................................................
	#
	# test whether a module is loaded or not
	#
	# Arguments:
	#	$1	module name
	#
	is_loaded() {
		[[ :${LOADEDMODULES}: =~ :$1: ]]
	}

	load_overlays(){
		eval "$( "${modulecmd}" bash use "${Config['use_overlays']}" )"
	}

	#......................................................................
	#
	# Load build- and run-time dependencies.
	#
	# Arguments:
	#	none
	#
	# Variables
	#	module_release		set if defined in a variants file
	#	runtime_dependencies    runtime dependencies from variants added
	#
	load_build_dependencies() {

 		#..............................................................
		#
		# build a dependency
		#
		# $1: name of module to build
		#
		# :FIXME: needs testing
		#
		build_dependency() {
			find_build_script(){
				local p=$1
				local script=''
				script=$(${find} "${BUILDBLOCK_DIR}/../.." \
						 -path "*/$p/build")
				std::get_abspath "${script}"
			}

			local -r m=$1
			std::debug "${m}: module not available"
			[[ ${dry_run} == yes ]] && \
				std::die 1 \
					 "%s " \
					 "${m}: module does not exist," \
					 "cannot continue with dry run..."

			std::info "%s " \
				  "$m: module does not exist, trying to build it..."
			local args=( '' )
			set -- "${ARGS[@]}"
			while (( $# > 0 )); do
				case $1 in
					-j )
						args+=( "-j $2" )
						shift
						;;
					--jobs=[0-9]* )
						args+=( "$1" )
						;;
					-v | --verbose)
						args+=( "$1" )
						;;
					--with=*/* )
						args+=( "$1" )
						;;
				esac
				shift
			done

			local buildscript=''
			buildscript=$(find_build_script "${m%/*}")
			[[ -x "${buildscript}" ]] || \
				std::die 1 \
					 "$m: build-block not found!"
			if ! "${buildscript}" "${m#*/}" "${args[@]}"; then
				std::die 1 \
					 "$m: oops: build failed..."
			fi
		}

		local m=''
		for m in "${with_modules[@]}"; do

			# module name prefixes in dependency declarations:
			# 'b:' this is a build dependency
			# 'r:' this a run-time dependency, *not* required for
			#      building
			# without prefix: this is a build and
			#      run-time dependency
			if [[ "${m:0:2}" == "b:" ]]; then
				m=${m#*:}   # remove 'b:'
			elif [[ "${m:0:2}" == "r:" ]]; then
				m=${m#*:}   # remove 'r:'
				runtime_dependencies+=( "$m" )
			elif [[ "${m:0:2}" == "R:" ]]; then
				m=${m#*:}   # remove 'R:'
				install_dependencies+=( "$m" )
				continue
			else
				runtime_dependencies+=( "$m" )
			fi
			is_loaded "$m" && continue

			# 'module avail' might output multiple matches if module
			# name and version are not fully specified or in case
			# modules with and without a release number exist.
			# Example:
			# mpc/1.1.0 and mpc/1.1.0-1. Since we get a sorted list
			# from 'module avail' and the full version should be set
			# in the variants file, we look for the first exact
			# match.
			local release_of_dependency=''
			if ! pbuild::module_is_avail "$m" release_of_dependency; then
				build_dependency "$m"
				pbuild::module_is_avail "$m" release_of_dependency || \
					std::die 6 "Oops"
			fi
			# for a stable module all dependencies must be stable
			if [[ "${module_release}" == 'stable' ]] \
				   && [[ "${release_of_dependency}" != 'stable' ]]; then
				std::die 5 \
					 "%s " "${module_name}/${module_version}:" \
					 "release cannot be set to '${module_release}'" \
					 "since the dependency '$m' is ${release_of_dependency}"
				# for a unstable module no dependency must be deprecated
			elif [[ "${module_release}" == 'unstable' ]] \
				     && [[ "${release_of_dependency}" == 'deprecated' ]]; then
				std::die 5 \
					 "%s " "${module_name}/${module_version}:" \
					 "release cannot be set to '${module_release}'" \
					 "since the dependency '$m' is ${release_of_dependency}"
			fi

			std::info "Loading module: ${m}"
			eval "$( "${modulecmd}" bash load "${m}" )"
		done
	}

	#......................................................................
	check_supported_systems() {
		if [[ "${opt_yaml,,}" == 'no' ]]; then
			(( ${#SUPPORTED_SYSTEMS[@]} == 0 )) && return 0
			for sys in "${SUPPORTED_SYSTEMS[@]}"; do
				[[ "${sys,,}" == "${system,,}" ]] && return 0
			done
			std::die 1 \
				 "%s " "${module_name}/${module_version}:" \
				 "Not available for ${system}."
		fi
	}

	#......................................................................
	check_supported_compilers() {
		(( ${#SUPPORTED_COMPILERS[@]} == 0 )) && return 0
		for compiler in "${SUPPORTED_COMPILERS[@]}"; do
			[[ "${compiler,,}" == "${COMPILER,,}" ]] && return 0
		done
		std::die 1 \
			 "%s " "${module_name}/${module_version}:" \
			 "Not available for ${COMPILER}."
	}

	#......................................................................
	#
	# compute full module name and installation prefix
	#
	# The following variables are expected to be set:
	#	GROUP	    module group
	#	P		    module name
	#	V		    module version
	#       variables defining the hierarchical environment like
	#	COMPILER and COMPILER_VERSION
	#
	# The following variables are set in this function
	#	modulefile_dir
	#	modulefile_name
	#	PREFIX
	#
	set_full_module_name_and_prefix() {
		die_no_compiler(){
			std::die 1 \
				 "%s: %s" \
				 "${module_name}/${module_version}" \
				 "module is in group '${GROUP}' but no compiler loaded!"
		}
		die_no_mpi(){
			std::die 1 \
				 "%s: %s" \
				 "${module_name}/${module_version}" \
				 "module is in group '${GROUP}' but no MPI module loaded!"
		}
		die_no_hdf5(){
			std::die 1 \
				 "%s: %s" \
				 "${module_name}/${module_version}" \
				 "module is in group '${GROUP}' but no HDF5 module loaded!"
		}

		modulefile_dir="${ol_modulefiles_root}/${GROUP}/${PMODULES_MODULEFILES_DIR}/"
		PREFIX="${ol_install_root}/${GROUP}/${module_name}/${module_version}/"
		case "${GROUP}" in
			Compiler )
				[[ -v COMPILER_VERSION ]] || die_no_compiler
				modulefile_dir+="${COMPILER}/${COMPILER_VERSION}/"
				PREFIX+="${COMPILER}/${COMPILER_VERSION}/"
				group_depth=2
				;;
			MPI )
				[[ -v COMPILER_VERSION ]] || die_no_compiler
				[[ -v MPI_VERSION ]] || die_no_mpi
				modulefile_dir+="${COMPILER}/${COMPILER_VERSION}/"
				modulefile_dir+="${MPI}/${MPI_VERSION}/"
				PREFIX+="${MPI}/${MPI_VERSION}/"
				PREFIX+="${COMPILER}/${COMPILER_VERSION}/"
				group_depth=4
				;;
			HDF5 )
				[[ -v COMPILER_VERSION ]] || die_no_compiler
				[[ -v MPI_VERSION ]] || die_no_mpi
				[[ -v HDF5_VERSION ]] || die_no_hdf5
				modulefile_dir+="${COMPILER}/${COMPILER_VERSION}/"
				modulefile_dir+="${MPI}/${MPI_VERSION}/"
				modulefile_dir+="hdf5/${HDF5_VERSION}/"
				PREFIX+="hdf5/${HDF5_VERSION}/"
				PREFIX+="${MPI}/${MPI_VERSION}/"
				PREFIX+="${COMPILER}/${COMPILER_VERSION}/"
				group_depth=6
				;;
			HDF5_serial )
				[[ -v COMPILER_VERSION ]] || die_no_compiler
				[[ -v HDF5_SERIAL_VERSION ]] || die_no_hdf5
				modulefile_dir+="${COMPILER}/${COMPILER_VERSION}/"
				modulefile_dir+="hdf5_serial/${HDF5_SERIAL_VERSION}/"
				PREFIX+="hdf5_serial/${HDF5_SERIAL_VERSION}/"
				PREFIX+="${COMPILER}/${COMPILER_VERSION}/"
				group_depth=4
				;;
			* )
				:
				;;
		esac
		modulefile_dir+="${module_name}"
		modulefile_name="${modulefile_dir}/${module_version}"
	} # set_full_module_name_and_prefix
	
	#......................................................................
	# post-install.
	#
	# Arguments:
	#	none
	post_install() {
		#..............................................................
		# post-install:
		# - build-script
		# - list of loaded modules while building
		# - doc-files specified in the build-script
		#
		# Arguments:
		#     none
		#
		install_doc() {
			local -r docdir="${PREFIX}/${_DOCDIR}/${module_name}"
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"Installing documentation to ${docdir}"
			${install} -m 0755 -d "${docdir}"
			${install} -m 0644 "${BUILD_SCRIPT}" "${docdir}"
			"${modulecmd}" bash list -t 2>&1 1>/dev/null | \
				${grep} -v "Currently Loaded" > \
				      "${docdir}/dependencies" || :

			(( ${#MODULE_DOCFILES[@]} == 0 )) && return 0
			${install} -m0644 \
				"${MODULE_DOCFILES[@]/#/${SRC_DIR}/}" \
				"${docdir}"
			return 0
		}

		#..............................................................
		# post-install: write file with required modules
		write_runtime_dependencies() {
			local -r fname="$1"
			shift
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"writing run-time dependencies to ${fname} ..."
			local dep
			echo -n "" > "${fname}"
			for dep in "$@"; do
				[[ -z $dep ]] && continue
				if [[ ! $dep == */* ]]; then
					# no version given: derive the version
					# from the currently loaded module
					dep=$( "${modulecmd}" bash list -t 2>&1 1>/dev/null \
						       | grep "^${dep}/" )
				fi
				echo "${dep}" >> "${fname}"
			done
		}
		patch_elf_exe_and_libs(){
			local -- libdir="${OverlayInfo[${ol_name}:install_root]}/lib64"
			[[ -d "${libdir}" ]] || return 0
			local -a bin_objects=()
			mapfile -t bin_objects < <(std::find_executables '.')
			local -- fname=''
			local -- rpath=''
			local -i depth=0
			for fname in "${bin_objects[@]}"; do
				# don't override existing RPATH
				rpath=$(patchelf --print-rpath "${fname}")
				[[ -z "${rpath}" ]] || continue
				(( depth=$(std::get_dir_depth "${fname}") + group_depth + 3 ))
				rpath='$ORIGIN/'$(printf "../%.0s" $(${seq} 1 ${depth}))lib64
				${patchelf} --force-rpath --set-rpath "${rpath}" "${fname}"
			done
			mapfile -t bin_objects < <(std::find_shared_objects '.')
			for fname in "${bin_objects[@]}"; do
				# don't override existing RPATH
				rpath=$(patchelf --print-rpath "${fname}")
				[[ -z "${rpath}" ]] || continue
				(( depth=$(std::get_dir_depth "${fname}") + group_depth + 3 ))
				rpath='$ORIGIN/'$(printf "../%.0s" $(${seq} 1 ${depth}))lib64
				${patchelf} --force-rpath --set-rpath "${rpath}" "${fname}"
			done
		}

		#..............................................................
		# post-install: for Linux we need a special post-install to
		# solve the multilib problem with LIBRARY_PATH on 64-bit systems
		post_install_linux() {
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"running post-installation for ${KernelName} ..."
			cd "${PREFIX}"
			[[ -d "lib" ]] && [[ ! -d "lib64" ]] && ln -s lib lib64
			patch_elf_exe_and_libs
			return 0
		}

		#..............................................................
		# post-install
		cd "${BUILD_DIR}"
		[[ "${KernelName}" == "Linux" ]] && post_install_linux
		install_doc
		if (( ${#runtime_dependencies[@]} > 0 )); then
			write_runtime_dependencies \
				"${PREFIX}/${FNAME_RDEPS}" \
				"${runtime_dependencies[@]}"
		fi
		if (( ${#install_dependencies[@]} > 0 )); then
			write_runtime_dependencies \
				"${PREFIX}/${FNAME_IDEPS}" \
				"${install_dependencies[@]}"
		fi
		install_modulefile
		install_release_file
		cleanup_build
		cleanup_src
		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"Done ..."
		return 0
	} # post_install

 	#......................................................................
	# Install modulefile in ${ol_modulefiles_root}/${GROUP}/modulefiles/...
	# The modulefiles in the build-block can be
	# versioned like
	#     modulefile-10.2.0
	#     modulefile-10.2
	#     modulefile-10
	#     modulefile
	# the most specific modulefile will be selected. Example:
	# For a version 10.2.1 the file moduelfile-10.2 would be
	# selected.
	#
	# Arguments
	#     none
	#
	# Used gloabal variables:
	#     VERSIONS
	#     BUILDBLOCK_DIR
	#     modulefile_name
	#
	install_modulefile() {
		#..............................................................
		# Select the modulefile to install.
		#
		# Arguments:
		#     $1  upvar to return the filename
		#
		find_modulefile() {
			local -n _modulefile="$1"
			local fname=''
			for fname in "${VERSIONS[@]/#/modulefile-}" 'modulefile'; do
				if [[ -r "${BUILDBLOCK_DIR}/${fname}" ]]; then
					_modulefile="${BUILDBLOCK_DIR}/${fname}"
					break;
				fi
			done
			[[ -n "${_modulefile}" ]]
		}
		[[ "${is_subpkg}" == 'yes' ]] && return 0
		local src=''
		if ! find_modulefile src; then
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"skipping modulefile installation ..."
			return
		fi
		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"adding modulefile to overlay '${ol_name}' ..."
		${mkdir} -p "${modulefile_dir}"
		${install} -m 0644 "${src}" "${modulefile_name}"
	}

	cleanup_modulefiles(){
		#
		# FIXME: Can it happen, that we remove module-/config-files which
		#        we shouldn't remove?
		#        For now we exclude removing from the overlay 'base' only.
		#
		[[ "${is_subpkg}" == 'yes' ]] && return 0
		local ol=''
		for ol in "${Overlays[@]}"; do
			[[ "${ol}" == "${ol_name}" ]] && continue
			[[ "${ol}" == 'base' ]] && continue
			local modulefiles_root="${OverlayInfo[${ol}:modulefiles_root]}"
			local dir="${modulefile_dir/${ol_modulefiles_root}/${modulefiles_root}}"
			local fname="${dir}/${module_version}"
			if [[ -e "${fname}" ]]; then
				std::info "%s "\
					  "${module_name}/${module_version}:" \
					  "removing modulefile from overlay '${ol}' ..."
				${rm} -f  "${fname}"
			fi
			fname="${dir}/.release-${module_version}"
			if [[ -e "${fname}" ]]; then
				std::info \
					"%s " \
					"${module_name}/${module_version}:" \
					"removing release file from overlay '${ol}' ..."
				${rm} -f "${fname}"
			fi
		done
	}

	install_release_file() {
		[[ "${is_subpkg}" == 'yes' ]] && return 0

		local -r legacy_config_file="${modulefile_dir}/.release-${module_version}"
		local -- status_legay_config_file='unchanged'
		local -- relstage_legacy=''
		if [[ -r "${legacy_config_file}" ]]; then
			read -r relstage_legacy < "${legacy_config_file}"
			if [[ "${relstage_legacy}" != "${module_release}" ]]; then
				status_legay_config_file='changed'
			fi
		else
			status_legay_config_file='new'
		fi
		${mkdir} -p "${modulefile_dir}"
		if [[ "${status_legay_config_file}" != 'unchanged' ]]; then
			echo "${module_release}" > "${legacy_config_file}"
		fi

 		local -r yaml_config_file="${modulefile_dir}/.config-${module_version}"
		local -- status_yaml_config_file='unchanged'
		if [[ -r "${yaml_config_file}" ]]; then
			while read -r key value; do
				local -n ref="${key:0:-1}"
				ref="${value}"
			done < "${yaml_config_file}"
			if [[ "${relstage}" != "${module_release}" ]]; then
				status_yaml_config_file='changed'
			fi
		else
			status_yaml_config_file='new'
		fi
		if [[ "${status_yaml_config_file}" != 'unchanged' ]]; then
			echo "relstage: ${module_release}" > "${yaml_config_file}"
			if (( ${#Systems[@]} > 0 )); then
				echo -n "systems: [${Systems[0]}" >> "${yaml_config_file}"
				for system in "${Systems[@]:1}"; do
					echo -n ", ${system}" >> "${yaml_config_file}"
				done
				echo "]" >> "${yaml_config_file}"
			fi
		fi

		case ${status_yaml_config_file},${status_legay_config_file} in
			unchanged,unchanged | new,unchanged)
				:
				;;
			unchanged,changed )
				std::info \
					"%s " \
					"${module_name}/${module_version}:" \
					"changing release stage from" \
					"'${relstage_legacy}' to '${module_release}' in legacy config file ..."
				;;
			unchanged,new )
				std::info \
					"%s " \
					"${module_name}/${module_version}:" \
					"setting release stage to '${module_release}' in legacy config file ..."
				;;
			changed,unchanged | changed,changed | changed,new | new,changed )
				std::info \
					"%s " \
					"${module_name}/${module_version}:" \
					"changing release stage from" \
					"'${relstage_legacy}' to '${module_release}' ..."
				;;
			new,new )
				std::info \
					"%s " \
					"${module_name}/${module_version}:" \
					"setting release stage to '${module_release}' ..."
				;;
		esac
	}

	cleanup_build() {
		[[ ${enable_cleanup_build} != 'yes' ]] && return 0
		[[ "${BUILD_DIR}" == "${SRC_DIR}" ]] && return 0
		[[ -d "${BUILD_DIR}/../.." ]] || return 0
		{
			cd "/${BUILD_DIR}/.." || std::die 42 "Internal error"
			[[ "$(${pwd})" == "/" ]] && \
				std::die 1 \
					 "%s " "${module_name}/${module_version}:" \
					 "Oops: internal error:" \
			     		 "BUILD_DIR is set to '/'"

			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"Cleaning up '${BUILD_DIR}'..."
			${rm} -rf "${BUILD_DIR##*/}"
		};
		return 0
	}

	cleanup_src() {
		[[ ${enable_cleanup_src} != 'yes' ]] && return 0
		[[ -d "${BUILD_DIR}/../.." ]] || return 0
    		{
			cd "/${SRC_DIR}/.." || std::die 42 "Internal error"
			[[ $(pwd) == / ]] && \
				std::die 1 \
					 "%s " "${module_name}/${module_version}:" \
					 "Oops: internal error:" \
			     		 "SRC_DIR is set to '/'"
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"Cleaning up '${SRC_DIR}'..."
			${rm} -rf "${SRC_DIR##*/}"
   		};
		return 0
	}

	#......................................................................
	# build module ${module_name}/${module_version}
	compile_and_install() {
		build_target() {
			local dir="$1"		# src or build directory, depends on target
			local target="$2"	# prep, configure, compile or install

			if [[ -e "${BUILD_DIR}/.${target}" ]] && \
				   [[ ${force_rebuild} == 'no' ]]; then
				return 0
			fi
			local targets=()
			targets+=( "${VERSIONS[@]/#/pbuild::pre_${target}_${system}_}" )
			targets+=( "pbuild::pre_${target}_${system}" )
			targets+=( "${VERSIONS[@]/#/pbuild::pre_${target}_${KernelName}_}" )
			targets+=( "pbuild::pre_${target}_${KernelName}" )
			targets+=( "${VERSIONS[@]/#/pbuild::pre_${target}_}" )
			targets+=( "pbuild::pre_${target}" )

			targets+=( "${VERSIONS[@]/#/pbuild::${target}_${system}_}" )
			targets+=( "pbuild::${target}_${system}" )
			targets+=( "${VERSIONS[@]/#/pbuild::${target}_${KernelName}_}" )
			targets+=( "pbuild::${target}_${KernelName}" )
			targets+=( "${VERSIONS[@]/#/pbuild::${target}_}" )
			targets+=( "pbuild::${target}" )

			targets+=( "${VERSIONS[@]/#/pbuild::post_${target}_${system}_}" )
			targets+=( "pbuild::post_${target}_${system}" )
			targets+=( "${VERSIONS[@]/#/pbuild::post_${target}_${KernelName}_}" )
			targets+=( "pbuild::post_${target}_${KernelName}" )
			targets+=( "${VERSIONS[@]/#/pbuild::post_${target}_}" )
			targets+=( "pbuild::post_${target}" )

			for t in "${targets[@]}"; do
				# We cd into the dir before calling the function -
				# just to be sure we are in the right directory.
				#
				# Executing the function in a sub-process doesn't
				# work because in some function global variables
				# might/need to be set.
				#
				cd "${dir}"
				if typeset -F "$t" 2>/dev/null; then
					"$t" || \
						std::die 10 "Aborting..."
				fi
			done
			touch "${BUILD_DIR}/.${target}"
		} # compile_and_install():build_target()

		[[ ${dry_run} == yes ]] && std::die 0 ""

		${mkdir} -p "${SRC_DIR}"
		${mkdir} -p "${BUILD_DIR}"

 		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"preparing sources ..."
		build_target "${SRC_DIR}" prep
		[[ "${build_target}" == "prep" ]] && return 0

 		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"configuring ..."
		build_target "${BUILD_DIR}" configure
		[[ "${build_target}" == "configure" ]] && return 0

 		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"compiling ..."
		build_target "${BUILD_DIR}" compile
		[[ "${build_target}" == "compile" ]] && return 0

		${mkdir} -p "${PREFIX}"
 		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"installing ..."
		build_target "${BUILD_DIR}" install
	} # compile_and_install()

	remove_module() {
		if [[ -d "${PREFIX}" ]]; then
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"removing all files in '${PREFIX}' ..."
			[[ "${dry_run}" == 'no' ]] && ${rm} -rf "${PREFIX}"
		fi
		if [[ -e "${modulefile_name}" ]]; then
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"removing modulefile '${modulefile_name}' ..."
			[[ "${dry_run}" == 'no' ]] && ${rm} -vf "${modulefile_name}"
		fi
		local release_file="${modulefile_dir}/.release-${module_version}"
		if [[ -e "${release_file}" ]]; then
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"removing release file '${release_file}' ..."
			[[ "${dry_run}" == 'no' ]] && ${rm} -vf "${release_file}"
		fi
		release_file="${modulefile_dir}/.config-${module_version}"
		if [[ -e "${release_file}" ]]; then
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"removing release file '${release_file}' ..."
			[[ "${dry_run}" == 'no' ]] && ${rm} -vf "${release_file}"
		fi
		${rmdir} -p "${modulefile_dir}" 2>/dev/null || :
	}

	deprecate_module(){
		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"is deprecated, skiping!"
		install_release_file
	}

	std::info \
		"%s " \
		"${module_name}/${module_version}:" \
		${with_modules:+with ${with_modules[@]}} \
		"building ..."

	init_module_environment
	load_overlays
	load_build_dependencies
	BUILD_ROOT="${PMODULES_TMPDIR}/${module_name}-${module_version}"
	SRC_DIR="${BUILD_ROOT}/src"
	if [[ "${compile_in_sourcetree,,}" == 'yes' ]]; then
		BUILD_DIR="${SRC_DIR}"
	else
		BUILD_DIR="${BUILD_ROOT}/build"
	fi

	source "${BUILD_SCRIPT}"
	
	# module name including path in hierarchy and version
	# (ex: 'gcc/6.1.0/openmpi/1.10.2' for openmpi compiled with gcc 6.1.0)
	local    modulefile_dir=''
	local    modulefile_name=''

	#
	# :FIXME: add comments what and why we are doing this.
	#
	local -r logfile="${BUILDBLOCK_DIR}/pbuild.log"
	${rm} -f "${logfile}"
	if [[ "${verbose}" == 'yes' ]]; then
		exec  > >(${tee} -a "${logfile}")
	else
		exec > >(${cat} >> "${logfile}")
	fi
	exec 2> >(${tee} -a "${logfile}" >&2)

	# the group must have been defined - otherwise we cannot continue
	[[ -n ${GROUP} ]] || \
		std::die 5 \
			 "%s " "${module_name}/${module_version}:" \
			 "Module group not set! Aborting ..."

	# check whether this module is supported
	check_supported_systems
	check_supported_compilers
	[[ "${is_subpkg}" != 'yes' ]] && set_full_module_name_and_prefix

	# ok, finally we can start ...
 	std::info \
		"%s " \
		"${module_name}/${module_version}:" \
		${with_modules:+build with ${with_modules[@]}}

	if [[ "${module_release}" == 'remove' ]]; then
		remove_module
		cleanup_modulefiles
	elif [[ "${module_release}" == 'deprecated' ]]; then
		deprecate_module
		cleanup_modulefiles
	elif [[ -d "${PREFIX}" || "${is_subpkg}" == 'yes' ]] && [[ "${force_rebuild}" == 'no' ]]; then
 		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"already exists, not rebuilding ..."
		if [[ "${opt_update_modulefiles}" == "yes" ]] || \
			   [[ ! -e "${modulefile_name}" ]]; then
			install_modulefile
		fi
		install_release_file
		cleanup_modulefiles
	else
		if [[ "${opt_clean_install,,}" == 'yes' ]]; then
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"remove module, if already exists ..."
			remove_module
		fi
		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"start building ..."
		cleanup_build
		cleanup_src
		compile_and_install
		post_install
		cleanup_modulefiles
	fi
	std::info "* * * * *\n"
}
readonly -f _build_module

# Local Variables:
# mode: sh
# sh-basic-offset: 8
# tab-width: 8
# End:
