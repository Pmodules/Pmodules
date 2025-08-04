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
declare -a SOURCE_NAMES=()
declare -a SOURCE_STRIP_DIRS=() 
declare -a SOURCE_UNPACKER=()
declare -a SOURCE_UNPACK_DIRS=()
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
	std::die 42 "%s " \
                 "${FUNCNAME[0]}: This function has been removed in Pmodules/1.1.22." \
		 "The group must be configured in the YAML configuration file!"
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
pbuild::use_flag() {
	[[ "${ModuleConfig['use_flags']}" =~ " ${1} " ]]
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
	std::die 42 "%s " \
                 "${FUNCNAME[0]}: This function has been removed in Pmodules/1.1.22." \
		 "The URL must be configured in the YAML configuration file!"
}
readonly -f pbuild::set_download_url

pbuild.set_urls(){
	local -n src="$1"
	local -i _i=${#SOURCE_URLS[@]}
	SOURCE_URLS[_i]="${src['url']}"
	SOURCE_NAMES[_i]="${src['name']}"
	SOURCE_STRIP_DIRS[_i]="${src['strip_dirs']}"
	SOURCE_UNPACKER[_i]="${src['unpacker']}"
	SOURCE_UNPACK_DIRS[_i]="${src['unpack_dir']}"
	SOURCE_PATCH_FILES[_i]="${src['patch_file']}"
	SOURCE_PATCH_STRIPS[_i]="${src['patch_strip']}"
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
	std::die 42 "%s " \
                 "${FUNCNAME[0]}: This function has been removed in Pmodules/1.1.22." \
		 "The SHA256 hash must be configured in the YAML configuration file!"
}
readonly -f pbuild::set_sha256sum

#..............................................................................
#
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
	std::die 42 "%s " \
                 "${FUNCNAME[0]}: This function has been removed in Pmodules/1.1.22." \
		 "The patch strip must be configured in the YAML configuration file!"
}
readonly -f pbuild::set_default_patch_strip

#..............................................................................
#
pbuild::unpack(){
	local -r fname="$1"
	local -- dir="$2"
	local -r strip="${3:-1}"
	local -r unpacker="${4:-${tar}}"

	if [[ -z "${dir}" ]]; then
		dir="${SRC_DIR}"
	else
		dir=$(envsubst <<<"${dir}")
	fi
	mkdir -p "${dir}"

	case "${unpacker}" in
		tar )
			tar \
				--directory="${dir}" \
				-xv \
				--exclude-vcs \
				--strip-components "${strip}" \
				-f "${fname}"
			;;
		7z )
			sevenz \
				x \
				-y \
				-o"${dir}" \
				"${fname}"
			;;
		none )
			cp "${fname}" "${dir}"
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
pbuild::pre_prep(){
	:
}
pbuild::post_prep(){
	:
}
pbuild::prep() {
	search_source_file(){
		local -n  ref_dir="$1"
		local -r fname="$2"
		local -a dirs=(
			"${PMODULES_DISTFILESDIR}"
			"${BUILDBLOCK_DIR}"
			"${BUILDBLOCK_DIR}/files"
		)
		# return if neither a URL nor a file name given
		[[ -n "${fname}" ]] || return 0
		local -- dir=''
		for dir in "${dirs[@]}"; do
			if [[ -r "${dir}/${fname}" ]]; then
				ref_dir="${dir}"
				return 0
			fi
		done
		ref_dir=''
		return 1
	}

	download_source_file() {
		local -- src_dir="$1"
		local -i idx="$2"
		if [[ -z "${SOURCE_NAMES[idx]}" ]]; then
			SOURCE_NAMES[idx]="${PMODULES_DISTFILESDIR}/${SOURCE_URLS[idx]##*/}"
		fi
		curl \
			--location \
				--fail \
				--output "${src_dir}/${SOURCE_NAMES[idx]}" \
				"${SOURCE_URLS[idx]}" || \
				std::die 42 \
					 "%s " \
					 "${module_name}/${module_version}:" \
					 "downloading source file '${fname}' failed!"

			# :FIXME: How to handle insecure downloads? 
			#if (( $? != 0 )); then
			#	curl \
			#		--insecure \
			#		--output "${fname}" \
			#		"${url}"
			#fi
	}

	unpack() {
		local -r  src_dir="$1"
		local -ri idx="$2"

		local -r fname="${src_dir}/${SOURCE_NAMES[idx]}"
		local -r dir="${SOURCE_UNPACK_DIRS[idx]}"
		local -r strip="${SOURCE_STRIP_DIRS[idx]}"
		local -r unpacker="${SOURCE_UNPACKER[idx]}"

		if ! pbuild::unpack "${fname}" "${dir}" "${strip}" "${unpacker}"; then
			${rm} -f "${fname}"
			std::die 4 \
				 "%s " \
				 "${module_name}/${module_version}:" \
				 "cannot unpack sources!"
		fi
	}

	check_hash_sum() {
		local -r  src_dir="$1"
		local -ri idx="$2"
		local -r fname="${SOURCE_NAMES[i]}"
		if [[ -v SHASUMS[${fname}] ]]; then
			local -- hash_sum=''
			hash_sum=$(sha256sum "${src_dir}/${fname}" | awk '{print $1}')
			test "${hash_sum}" == "${SHASUMS[${fname}]}" || \
				std::die 42 \
					 "%s " \
					 "${module_name}/${module_version}:" \
					 "hash-sum missmatch for file '${fname}'!"
			std::info "${module_name}/${module_version}: SHA256 hash sum is OK ..." 
		else
			std::info "${module_name}/${module_version}: SHA256 hash sum missing NOK ..." 
		fi

	}

	apply_patch(){
		local -r fname="$1"
		local -r strip="$2"
		local -r dir="$3"
		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"Appling patch '${fname}' ..."
		patch \
			--strip="${strip}" \
			--directory="${dir}" < "${fname}" || \
			std::die 4 \
				 "%s " \
				 "${module_name}/${module_version}:" \
				 "error patching sources!"
	}

	patch_sources() {
		local -i _i=0
		for ((_i = 0; _i < ${#PATCH_FILES[@]}; _i++)); do
			local -i strip=
			apply_patch \
				"${BUILDBLOCK_DIR}/${PATCH_FILES[_i]}" \
				"${PATCH_STRIPS[_i]:-${PATCH_STRIP_DEFAULT}}" \
				"${SRC_DIR}"
		done
	}

	(( ${#SOURCE_URLS[@]} == 0 )) && return 0
	mkdir -p "${PMODULES_DISTFILESDIR}"
	local -i i=0
	for ((i = 0; i < ${#SOURCE_URLS[@]}; i++)); do
		local -- src_dir=''
		local -i ec=0
		# if file name is not specified, use last component of URL as file name
		# check whether file exist
		# try to download if not and URL is specified
		[[ -z "${SOURCE_NAMES[i]}" ]] && SOURCE_NAMES[i]="${SOURCE_URLS[i]##*/}"
		if [[ -n "${SOURCE_NAMES[i]}" ]]; then
			if ! search_source_file src_dir "${SOURCE_NAMES[i]}"; then
				if [[ -n "${SOURCE_URLS[i]}" ]]; then
					src_dir="${PMODULES_DISTFILESDIR}"
					download_source_file "${src_dir}" "$i"
				fi
			fi
		fi
		if [[ -n "${SOURCE_NAMES[i]}" ]]; then
			check_hash_sum "${src_dir}" "$i"
			unpack "${src_dir}" "$i"
		fi
		if [[ -n "${SOURCE_PATCH_FILES[i]}" ]]; then
			search_source_file src_dir "${SOURCE_PATCH_FILES[i]}" || \
				std::die 42 \
					 "%s " \
					 "${module_name}/${module_version}:" \
					 "patch file '${SOURCE_PATCH_FILES[i]}' not found!"
			local -- target_dir=''
			if [[ -z "${SOURCE_UNPACK_DIRS[i]}" ]]; then
				target_dir="${SRC_DIR}"
			else
				target_dir="$(envsubst <<<"${SOURCE_UNPACK_DIRS[i]}")"
			fi
			mkdir -p "${target_dir}"

			apply_patch \
				"${src_dir}/${SOURCE_PATCH_FILES[i]}" \
				 "${SOURCE_PATCH_STRIPS[i]:-${PATCH_STRIP_DEFAULT}}" \
				"${target_dir}"
		fi
	done
	patch_sources
	# create build directory
	mkdir -p "${BUILD_DIR}"
}

###############################################################################
#
# functions to configure the sources

#..............................................................................
#
pbuild.set_configure_args(){
	CONFIGURE_ARGS=( "$@" )
}
readonly -f pbuild.set_configure_args

pbuild.add_configure_args(){
	CONFIGURE_ARGS+=( "$@" )
}
readonly -f pbuild.add_configure_args

#..............................................................................
#
pbuild::use_autotools() {
	std::die 42 "%s " \
                 "${FUNCNAME[0]}: This function has been removed in Pmodules/1.1.22." \
		 "Use the 'configure_with' key in the YAML configuration file!"
}
readonly -f pbuild::use_autotools

#..............................................................................
#
pbuild::use_cmake() {
	std::die 42 "%s " \
                 "${FUNCNAME[0]}: This function has been removed in Pmodules/1.1.22." \
		 "Use the 'configure_with' key in the YAML configuration file!"
}
readonly -f pbuild::use_cmake

pbuild.configure_with(){
	configure_with="$1"
}

#..............................................................................
#
# Set flag to build module in source tree.
#
# Arguments:
#   none
#
declare -- compile_in_sourcetree='no'

pbuild::compile_in_sourcetree() {
	std::die 42 "%s " \
                 "${FUNCNAME[0]}: This function has been removed in Pmodules/1.1.22." \
		 "Use the 'compile_in_sourcetree' key in the YAML configuration file!"
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
pbuild::pre_configure() {
	:
}
pbuild::post_configure() {
	:
}
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
		std::info "%s " "${SRC_DIR}/configure --prefix=${PREFIX} ${config_args[@]}"
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
pbuild::pre_compile() {
	:
}
pbuild::post_compile() {
	:
}
pbuild::compile() {
	local -- v_save="$V"
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
pbuild::pre_install() {
	:
}
pbuild::post_install() {
	:
}
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

declare -n ModuleConfig
declare -a Systems=()
declare -a UseOverlays=()
pbuild.build_module_yaml(){
	local -- module_name="$1"
	local -- module_version="$2"
	ModuleConfig="$3"

	eval $( "${modulecmd}" bash purge )
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

	local -- module_relstage="${ModuleConfig['relstage']}"
	if [[ -n "${ModuleConfig['systems']}" ]]; then
		readarray -t Systems <<< "${ModuleConfig['systems']}"
	fi
	if [[ -n "${ModuleConfig['use_overlays']}" ]]; then
		readarray -t UseOverlays <<< "${ModuleConfig['use_overlays']}"
	fi
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
	bm::is_loaded() {
		[[ :${LOADEDMODULES}: =~ :$1: ]]
	}

	bm::load_overlays(){
		[[ -n ${ModuleConfig['use_overlays']} ]] || return 0
		eval "$( "${modulecmd}" bash use ${ModuleConfig['use_overlays']} )"
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
	bm::load_build_dependencies() {

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
				local -- p="$1"
				local -- script=''
				script=$(${find} "${BUILDBLOCK_DIR}/../.." \
						 -path "*/$p/build")
				std::get_abspath "${script}"
			}

			local -r m="$1"
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

			local -- buildscript=''
			buildscript=$(find_build_script "${m%/*}")
			[[ -x "${buildscript}" ]] || \
				std::die 1 \
					 "$m: build-block not found!"
			if ! "${buildscript}" "${m#*/}" "${args[@]}"; then
				std::die 1 \
					 "$m: oops: build failed..."
			fi
		}

		local -- m=''
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
			bm::is_loaded "$m" && continue

			# 'module avail' might output multiple matches if module
			# name and version are not fully specified or in case
			# modules with and without a release number exist.
			# Example:
			# mpc/1.1.0 and mpc/1.1.0-1. Since we get a sorted list
			# from 'module avail' and the full version should be set
			# in the variants file, we look for the first exact
			# match.
			local -- release_of_dependency=''
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
			if ! bm::is_loaded "$m"; then
				"${modulecmd}" bash list
				std::die 5 \
					 "%s " "${m}:" \
					 "module cannot be loaded!"
			fi
		done
	} # bm::load_build_dependencies

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
	bm::set_full_module_name_and_prefix() {
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

		modulefile_dir="${ol_modulefiles_root}/${GROUP}/${__MODULEFILES_DIR__}/"
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
	} # bm::set_full_module_name_and_prefix
	
	#......................................................................
	# post-install.
	#
	# Arguments:
	#	none
	bm::post_install() {
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

		patch_elf64_files(){
			local -- libdir="${OverlayInfo[${ol_name}:install_root]}/lib64"
			[[ -d "${libdir}" ]] || return 0
			local -a bin_objects=()
			mapfile -t files < <(std::find_elf64_binaries '.')
			local -- fname=''
			local -- rpath=''
			local -i depth=0
			for fname in "${files[@]}"; do
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
			{
				cd "${PREFIX}"
				[[ -d "lib" ]] && [[ ! -d "lib64" ]] && ln -s lib lib64
				patch_elf64_files
			};
			return 0
		}

		#..............................................................
		# post-install
		cd "${BUILD_DIR}"
		[[ "${KernelName}" == "Linux" ]] && post_install_linux
		install_doc
		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"Done ..."
		return 0
	} # bm::post_install

		#
	# write modulefile, configuration and dependencies
	#
	bm::install_module_config(){

 		#......................................................................
		# Install modulefile in ${ol_modulefiles_root}/${GROUP}/modulefiles/...
		# The modulefiles in the build-block can be
		# versioned like
		#     modulefile-10.2.0
		#     modulefile-10.2
		#     modulefile-10
		#     modulefile
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
				local -- fname=''
				for fname in "${VERSIONS[@]/#/modulefile-}" 'modulefile'; do
					if [[ -r "${BUILDBLOCK_DIR}/${fname}" ]]; then
						_modulefile="${BUILDBLOCK_DIR}/${fname}"
						break;
					fi
				done
				[[ -n "${_modulefile}" ]]
			}
			[[ "${is_subpkg}" == 'yes' ]] && return 0
			local -- src=''
			if [[ -n "${ModuleConfig['modulefile']}" ]]; then
				src="${ModuleConfig['modulefile']}"
			elif ! find_modulefile src; then
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

		#..............................................................
		# post-install: write file with required modules
		install_runtime_dependencies() {
			_write_file(){
				local -r fname="$1"
				shift
				std::info \
					"%s " \
					"${module_name}/${module_version}:" \
					"writing run-time dependencies to ${fname} ..."
				echo -n "" > "${fname}"
				local -- dep=''
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
			if (( ${#runtime_dependencies[@]} > 0 )); then
				if [[ "${ol_name}" == 'base' ]]; then
					_write_file \
						"${PREFIX}/${FNAME_RDEPS}" \
						"${runtime_dependencies[@]}"
				fi
				_write_file \
					"${modulefile_dir}/.deps-${module_version}" \
					"${runtime_dependencies[@]}"
			fi
			if (( ${#install_dependencies[@]} > 0 )); then
				_write_file \
					"${PREFIX}/${FNAME_IDEPS}" \
					"${install_dependencies[@]}"
			fi

		}

		install_config_file() {
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
			if [[ "${opt_update_modulefiles}" == 'yes' ]]; then
				status_yaml_config_file='update'
			elif [[ -r "${yaml_config_file}" ]]; then
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
					local -- system=''
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

		if [[ "${opt_update_modulefiles}" == "yes" ]] || \
			   [[ ! -e "${modulefile_name}" ]]; then
			install_modulefile
		fi
		install_runtime_dependencies
		install_config_file
	}

	bm::cleanup_modulefiles(){
		#
		# FIXME: Can it happen, that we remove module-/config-files which
		#        we shouldn't remove?
		#        For now we exclude removing from the overlay 'base' only
		#	 This function is only called if the option '--cleanup-modulefiles'
		#	 was specified.
		#
		[[ "${is_subpkg}" == 'yes' ]] && return 0
		local -- ol=''
		for ol in "${Overlays[@]}"; do
			[[ "${ol}" == "${ol_name}" ]] && continue
			[[ "${ol}" == 'base' ]] && continue
			local -- modulefiles_root="${OverlayInfo[${ol}:modulefiles_root]}"
			local -- dir="${modulefile_dir/${ol_modulefiles_root}/${modulefiles_root}}"
			local -- fname="${dir}/${module_version}"
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

	bm::cleanup_build() {
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

	bm::cleanup_src() {
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
	bm::compile_and_install() {
		build_target() {
			local -- dir="$1"		# src or build directory, depends on target
			local -- target="$2"	# prep, configure, compile or install

			if [[ -e "${BUILD_DIR}/.${target}" ]] && \
				   [[ ${force_rebuild} == 'no' ]]; then
				return 0
			fi
			debug "build functions for target ${target}: ${ModuleConfig[target_funcs:${target}]}"
			local -- t=''
			if (( ${#ModuleConfig[target_funcs:${target}]} == 0 )); then
				${touch} "${BUILD_DIR}/.${target}"
				return 0
			fi
			local -A target_info=(
				[prep]='preparing sources'
				[configure]='configuring'
				[compile]='compiling'
				[install]='installing'
			)
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"${target_info[${target}]} ..."
			local -- t=''
			for t in ${ModuleConfig[target_funcs:${target}]}; do
				# We cd into the dir before calling the function -
				# just to be sure we are in the right directory.
				#
				# Executing the function in a sub-process doesn't
				# work because in some function global variables
				# might/need to be set.
				#
				cd "${dir}"
				if typeset -F "$t" 2>/dev/null; then
					"$t" || std::die 10 "Aborting..."
				else
					std::die 10 "Function is not defined -- $t"
				fi
			done
			${touch} "${BUILD_DIR}/.${target}"
		} # build_target()

		[[ ${dry_run} == yes ]] && std::die 0 ""

		${mkdir} -p "${SRC_DIR}"
		${mkdir} -p "${BUILD_DIR}"

		build_target "${SRC_DIR}" prep
		[[ "${build_target}" == "prep" ]] && return 0

		build_target "${BUILD_DIR}" configure
		[[ "${build_target}" == "configure" ]] && return 0

		build_target "${BUILD_DIR}" compile
		[[ "${build_target}" == "compile" ]] && return 0

		${mkdir} -p "${PREFIX}"
		build_target "${BUILD_DIR}" install
	} # bm::compile_and_install()

	bm::remove_module() {
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
		local -- release_file="${modulefile_dir}/.release-${module_version}"
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

	bm::deprecate_module(){
		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"is deprecated, skiping!"
		bm::install_module_config
	}

	die_sub_package_name_missing(){
		std::die 3 "Name of sub-package not specified in \n===\n$1\n===\n"
	}
	die_sub_package_version_missing(){
		std::die 3 "Version of sub-package not specified in \n===\n$1\n===\n"
	}
	bm::build_sub_packages(){
		local -- yaml="$1"

		# get no of sub-packages to build
		local -i l=0
		yml::get_seq_length l yaml .
		(( l == 0 )) && return 0

		std::info "\n %d sub-package(s) to build..." "$l"
		local -i i=0
		local -- fname=''
		for ((i=0; i<l; i++)); do
			local -- node=".[$i]"
			local -- pkg_name=''
			local -- pkg_version=''
			local -a pkg_build_args=()

			local -- key=''
			local -a keys=()
			yml::get_keys keys yaml "${node}"
			for key in "${keys[@]}"; do
				case ${key,,} in
					'name' )
						yml::get_value \
							pkg_name \
							yaml \
							"${node}.${key}" \
							'!!str' || \
							yml::die_parsing "${yaml}"
						;;
					'version' )
						yml::get_value \
							pkg_version \
							yaml \
							"${node}.${key}" \
							'!!str' || \
							yml::die_parsing "${yaml}"
						;;
					'build_args' )
						local -- value=''
						yml::get_seq \
							value \
							yaml \
							"${node}.${key}" || \
							yml::die_parsing "${yaml}"
						readarray -t pkg_build_args <<< "${value}"
						;;
					* )
						die_invalid_key \
							"${yaml}" \
							"in subpackage '$i'" \
							"${key}"
						;;
				esac
			done
			[[ -n "${pkg_name}" ]] || \
				die_sub_package_name_missing "${yaml}"
			[[ -n "${pkg_version}" ]] || \
				die_sub_package_version_missing "${yaml}"

			[[ "${opt_verbose}" == 'yes' ]] && \
				pkg_build_args+=( '--verbose' )
			[[ "${opt_debug}" == 'yes' ]] && \
				pkg_build_args+=( '--debug' )
			[[ "${opt_force_rebuild}" == 'yes' ]] && \
				pkg_build_args+=( '-f' )
			pkg_build_args+=( "--parent-prefix=${PREFIX}" )
			"$BUILDBLOCK_DIR/build-${pkg_name}" \
				"${pkg_name}/${pkg_version}" \
				"${pkg_build_args[@]}"
		done
		debug "Building sub-packages done"
	}


	std::info \
		"%s " \
		"${module_name}/${module_version}:" \
		${with_modules:+with ${with_modules[@]}} \
		"building ..."

	bm::load_overlays
	bm::load_build_dependencies
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
	local -- modulefile_dir=''
	local -- modulefile_name=''

	# the group must have been defined - otherwise we cannot continue
	[[ -n ${GROUP} ]] || \
		std::die 5 \
			 "%s " "${module_name}/${module_version}:" \
			 "Module group not set! Aborting ..."

	[[ "${is_subpkg}" != 'yes' ]] && bm::set_full_module_name_and_prefix

	# ok, finally we can start ...
 	std::info \
		"%s " \
		"${module_name}/${module_version}:" \
		${with_modules:+build with ${with_modules[@]}}

	if [[ "${module_release}" == 'remove' ]]; then
		bm::remove_module
	elif [[ "${module_release}" == 'deprecated' ]]; then
		bm::deprecate_module
	elif [[ -d "${PREFIX}" && "${is_subpkg}" != 'yes' ]] && [[ "${force_rebuild}" == 'no' ]]; then
 		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"already exists, not rebuilding ..."
		bm::install_module_config
	else
		if [[ "${opt_clean_install,,}" == 'yes' ]]; then
			std::info \
				"%s " \
				"${module_name}/${module_version}:" \
				"remove module, if already exists ..."
			bm::remove_module
		fi
		std::info \
			"%s " \
			"${module_name}/${module_version}:" \
			"start building ..."
		bm::cleanup_build
		bm::cleanup_src
		bm::compile_and_install
		bm::post_install
		bm::install_module_config
		bm::cleanup_build
		bm::cleanup_src
		bm::build_sub_packages "${ModuleConfig['sub_packages']}"

	fi
	if [[ "${opt_cleanup_modulefiles}" == 'yes' ]]; then
		bm::cleanup_modulefiles
	fi
 	std::info \
		"\n%s\n%s" \
		"${module_name}/${module_version}: done" \
		"* * * * *"
}
readonly -f _build_module

# Local Variables:
# mode: sh
# sh-basic-offset: 8
# tab-width: 8
# End:
