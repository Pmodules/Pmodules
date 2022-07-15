#!/bin/bash

#.............................................................................
# disable auto-echo feature of 'cd'
unset CDPATH

#.............................................................................
# define constants
declare -r BNAME_VARIANTS='variants'
declare -r FNAME_RDEPS='.dependencies'
declare -r FNAME_IDEPS='.install_dependencies'
declare -r FNAME_BDEPS='.build_dependencies'

# relative path of documentation
# abs. path is "${PREFIX}/${_docdir}/${module_name}"
declare -r  _DOCDIR='share/doc'

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
	case "${OS}" in
	Linux )
		${grep} -c ^processor /proc/cpuinfo
		;;
	Darwin )
		${sysctl} -n hw.ncpu
		;;
	* )
		std::die 1 "OS ${OS} is not supported\n"
		;;
	esac
}
readonly -f _get_num_cores

#..............................................................................
# global variables which can be set/overwritten by command line args
# and their corresponding functions
#
declare force_rebuild=''
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


###############################################################################
#
# function in the "namespace" (with prefix) 'pbuild::' can be used in
# build-scripts
#

#..............................................................................
#
# compare two version numbers
#
# original implementation found on stackoverflow:
# https://stackoverflow.com/questions/4023830/how-to-compare-two-strings-in-dot-separated-version-format-in-bash
#
pbuild::version_compare () {
        is_uint() {
                [[ $1 =~ ^[0-9]+$ ]]
        }

        [[ $1 == $2 ]] && return 0
        local IFS=.
        local i ver1=($1) ver2=($2)

        # fill empty fields in ver1 with zeros
        for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
                ver1[i]=0
        done
        for ((i=0; i<${#ver1[@]}; i++)); do
                [[ -z ${ver2[i]} ]] && ver2[i]=0
                if is_uint ${ver1[i]} && is_uint ${ver2[i]}; then
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

#..............................................................................
# version less than
#
# return 0 if version passed in $1 is older then $2
#
pbuild::version_lt() {
        pbuild::version_compare "$1" "$2"
        (( $? == 2 ))
}
readonly -f pbuild::version_lt

#..............................................................................
# version less than or equal
#
# return 0 if version passed in $1 is older or equal then $2
#
pbuild::version_le() {
        pbuild::version_compare "$1" "$2"
        local -i exit_code=$?
        (( exit_code == 0 || exit_code == 2 ))
}
readonly -f pbuild::version_le

#..............................................................................
# version greater than
#
# return 0 if version passed in $1 is newer then $2
#
pbuild::version_gt() {
        pbuild::version_compare "$1" "$2"
        (( $? == 1 ))
        local -i exit_code=$?
        (( exit_code == 0 || exit_code == 1 ))
}
readonly -f pbuild::version_gt

#..............................................................................
# version greater than
#
# return 0 if version passed in $1 and $2 are equal
#
pbuild::version_eq() {
        pbuild::version_compare "$1" "$2"
}
readonly -f pbuild::version_eq

##############################################################################
#
# Set flag to build module in source tree.
#
# Arguments:
#   none
#
pbuild::compile_in_sourcetree() {
	BUILD_DIR="${SRC_DIR}"
}
readonly -f pbuild::compile_in_sourcetree

##############################################################################
#
# Check whether the script is running on a supported OS.
#
# Arguments:
#   $@: supported opertating systems (something like RHEL6, macOS10.14, ...).
#       Default is all.
#
pbuild::supported_systems() {
	SUPPORTED_SYSTEMS+=( "$@" )
}
readonly -f pbuild::supported_systems

##############################################################################
#
# Check whether the script is running on a supported OS.
#
# Arguments:
#   $@: supported opertating systems (like Linux, Darwin).
#       Default is all.
#
pbuild::supported_os() {
	SUPPORTED_OS+=( "$@" )
}
readonly -f pbuild::supported_os

##############################################################################
#
# Check whether the loaded compiler is supported.
#
# Arguments:
#   $@: supported compiler (like GCC, Intel, PGI).
#       Default is all.
#
pbuild::supported_compilers() {
	SUPPORTED_COMPILERS+=( "$@" )
}
readonly -f pbuild::supported_compilers

##############################################################################
#
# Install module in given group.
#
# Arguments:
#   $1: group
#
pbuild::add_to_group() {
	if (( $# == 0 )); then
		std::die 42 \
                         "%s " "${module_name}/${module_version}:" \
                         "${FUNCNAME}: missing group argument."
	fi
	GROUP="$1"
}
readonly -f pbuild::add_to_group

##############################################################################
#
# Set documentation file to be installed.
#
# Arguments:
#   $@: documentation files relative to source
#
pbuild::install_docfiles() {
	MODULE_DOCFILES+=("$@")
}
readonly -f pbuild::install_docfiles

##############################################################################
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
	local output=( $("${MODULECMD}" bash avail -a -m "$1" \
                                        2>&1 1>/dev/null) )
	local i
	for (( i = 0; i < ${#output[@]}; i += 2 )); do
		if [[ "${output[$i]}" == "$1" ]]; then
			if (( $# > 1 )); then
				local -n _result="$2"
				_result="${output[i+1]}"
			fi
			return 0
		fi
	done
	return 1
}
readonly -f pbuild::module_is_avail

##############################################################################
#
# Set the download URL and name of downloaded file.
#
# Arguments:
#	$1	download URL
#	$2	optional file-name (of)
pbuild::set_download_url() {
	local -i _i=${#SOURCE_URLS[@]}
	SOURCE_URLS[_i]="$1"
	if (( $# > 1 )); then
		SOURCE_NAMES[$_i]="${2:-${1##*/}}"
	else
		SOURCE_NAMES[$_i]="${1##*/}"
	fi
}
readonly -f pbuild::set_download_url

##############################################################################
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
	SOURCE_SHA256_SUMS+=("$1")
}
readonly -f pbuild::set_sha256sum

##############################################################################
#
# Unpack file $1 in directory $2
#
# Arguments:
#	$1	file-name
#	$2	directory
#
pbuild::set_unpack_dir() {
	SOURCE_UNPACK_DIRS[$1]=$2
}
readonly -f pbuild::set_unpack_dir

##############################################################################
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
	CC="$1"
}
readonly -f pbuild::use_cc

###############################################################################
#
pbuild::add_patch() {
	[[ -z "$1" ]] && \
		std::die 1 \
			 "%s " "${module_name}/${module_version}:" \
			 "${FUNCNAME}: missing argument!"
	PATCH_FILES+=( "$1" )
	if (( $# >= 2 )); then
		PATCH_STRIPS+=( "$2" )
	else
		PATCH_STRIPS+=( "${PATCH_STRIP_DEFAULT}" )
	fi
}
readonly -f pbuild::add_patch

###############################################################################
#
pbuild::set_default_patch_strip() {
	[[ -n "$1" ]] || \
		std::die 1 \
			 "%s " "${module_name}/${module_version}:" \
			 "${FUNCNAME}: missing argument!"

	PATCH_STRIP_DEFAULT="$1"
}
readonly -f pbuild::set_default_patch_strip

###############################################################################
#
pbuild::use_flag() {
	[[ "${USE_FLAGS}" =~ ":${1}:" ]]
}
readonly -f pbuild::use_flag

###############################################################################
#
pbuild::add_configure_args() {
	CONFIGURE_ARGS+=( "$@" )
}
readonly -f pbuild::add_configure_args

###############################################################################
#
pbuild::use_autotools() {
	configure_with='autotools'
}
readonly -f pbuild::use_autotools

###############################################################################
#
pbuild::use_cmake() {
	configure_with='cmake'
}
readonly -f pbuild::use_cmake

###############################################################################
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
			download_with_curl "${dir}/${fname}" "${url}"
			(( $? == 0 )) || \
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

		local sha256_sum=''
		local hash=''
		for hash in "${SOURCE_SHA256_SUMS[@]}"; do
			if [[ ${hash} =~ $fname: ]]; then
				sha256_sum="${hash#*:}"
			fi
		done
		if [[ -n "${sha256_sum}" ]]; then
			check_hash_sum "${dir}/${fname}" "${sha256_sum}"
		fi
	}

	unpack() {
		local -r file="$1"
		local -r dir="${2:-${SRC_DIR}}"
		${tar} --directory="${dir}" -xv --strip-components 1 -f "${file}" || {
			${rm} -f "${file}"
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
	if [[ -z "${SOURCE_URLS}" ]]; then
		for fname in ${VERSIONS[@]/#/pbuild::set_download_url_}; do
			if typeset -F ${fname} 2>/dev/null; then
				$f
				break
			fi
		done
	fi
	[[ -z "${SOURCE_URLS}" ]] && \
		std::die 3 \
			 "%s " "${module_name}/${module_version}:" \
			 "Download source not set!"
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
		local key="${SOURCE_URLS[i]##*/}"
		if [[ -v SOURCE_UNPACK_DIRS[${key}] ]]; then
			echo "dir specified"
			dir="${SOURCE_UNPACK_DIRS[${SOURCE_URLS[i]##*/}]}"
		else
			echo "use SRC_DIR"
			dir="${SRC_DIR}"
		fi
		unpack "${source_fname}" "${dir}"
	done
	patch_sources
	# create build directory
	${mkdir} -p "${BUILD_DIR}"
}

###############################################################################
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
	if [[ -r "${SRC_DIR}/configure" ]] && \
		   [[ "${configure_with}" == 'undef' ]] || \
			   [[ "${configure_with}" == 'autotools' ]]; then
		${SRC_DIR}/configure \
			  --prefix="${PREFIX}" \
			  "${CONFIGURE_ARGS[@]}" || \
			std::die 3 \
				 "%s " "${module_name}/${module_version}:" \
				 "configure failed"
	elif [[ -r "${SRC_DIR}/CMakeLists.txt" ]] && \
		     [[ "${configure_with}" == 'undef' ]] || \
			     [[ "${configure_with}" == "cmake" ]]; then
		# note: in most/many cases a cmake module is used!
		cmake \
			-DCMAKE_INSTALL_PREFIX="${PREFIX}" \
			"${CONFIGURE_ARGS[@]}" \
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


###############################################################################
#
# Default compile function.
#
# Arguments:
#	none
#
pbuild::compile() {
	(( JOBS == 0 )) && JOBS=$(_get_num_cores)
	${make} -j${JOBS} || \
		std::die 3 \
			 "%s " "${module_name}/${module_version}:" \
			 "compilation failed!"
}

###############################################################################
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

###############################################################################
#
pbuild::install_shared_libs() {
	local -r binary="$1"
	local -r dstdir="$2"
	local -r pattern="${3//\//\\/}" # escape slash

	install_shared_libs_Linux() {
		local libs=( $(ldd "${binary}" | \
				       ${awk} "/ => \// && /${pattern}/ {print \$3}") )
		if [[ -n "${libs}" ]]; then
			${cp} -vL "${libs[@]}" "${dstdir}" || return $?
		fi
		return 0
	}

	install_shared_libs_Darwin() {
		# https://stackoverflow.com/questions/33991581/install-name-tool-to-update-a-executable-to-search-for-dylib-in-mac-os-x
		local libs=( $(${otool} -L "${binary}" | \
				       ${awk} "/${pattern}/ {print \$1}"))
		if [[ -n "${libs}" ]]; then
			${cp} -vL "${libs[@]}" "${dstdir}" || return $?
		fi
		return 0
	}

	test -e "${binary}" || \
		std::die 3 \
			 "%s " "${module_name}/${module_version}:" \
			 "${binary}: does not exist or is not executable!"
	${mkdir} -p "${dstdir}"
	case "${OS}" in
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
# This is the main entry function called by modbuild!
#
pbuild.build_module() {
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

	#......................................................................
	#
	# Initialise environment modules.
	#
	# Arguments:
	#	none
	#
	init_module_environment(){
		eval $( "${MODULECMD}" bash use unstable )
		eval $( "${MODULECMD}" bash use deprecated )
		eval $( "${MODULECMD}" bash purge )

		# :FIXME: this is a hack!!!
		# shouldn't this be set in the build-script?
		if [[ -e "${PMODULES_HOME%%/Tools*}/Libraries" ]]; then
			eval $( "${MODULECMD}" bash use Libraries )
		fi
		if [[ -e "${PMODULES_HOME%%/Tools*}/System" ]]; then
			eval $( "${MODULECMD}" bash use System )
		fi
		unset	C_INCLUDE_PATH
		unset	CPLUS_INCLUDE_PATH
		unset	CPP_INCLUDE_PATH
		unset	LIBRARY_PATH
		unset	LD_LIBRARY_PATH
		unset	DYLD_LIBRARY_PATH
		
		unset	CFLAGS
		unset	CPPFLAGS
		unset	CXXFLAGS
		unset	LIBS
		unset	LDFLAGS

		unset	CC
		unset	CXX
		unset	FC
		unset	F77
		unset	F90
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
				local script=$(${find} "${BUILDBLOCK_DIR}/../.." \
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
			set -- ${ARGS[@]}
			while (( $# > 0 )); do
				case $1 in
					-j )
						args+=( "-j $2" )
						shift
						;;
					--jobs=[0-9]* )
						args+=( $1 )
						;;
					-v | --verbose)
						args+=( $1 )
						;;
					--with=*/* )
						args+=( $1 )
						;;
				esac
				shift
			done

			local buildscript=$(find_build_script "${m%/*}")
			[[ -x "${buildscript}" ]] || \
				std::die 1 \
					 "$m: build-block not found!"
			if ! "${buildscript}" "${m#*/}" ${args[@]}; then
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
			# should be set, just in case it is not...
			: ${release_of_dependency:='unstable'}

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
			eval $( "${MODULECMD}" bash load "${m}" )
		done
	}

	init_build_environment() {
		#......................................................................
		#
		# parse the passed version string
		#
		# the following global variables will be set in this function:
		#       V_MAJOR
		#       V_MINOR
		#       V_PATCHLVL
		#       V_RELEASE
		#       USE_FLAGS
		#
		parse_version() {
			local v="$1"
			V_MAJOR=''		# first number in version string
			V_MINOR=''		# second number in version string (or empty)
			V_PATCHLVL=''		# third number in version string (or empty)
			V_RELEASE=''		# module release (or empty)
			: ${USE_FLAGS:=''}	# architectures (or empty)

			local tmp=''

			if [[ "$v" =~ "_" ]]; then
				tmp="${v#*_}"
				USE_FLAGS+=":${tmp//_/:}:"
				v="${v%%_*}"
			fi
			V_PKG="${v%%-*}"	# version without the release number
			if [[ $v == *-* ]]; then
				V_RELEASE="${v#*-}"	# release number
			else
				V_RELEASE=''
			fi
			case "${V_PKG}" in
				*.*.* )
					V_MAJOR="${V_PKG%%.*}"
					tmp="${V_PKG#*.}"
					V_MINOR="${tmp%%.*}"
					V_PATCHLVL="${tmp#*.}"
					;;
				*.* )
					V_MAJOR="${V_PKG%.*}"
					V_MINOR="${V_PKG#*.}"
					;;
				* )
					V_MAJOR="${V_PKG}"
					;;
			esac

			VERSIONS=()
			if [[ -n ${V_RELEASE} ]]; then
				VERSIONS+=( ${V_PKG}-${V_RELEASE} )
			fi
			if [[ -n ${V_PATCHLVL} ]]; then
				VERSIONS+=( ${V_MAJOR}.${V_MINOR}.${V_PATCHLVL} )
			fi
			if [[ -n ${V_MINOR} ]]; then
				VERSIONS+=( ${V_MAJOR}.${V_MINOR} )
			fi
			VERSIONS+=( ${V_MAJOR} )
		}

		local -r module_name="$1"
		local -r module_version="$2"

		SRC_DIR="${PMODULES_TMPDIR}/${module_name}-${module_version}/src"
		BUILD_DIR="${PMODULES_TMPDIR}/${module_name}-${module_version}/build"

		# P and V can be used in the build-script, so we have to set them here
		P="${module_name}"
		V="${module_version}"
		parse_version "${module_version}"
		declare -gx GROUP=''
		declare -g  PREFIX=''
		
		SOURCE_URLS=()
		SOURCE_SHA256_SUMS=()
		SOURCE_NAMES=()
		declare -Ag SOURCE_UNPACK_DIRS=()
		CONFIGURE_ARGS=()
		SUPPORTED_SYSTEMS=()
		SUPPORTED_OS=()
		SUPPORTED_COMPILERS=()
		PATCH_FILES=()
		PATCH_STRIPS=()
		PATCH_STRIP_DEFAULT='1'
		MODULE_DOCFILES=()
		configure_with='undef'
	} # init_build_environment()

	#......................................................................
	check_supported_systems() {
		(( ${#SUPPORTED_SYSTEMS[@]} == 0 )) && return 0
		for sys in "${SUPPORTED_SYSTEMS[@]}"; do
			[[ ${sys,,} == ${system,,} ]] && return 0
		done
		std::die 1 \
			 "%s " "${module_name}/${module_version}:" \
			 "Not available for ${system}."
	}

	#......................................................................
	check_supported_os() {
		(( ${#SUPPORTED_OS[@]} == 0 )) && return 0
		for os in "${SUPPORTED_OS[@]}"; do
			[[ ${os,,} == ${OS,,} ]] && return 0
		done
		std::die 1 \
			 "%s " "${module_name}/${module_version}:" \
			 "Not available for ${OS}."
	}

	#......................................................................
	check_supported_compilers() {
		(( ${#SUPPORTED_COMPILERS[@]} == 0 )) && return 0
		for compiler in "${SUPPORTED_COMPILERS[@]}"; do
			[[ ${compiler,,} == ${COMPILER,,} ]] && return 0
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
		do_simple_group(){
			modulefile_dir="${ol_mod_root}/${GROUP}/${PMODULES_MODULEFILES_DIR}/"
			modulefile_dir+="${module_name}"
			modulefile_name="${modulefile_dir}/${module_version}"
			PREFIX="${ol_inst_root}/${GROUP}/${module_name}/${module_version}"
		}
		do_hierarchical_group(){
			join_by() {
				local IFS="$1"
				shift
				echo "$*"
			}
			# define hierarchies
			if [[ -v COMPILER_VERSION ]]; then
				Compiler_HIERARCHY='${COMPILER}/${COMPILER_VERSION}'
			else
				unset Compiler_HIERARCHY
			fi
			if [[ -v COMPILER_VERSION ]] && \
				   [[ -v HDF5_SERIAL_VERSION ]]; then
				HDF5_serial_HIERARCHY='${COMPILER}/${COMPILER_VERSION}'
				HDF5_serial_HIERARCHY+=' hdf5_serial/${HDF5_SERIAL_VERSION}'
			else
				unset HDF5_serial_HIERARCHY
			fi
			if [[ -v COMPILER_VERSION ]] && \
				   [[ -v MPI_VERSION ]]; then
				MPI_HIERARCHY='${COMPILER}/${COMPILER_VERSION}'
				MPI_HIERARCHY+=' ${MPI}/${MPI_VERSION}'
			else
				unset MPI_HIERARCHY
			fi
			if [[ -v COMPILER_VERSION ]] && \
				   [[ -v MPI_VERSION ]] && \
				   [[ HDF5_VERSION ]]; then
				HDF5_HIERARCHY='${COMPILER}/${COMPILER_VERSION}'
				HDF5_HIERARCHY+=' ${MPI}/${MPI_VERSION}'
				HDF5_HIERARCHY+=' hdf5/${HDF5_VERSION}'
			else
				unset HDF5_HIERARCHY
			fi

			# evaluate
			local names=()
			local -n vname="${GROUP}"_HIERARCHY
			if [[ -v vname ]]; then
				names=( $(eval echo ${vname}) )
			else
				std::die 1 \
					 "%s: %s" \
					 "${module_name}/${module_version}" \
					 "not all hierarchical dependencies loaded!"
			fi

			modulefile_dir=$(join_by '/' \
						 "${ol_mod_root}" \
						 "${GROUP}" \
						 "${PMODULES_MODULEFILES_DIR}" \
						 "${names[@]}" \
						 "${module_name}")
			modulefile_name="${modulefile_dir}/${module_version}"

			PREFIX="${ol_inst_root}/${GROUP}/${module_name}/${module_version}"
			local -i i=0
			for ((i=${#names[@]}-1; i >= 0; i--)); do
				PREFIX+="/${names[i]}"
			done
		}

		[[ -n ${GROUP} ]] || std::die 1 \
					      "%s: %s" \
					      "${module_name}/${module_version}" \
					      "group not set."

		local -i grp_depth
		compute_group_depth grp_depth "${ol_mod_root}/${GROUP}/${PMODULES_MODULEFILES_DIR}"
		if (( grp_depth == 0 )); then
			do_simple_group
		else
			do_hierarchical_group
		fi
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
			${install} -m0644 	"${BUILD_SCRIPT}" "${docdir}"
			"${MODULECMD}" bash list -t 2>&1 1>/dev/null | \
				${grep} -v "Currently Loaded" > \
				      "${docdir}/dependencies" || :

			if [[ ! -v MODULE_DOCFILES[0] ]]; then
				# loop over version specific functions. In these function
				# more MODULE_DOCFILES can be defined.
				# :FIXME: maybe we find a better solution.
				for f in ${VERSIONS[@]/#/pbuild::install_docfiles_}; do
					if typeset -F "$f" 2>/dev/null; then
						$f
						break
					fi
				done
			fi
			if [[ ! -v MODULE_DOCFILES[0] ]]; then
				return 0
			fi
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
					dep=$( "${MODULECMD}" bash list -t 2>&1 1>/dev/null \
						       | grep "^${dep}/" )
				fi
				echo "${dep}" >> "${fname}"
			done
		}

		#..............................................................
		# post-install: for Linux we need a special post-install to
		# solve the multilib problem with LIBRARY_PATH on 64-bit systems
		post_install_linux() {
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"running post-installation for ${OS} ..."
			cd "${PREFIX}"
			[[ -d "lib" ]] && [[ ! -d "lib64" ]] && ln -s lib lib64
			return 0
		}

		#..............................................................
		# post-install
		cd "${BUILD_DIR}"
		[[ "${OS}" == "Linux" ]] && post_install_linux
		install_doc
		if [[ -v runtime_dependencies[0] ]]; then
			write_runtime_dependencies \
				"${PREFIX}/${FNAME_RDEPS}" \
				"${runtime_dependencies[@]}"
		fi
		if [[ -v install_dependencies[0] ]]; then
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
	# Install modulefile in ${pm_root}/${GROUP}/modulefiles/...
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

		local src=''
		find_modulefile src
		if (( $? != 0 )); then
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
		local ol=''
		for ol in "${Overlays[@]}"; do
			local i
			for ((i=0; i<${#mod_overlays}; i++ )); do
				[[ "${ol}" == "{mod_overlays[i]}" ]] && continue 2
			done
			[[ "${ol}" == "${ol_name}" ]] && continue
			local mod_root="${OverlayInfo[${ol}:mod_root]}"
			local dir="${modulefile_dir/${ol_mod_root}/${mod_root}}"
			local fname="${dir}/${module_version}"
			if [[ -e "${fname}" ]]; then
				std::info "%s "\
					  "${module_name}/${module_version}:" \
					  "removing modulefile from overlay '${ol}' ..."
				${rm} "${fname}"
			fi
			fname="${dir}/.release-${module_version}"
			if [[ -e "${fname}" ]]; then
				std::info \
					"%s " \
					"${module_name}/${module_version}:" \
					"removing release file from overlay '${ol}' ..."
				${rm} "${fname}"
			fi
		done
	}

	install_release_file() {
 		local -r release_file="${modulefile_dir}/.release-${module_version}"

		if [[ -r "${release_file}" ]]; then
			local release
			read release < "${release_file}"
			if [[ "${release}" != "${module_release}" ]]; then
				std::info \
					"%s " \
					"${module_name}/${module_version}:" \
					"changing release from" \
					"'${release}' to '${module_release}' ..."
				echo "${module_release}" > "${release_file}"
			fi
		else
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"setting release to '${module_release}' ..."
			echo "${module_release}" > "${release_file}"
		fi
	}

	cleanup_build() {
		[[ ${enable_cleanup_build} == yes ]] || return 0
		[[ "${BUILD_DIR}" == "${SRC_DIR}" ]] && return 0
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
		[[ ${enable_cleanup_src} == yes ]] || return 0
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
			rm -rf "${SRC_DIR##*/}"
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
				   [[ ${force_rebuild} != 'yes' ]]; then
				return 0
			fi
			local targets=()
			targets+=( ${VERSIONS[@]/#/pbuild::pre_${target}_${system}_} )
			targets+=( pbuild::pre_${target}_${system} )
			targets+=( ${VERSIONS[@]/#/pbuild::pre_${target}_${OS}_} )
			targets+=( pbuild::pre_${target}_${OS} )
			targets+=( ${VERSIONS[@]/#/pbuild::pre_${target}_} )
			targets+=( pbuild::pre_${target} )

			targets+=( ${VERSIONS[@]/#/pbuild::${target}_${system}_} )
			targets+=( pbuild::${target}_${system} )
			targets+=( ${VERSIONS[@]/#/pbuild::${target}_${OS}_} )
			targets+=( pbuild::${target}_${OS} )
			targets+=( ${VERSIONS[@]/#/pbuild::${target}_} )
			targets+=( pbuild::${target} )

			targets+=( ${VERSIONS[@]/#/pbuild::post_${target}_${system}_} )
			targets+=( pbuild::post_${target}_${system} )
			targets+=( ${VERSIONS[@]/#/pbuild::post_${target}_${OS}_} )
			targets+=( pbuild::post_${target}_${OS} )
			targets+=( ${VERSIONS[@]/#/pbuild::post_${target}_} )
			targets+=( pbuild::post_${target} )

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
			[[ "${dry_run}" == 'no' ]] && ${rm} -rf ${PREFIX}
		fi
		if [[ -e "${modulefile_name}" ]]; then
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"removing modulefile '${modulefile_name}' ..."
			[[ "${dry_run}" == 'no' ]] && ${rm} -v "${modulefile_name}"
		fi
		local release_file="${modulefile_dir}/.release-${module_version}"
		if [[ -e "${release_file}" ]]; then
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"removing release file '${release_file}' ..."
			[[ "${dry_run}" == 'no' ]] && rm -v "${release_file}"
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
	load_build_dependencies
	init_build_environment "${module_name}" "${module_version}"

	source "${BUILD_SCRIPT}"
	
	# module name including path in hierarchy and version
	# (ex: 'gcc/6.1.0/openmpi/1.10.2' for openmpi compiled with gcc 6.1.0)
	local    modulefile_dir=''
	local    modulefile_name=''

	#
	# :FIXME: add comments what and why we are doing this.
	#
	local -r logfile="${BUILDBLOCK_DIR}/pbuild.log"
	rm -f "${logfile}"
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
	check_supported_os
	check_supported_compilers
	# setup module name and prefix
	set_full_module_name_and_prefix

	# ok, finally we can start ...
 	std::info \
		"%s " \
		"${module_name}/${module_version}:" \
		${with_modules:+build with ${with_modules[@]}}

	if [[ "${module_release}" == 'removed' ]]; then
		remove_module
	elif [[ "${module_release}" == 'deprecated' ]]; then
		deprecate_module
	elif [[ -d ${PREFIX} ]] && [[ ${force_rebuild} != 'yes' ]]; then
 		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"already exists, not rebuilding ..."
		if [[ "${opt_update_modulefiles}" == "yes" ]] || \
			   [[ ! -e "${modulefile_name}" ]]; then
			install_modulefile
		fi
		install_release_file
	else
		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"start building ..."
		compile_and_install
		post_install
	fi
	cleanup_modulefiles
	std::info "* * * * *\n"
}
readonly -f pbuild.build_module

# Local Variables:
# mode: sh
# sh-basic-offset: 8
# tab-width: 8
# End:
