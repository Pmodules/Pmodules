#!/bin/bash

#.............................................................................
#
# We need GNU versions of the following utilities. This code works
# well on Linux and Mac OS X with MacPorts.
# :FIXME: implement a smarter, portable solution.
#
shopt -s expand_aliases
unalias -a

__path=$(which gsed 2>/dev/null || : )
if [[ $__path ]]; then
	alias sed=$__path
else
	alias sed=$(which sed 2>/dev/null)
fi
unset __path

#.............................................................................
# disable auto-echo feature of 'cd'
unset CDPATH

#.............................................................................
#
# Exit script on errror.
#
# $1	exit code
#
set -o errexit

error_handler() {
	local -i ec=$?

	std::die ${ec} "Oops"
}

trap "error_handler" ERR

###############################################################################
#
# unset environment variables used for compiling
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

declare	SOURCE_URLS=()
declare SOURCE_SHA256_SUMS=()
declare SOURCE_NAMES=()

declare	SOURCE_FILE=()
declare	CONFIGURE_ARGS=()
declare SUPPORTED_SYSTEMS=()
declare PATCH_FILES=()
declare PATCH_STRIPS=()
declare PATCH_STRIP_DEFAULT='1'
declare configure_with='undef'	

#..............................................................................
# global variables used in the library

declare -r  OS="${SYSTEM}"

# module name including path in hierarchy and version
# (ex: 'gcc/6.1.0/openmpi/1.10.2' for openmpi compiled with gcc 6.1.0)
declare -x  fully_qualified_module_name=''

# group this module is in (ex: 'Programming')
declare -x  GROUP=''

# release of module (ex: 'stable')
declare	-x  module_release=''

# relative path of documentation
# abs. path is "${PREFIX}/${_docdir}/${module_name}"
declare -r  _DOCDIR='share/doc'

#..............................................................................
#
# The following variables are available in build-blocks and set read-only
# :FIXME: do we have to export them?
#

# install prefix of module.
declare -x  PREFIX=''

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

##############################################################################
#
# Check whether the script is running on a supported OS.
#
# Arguments:
#   $@: supported opertating systems (as printed by 'uname -s')
#
pbuild::supported_systems() {
	SUPPORTED_SYSTEMS+=( "$@" )
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
#	fully_qualified_module_name
#	PREFIX
#
set_full_module_name_and_prefix() {
	join_by() {
		local IFS="$1"
		shift
		echo "$*"
	}

	[[ -n ${GROUP} ]] || std::die 1 "${module_name}/${module_version}: group not set."
	
	# build module name
	# :FIXME: this should be read from a configuration file
	local name=()
	case ${GROUP} in
	Compiler )
		name+=( "${COMPILER}/${COMPILER_VERSION}" )
	        name+=( "${module_name}/${module_version}" )
		;;
	MPI )
		name+=( "${COMPILER}/${COMPILER_VERSION}" )
		name+=( "${MPI}/${MPI_VERSION}" )
		name+=( "${module_name}/${module_version}" )
		;;
	HDF5 )
		name+=( "${COMPILER}/${COMPILER_VERSION}" )
		name+=( "${MPI}/${MPI_VERSION}" )
		name+=( "${HDF5}/${HDF5_VERSION}" )
		name+=( "${module_name}/${module_version}" )
		;;
	OPAL )
		name+=( "${COMPILER}/${COMPILER_VERSION}" )
		name+=( "${MPI}/${MPI_VERSION}" )
		name+=( "${OPAL}/${OPAL_VERSION}" )
		name+=( "${module_name}/${module_version}" )
		;;
	HDF5_serial )
		name+=( "${COMPILER}/${COMPILER_VERSION}" )
		name+=( "hdf5_serial/${HDF5_SERIAL_VERSION}" )
		name+=( "${module_name}/${module_version}" )
		;;
	* )
		name+=("${module_name}/${module_version}" )
		;;
	esac

	# set full module name
	fully_qualified_module_name=$( join_by '/' "${name[@]}" )
	# set PREFIX of module
	PREFIX="${PMODULES_ROOT}/${GROUP}/"
        local -i i=0
	for ((i=${#name[@]}-1; i >= 0; i--)); do
		PREFIX+="${name[i]}/"
	done
}

##############################################################################
#
# Install module in given group.
#
# Arguments:
#   $1: group
#
pbuild::add_to_group() {
	if [[ -z ${1} ]]; then
		std::die 42 \
                         "%s " "${module_name}/${module_version}:" \
                         "${FUNCNAME}: missing group argument."
	fi
	GROUP="$1"
	set_full_module_name_and_prefix
}

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

##############################################################################
#
# Test whether a module with the given name is available. If yes, return
# release
#
# Arguments:
#   $1: module name
#   $2: optional variable name to return release via upvar
#
# Notes:
#   The passed module name must be NAME/VERSION! 
#
pbuild::module_is_avail() {
	local "$2"
	local uvar="$2"
	[[ -n "${uvar}" ]] || uvar="__unused__"
	local output=( $("${MODULECMD}" bash avail -a -m "$1" \
                                        2>&1 1>/dev/null) )
	[[ "${output[0]}" == "$1" ]] && std::upvar "${uvar}" "${output[1]}"
}

pbuild::set_download_url() {
	local -i _i=${#SOURCE_URLS[@]}
	SOURCE_URLS[_i]="$1"
	SOURCE_NAMES[_i]="$2"
}

pbuild::set_sha256sum() {
	SOURCE_SHA256_SUMS+=("$1")
}

pbuild::use_cc() {
	[[ -x "$1" ]] || std::die 3 \
                                  "%s " "${module_name}/${module_version}:" \
                                  "Error in setting CC:" \
                                  "'$1' is not an executable!"
	CC="$1"
}

#......................................................................
#
# Find/download tarball for given module.
# If the source URL is given, we look for the file-name specified in
# the URL. Otherwise we test for several possible names/extensions.
#
# The downloaded file will be stored with the name "${module_name}-${module_version}" and extension
# derived from URL. The download directory is the first directory passed.
#
# Arguments:
#   $1:	    store file name with upvar here
#   $2:	    download URL 
#   $3:	    output filename (can be empty string)
#   $4...:  download directories
#
# Returns:
#   0 on success otherwise a value > 0
#
download_source_file() {
	check_hash_sum() {
		local -r fname="$1"
		local -r expected_hash_sum="$2"
		local hash_sum=''

		if which 'sha256sum' 1>/dev/null; then
			hash_sum=$(sha256sum "${fname}" | awk '{print $1}')
		elif which 'shasum' 1>/dev/null; then
			hash_sum=$(shasum -a 256 "${fname}" | awk '{print $1}')
		else
			std::die 42 \
                                 "%s " "${module_name}/${module_version}:" \
                                 "Binary to compute SHA256 sum missing!"
		fi
		test "${hash_sum}" == "${expected_hash_sum}" || \
                        std::die 42 \
			         "%s " "${module_name}/${module_version}:" \
                                 "hash-sum missmatch for file '%s'" "${fname}"
	}

	local "$1"
	local var="$1"
	local -r url="$2"
	local    fname="$3"
	shift 3
	dirs+=( "$@" )

	[[ -n "${fname}" ]] || fname="${url##*/}"
	local expr='s/.*\(.tar.bz2\|.tbz2\|.tar.gz\|.tgz\|.tar.xz\|.zip\)/\1/'
	local -r extension=$(echo ${fname} | sed "${expr}")
	local dir=''
	dirs+=( 'not found' )
	for dir in "${dirs[@]}"; do
		[[ -r "${dir}/${fname}" ]] && break
	done
	if [[ "${dir}" == 'not found' ]]; then
		dir="${dirs[0]}"
		local -r method="${url%:*}"
		case "${method}" in
			http | https | ftp )
				curl \
				    -L \
				    --output "${dir}/${fname}" \
				    "${url}"
				if (( $? != 0 )); then
					curl \
					    --insecure \
					    --output "${dir}/${fname}" \
					    "${url}"
				fi
				;;
			* )
				std::die 4 \
                                         "%s " "${module_name}/${module_version}:" \
                                         "Error in download URL:" \
					 "unknown download method '${method}'!"
				;;
                esac
	fi
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
	std::upvar "${var}" "${dir}/${fname}"
	[[ -r "${dir}/${fname}" ]]
}

pbuild::pre_prep() {
	:
}
eval "pbuild::pre_prep_${SYSTEM}() { :; }"

pbuild::post_prep() {
	:
}
eval "pbuild::post_prep_${SYSTEM}() { :; }"

###############################################################################
#
# extract sources. For the time being only tar-files are supported.
#
pbuild::prep() {
	unpack() {
		local -r file="$1"
		local -r dir="$2"
		(
			if [[ -n "${dir}" ]]; then
				mkdir -p "${dir}"
				cd "${dir}"
			fi
			tar -xv --strip-components 1 -f "${file}"
		)
	}

	patch_sources() {
		cd "${SRC_DIR}"
                local i=0
		for ((_i = 0; _i < ${#PATCH_FILES[@]}; _i++)); do
			std::info \
                                "%s " "${module_name}/${module_version}:" \
                                "Appling patch '${PATCH_FILES[_i]}' ..."
			local -i strip_val="${PATCH_STRIPS[_i]:-${PATCH_STRIP_DEFAULT}}"
			patch -p${strip_val} < "${BUILDBLOCK_DIR}/${PATCH_FILES[_i]}"
		done
	}

	[[ -z "${SOURCE_URLS}" ]] && \
                std::die 3 \
                         "%s " "${module_name}/${module_version}:" \
                         "Download source not set!"
        local i=0
	for ((i = 0; i < ${#SOURCE_URLS[@]}; i++)); do
		download_source_file \
		    SOURCE_FILE \
		    "${SOURCE_URLS[i]}" \
		    "${SOURCE_NAMES[i]}" \
		    "${PMODULES_DISTFILESDIR}" \
		    "${BUILDBLOCK_DIR}" ||
		        std::die 4 \
                                 "%s " "${module_name}/${module_version}:" \
                                 "sources for not found."
		unpack "${SOURCE_FILE}" "${SRC_DIR}"
	done
	patch_sources
	# create build directory
	mkdir -p "${BUILD_DIR}"
}

pbuild::add_patch() {
	[[ -z "$1" ]] && \
                std::die 1 \
                         "%s " "${module_name}/${module_version}:" \
                         "${FUNCNAME}: missing argument!"
	PATCH_FILES+=( "$1" )
	PATCH_STRIPS+=( "$2" )
}
eval "pbuild::add_patch_${SYSTEM}() { pbuild::add_patch \"\$@\"; }"

pbuild::set_default_patch_strip() {
	[[ -n "$1" ]] || \
                std::die 1 \
                         "%s " "${module_name}/${module_version}:" \
                         "${FUNCNAME}: missing argument!"

	PATCH_STRIP_DEFAULT="$1"
}

pbuild::use_flag() {
	[[ "${USE_FLAGS}" =~ ":${1}:" ]]
}

###############################################################################
#
#
pbuild::pre_configure() {
	:
}
eval "pbuild::pre_configure_${SYSTEM}() { :; }"

pbuild::set_configure_args() {
	CONFIGURE_ARGS+=( "$@" )
}

pbuild::add_configure_args() {
	CONFIGURE_ARGS+=( "$@" )
}

pbuild::use_autotools() {
	if [[ -r "${SRC_DIR}/configure" ]]; then
		configure_with='autotools'
	else
		std::die 3 \
                         "%s " "${module_name}/${module_version}:" \
                         "${FNCNAME[0]}:" \
                         "autotools configuration not available, aborting..."
	fi
}

pbuild::use_cmake() {
	if [[ -r "${SRC_DIR}/CMakeLists.txt" ]]; then
		configure_with='cmake'
	else
		std::die 3 \
                         "%s " "${module_name}/${module_version}:" \
                         "${FNCNAME[0]}:" \
                         "CMake script not available, aborting..."
	fi
}

pbuild::configure() {
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
		cmake \
			-DCMAKE_INSTALL_PREFIX="${PREFIX}" \
			"${CONFIGURE_ARGS[@]}" \
			"${SRC_DIR}" || \
                        std::die 3 \
                                 "%s " "${module_name}/${module_version}:" \
                                 "cmake failed"
	else
		std::info \
                        "%s " "${module_name}/${module_version}:" \
                        "${FUNCNAME[0]}: skipping..."
	fi
}

pbuild::post_configure() {
	:
}
eval "pbuild::post_configure_${SYSTEM}() { :; }"

pbuild::pre_compile() {
	:
}
eval "pbuild::pre_compile_${SYSTEM}() { :; }"

pbuild::compile() {
	make -j${JOBS}
}

pbuild::post_compile() {
	:
}
eval "pbuild::post_compile_${SYSTEM}() { :; }"

pbuild::pre_install() {
	:
}
eval "pbuild::pre_install_${SYSTEM}() { :; }"

pbuild::install() {
	make install
}

pbuild::install_shared_libs() {
	local -r binary="${PREFIX}/$1"
	local -r pattern="$2"
	local -r dstdir="${3:-${PREFIX}/lib}"

	test -e "${binary}" || \
                std::die 3 \
                         "%s " "${module_name}/${module_version}:" \
                         "${binary}: does not exist or is not executable!"
	mkdir -p "${dstdir}"
	local -r libs=( $(ldd "${binary}" | \
                                  awk "/ => \// && /${pattern}/ {print \$3}") )
	cp -avL "${libs[@]}" "${dstdir}"
}

pbuild::post_install() {
	:
}
eval "pbuild::post_install_${SYSTEM}() { :; }"

pbuild::cleanup_build() {
	[[ "${BUILD_DIR}" == "${SRC_DIR}" ]] && return 0

	# the following two checks we should de earlier!	
	[[ -z "${BUILD_DIR}" ]] && \
	        std::die 1 \
                         "%s " "${module_name}/${module_version}:" \
                         "Oops: internal error:" \
			 "BUILD_DIR is unset or set to empty string"
	[[ ! -d "/${BUILD_DIR}" ]] && \
		std::die 1 \
                         "%s " "${module_name}/${module_version}:" \
                         "Oops: internal error: " \
			 "BUILD_DIR=${BUILD_DIR} is not a directory"

	{
		cd "/${BUILD_DIR}/.."
		[[ "$(pwd)" == "/" ]] && \
		        std::die 1 \
                                 "%s " "${module_name}/${module_version}:" \
                                 "Oops: internal error:" \
			     	 "BUILD_DIR is set to '/'"

		std::info \
                        "%s " "${module_name}/${module_version}:" \
                        "Cleaning up '${BUILD_DIR}'..."
		rm -rf "${BUILD_DIR##*/}"
	};
	return 0
}

pbuild::cleanup_src() {
	[[ -d /${SRC_DIR} ]] || return 0
    	{
		cd "/${SRC_DIR}/..";
		[[ $(pwd) == / ]] && \
		        std::die 1 \
                                 "%s " "${module_name}/${module_version}:" \
                                 "Oops: internal error:" \
			     	 "SRC_DIR is set to '/'"
		std::info \
                        "%s " "${module_name}/${module_version}:" \
                        "Cleaning up '${SRC_DIR}'..."
		rm -rf "${SRC_DIR##*/}"
   	};
	return 0
}

#
# The 'do it all' function.
#
pbuild::make_all() {
	local -a runtime_dependencies=()

	#
	# everything set up?
	#
	[[ -n ${GROUP} ]] || \
                std::die 5 \
                         "%s " "${module_name}/${module_version}:" \
                         "Module group not set! Aborting ..."

	#
	# helper functions
	#

	#......................................................................
	check_supported_systems() {
		[[ -z "${SUPPORTED_SYSTEMS}" ]] && return 0
		for sys in "${SUPPORTED_SYSTEMS[@]}"; do
			[[ ${sys} == ${SYSTEM} ]] && return 0
		done
		std::die 1 \
                         "%s " "${module_name}/${module_version}:" \
                         "Not available for ${SYSTEM}."
	}

	#......................................................................
	#
	# test whether a module is loaded or not
	#
	# $1: module name
	#
	is_loaded() {
		[[ :${LOADEDMODULES}: =~ :$1: ]]
	}

 	#......................................................................
	#
	# build a dependency
	#
	# $1: name of module to build
	#
	# :FIXME: needs testing
	#
	build_dependency() {
		#..............................................................
		#
		# Test whether a module with the given name already exists.
		#
		# Arguments:
		#   $1: module name
		#
		# Notes:
		#   The passed module name should be NAME/VERSION
		#   :FIXME: this does not really work in a hierarchical group
                #           without adding the dependencies...
		#
		module_exists() {
			[[ -n $("${MODULECMD}" bash search -a --no-header "$1" \
					       2>&1 1>/dev/null) ]]
		}


		local -r m=$1
		std::debug "${m}: module not available"
		local rels=( ${PMODULES_DEFINED_RELEASES//:/ } )
		[[ ${dry_run} == yes ]] && \
			std::die 1 \
                                 "%s " \
				 "${m}: module does not exist," \
				 "cannot continue with dry run..."

		std::info "$m: module does not exist, trying to build it..."
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

		local buildscript=$( std::get_abspath "${BUILDBLOCK_DIR}"/../../*/${m/\/*}/build )
		[[ -x "${buildscript}" ]] || \
                        std::die 1 \
                                 "$m: build-block not found!"
		"${buildscript}" "${m#*/}" ${args[@]}
		module_exists "$m" || \
                        std::die 1 \
                                 "$m: oops: build failed..."
	}
	
	#......................................................................
	#
	# Load build- and run-time dependencies.
	#
	# Arguments:
	#   none
	#
	# Variables
	#   [r] module_release	    set if defined in a variants file
	#   runtime_dependencies    runtime dependencies from variants added
	#
	load_build_dependencies() {
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
                                     && [[ "${release_of_dependency}" != 'deprecated' ]]; then
                                std::die 5 \
                                         "%s " "${module_name}/${module_version}:" \
                                         "release cannot be set to '${module_release}'" \
                                         "since the dependency '$m' is ${release_of_dependency}"
			fi
			
			echo "Loading module: ${m}"
			module load "${m}"
		done
	}

	#......................................................................
	# non-redefinable post-install
	post_install() {
		install_doc() {
			test -n "${MODULE_DOCFILES}" || return 0
			local -r docdir="${PREFIX}/${_DOCDIR}/${module_name}"

			std::info \
                                "%s " "${module_name}/${module_version}:" \
                                "Installing documentation to ${docdir}"
			install -m 0755 -d \
                                "${docdir}"
			install -m0444 \
                                "${MODULE_DOCFILES[@]/#/${SRC_DIR}/}" \
				"${docdir}"
			return 0
		}

		#..............................................................
		# install build-block
		# Skip installation if modulefile does not exist.
		install_pmodules_files() {
			test -r "${BUILDBLOCK_DIR}/modulefile" || return 0

			local -r target_dir="${PREFIX}/share/$GROUP/${module_name}"
			install -m 0756 \
                                -d "${target_dir}/files"
			install -m0444 \
                                "${BUILD_SCRIPT}" \
                                "${target_dir}"
			install -m0444 \
                                "${BUILDBLOCK_DIR}/modulefile" \
                                "${target_dir}"
			#install -m0444 \
                        #        "${variants_file}" \
                        #        "${target_dir}/files"

			local -r fname="${target_dir}/dependencies"
			"${MODULECMD}" bash list -t 2>&1 1>/dev/null | \
					grep -v "Currently Loaded" > "${fname}" || :
		}

		#..............................................................
		# write run time dependencies to file
		write_runtime_dependencies() {
			local -r fname="${PREFIX}/.dependencies"
			std::info \
                                "%s " "${module_name}/${module_version}:" \
                                "writing run-time dependencies to ${fname} ..."
			local dep
			echo -n "" > "${fname}"
			for dep in "${runtime_dependencies[@]}"; do
				[[ -z $dep ]] && continue
				if [[ ! $dep =~ .*/.* ]]; then
					# no version given: derive the version
					# from the currently loaded module
					dep=$( "${MODULECMD}" bash list -t 2>&1 1>/dev/null \
							| grep "^${dep}/" )
				fi
				echo "${dep}" >> "${fname}"
			done
		}


		# sometimes we need an system depended post-install
		post_install_linux() {
			std::info \
                                "%s " "${module_name}/${module_version}:" \
                                "running post-installation for ${SYSTEM} ..."
			cd "${PREFIX}"
			# solve multilib problem with LIBRARY_PATH
                        # on 64bit Linux
			[[ -d "lib" ]] && [[ ! -d "lib64" ]] && ln -s lib lib64
			return 0
		}

		cd "${BUILD_DIR}"
		[[ "${SYSTEM}" == "Linux" ]] && post_install_linux
		install_doc
		install_pmodules_files
		write_runtime_dependencies
		return 0
	}

 	#......................................................................
	# Install modulefile
	install_modulefile() {
		local -r src="${BUILDBLOCK_DIR}/modulefile"
		if [[ ! -r "${src}" ]]; then
			std::info \
                                "%s " "${module_name}/${module_version}:" \
                                "skipping modulefile installation ..."
			return
		fi
		# assemble name of modulefile
		local dst="${PMODULES_ROOT}/"
		dst+="${GROUP}/"
		dst+="${PMODULES_MODULEFILES_DIR}/"
		dst+="${fully_qualified_module_name}"

		# directory where to install modulefile
 		local -r dstdir=${dst%/*}

		std::info \
                        "%s " "${module_name}/${module_version}:" \
                        "installing modulefile in '${dstdir}' ..."
		mkdir -p "${dstdir}"
		install -m 0444 "${src}" "${dst}"
	}

        install_release_file() {
		local dst="${PMODULES_ROOT}/"
		dst+="${GROUP}/"
		dst+="${PMODULES_MODULEFILES_DIR}/"
		dst+="${fully_qualified_module_name}"

		# directory where to install release file
                local -r dstdir=${dst%/*}
                mkdir -p "${dstdir}"
                
 		local -r release_file="${dst%/*}/.release-${module_version}"

                if [[ -r "${release_file}" ]]; then
                        local release
                        read release < "${release_file}"
                        if [[ "${release}" != "${module_release}" ]]; then
		                std::info \
                                        "%s " "${module_name}/${module_version}:" \
                                        "changing release from '${release}' to '${module_release}' ..."
		                echo "${module_release}" > "${release_file}"
                        fi
                else
		        std::info \
                                "%s " "${module_name}/${module_version}:" \
                                "setting release to '${module_release}' ..."
                        echo "${module_release}" > "${release_file}"
                fi
        }
        
	build_target() {
		local dir="$1"
		local target="$2"
		if [[ ! -e "${BUILD_DIR}/.${target}" ]] || \
			[[ ${force_rebuild} == 'yes' ]]; then
			# We cd into the dir before every function call -
			# just in case there was a cd in the called function.
			# 
			# Executing the function in a sub-process doesn't
			# work because in some function global variables 
			# might to be set.
			#
			cd "${dir}" && "pbuild::pre_${target}_${SYSTEM}"
			cd "${dir}" && "pbuild::pre_${target}"
			cd "${dir}" && "pbuild::${target}"
			cd "${dir}" && "pbuild::post_${target}_${SYSTEM}"
			cd "${dir}" && "pbuild::post_${target}"
			touch "${BUILD_DIR}/.${target}"
		fi
	}

	#......................................................................
	# build module ${module_name}/${module_version}
	build_module() {
 		std::info \
                        "%s " "${module_name}/${module_version}:" \
                        "start building ..."
		[[ ${dry_run} == yes ]] && std::die 0 ""

		mkdir -p "${SRC_DIR}"
		mkdir -p "${BUILD_DIR}"

		build_target "${SRC_DIR}" prep
		[[ "${build_target}" == "prep" ]] && return 0

		build_target "${BUILD_DIR}" configure
		[[ "${build_target}" == "configure" ]] && return 0

		build_target "${BUILD_DIR}" compile
		[[ "${build_target}" == "compile" ]] && return 0

		build_target "${BUILD_DIR}" install
		post_install

		[[ "${build_target}" == "install" ]] && return 0

		install_modulefile
                install_release_file

		[[ ${enable_cleanup_build} == yes ]] && pbuild::cleanup_build
		[[ ${enable_cleanup_src} == yes ]] && pbuild::cleanup_src
		return 0
	}
	remove_module() {
		if [[ -d "${PREFIX}" ]]; then
			std::info \
                                "%s " "${module_name}/${module_version}:" \
                                "removing all files in '${PREFIX}' ..."
			[[ "${dry_run}" == 'no' ]] && rm -rf ${PREFIX}
		fi

		# assemble name of modulefile
		local dst="${PMODULES_ROOT}/"
		dst+="${GROUP}/"
		dst+="${PMODULES_MODULEFILES_DIR}/"
		dst+="${fully_qualified_module_name}"

		# directory where to install modulefile
 		local -r dstdir=${dst%/*}

		if [[ -e "${dst}" ]]; then
			std::info \
                                "%s " "${module_name}/${module_version}:" \
                                "removing modulefile '${dst}' ..."
			[[ "${dry_run}" == 'no' ]] && rm -v "${dst}"
		fi
		local release_file="${dstdir}/.release-${module_version}"
		if [[ -e "${release_file}" ]]; then
			std::info \
                                "%s " "${module_name}/${module_version}:" \
                                "removing release file '${release_file}' ..."
			[[ "${dry_run}" == 'no' ]] && rm -v "${release_file}"
		fi
		rmdir -p --ignore-fail-on-non-empty "${dstdir}" 2>/dev/null
	}

	########################################################################
	#
	# here we really start with make_all()
	#

	# setup module specific environment
	if [[ "${bootstrap}" == 'no' ]]; then
		check_supported_systems
		load_build_dependencies
		set_full_module_name_and_prefix
		if [[ "${module_release}" == 'removed' ]]; then
			remove_module
		elif [[ ! -d "${PREFIX}" ]] || \
                             [[ "${force_rebuild}" == 'yes' ]]; then
			build_module
		else
 			std::info \
                                "%s " "${module_name}/${module_version}:" \
                                "already exists, not rebuilding ..."
			if [[ "${opt_update_modulefiles}" == "yes" ]]; then
				install_modulefile
			fi
                        install_release_file
		fi
	else
		build_module
	fi
	return 0
}

pbuild.init_env() {
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

        SOURCE_URLS=()
        SOURCE_SHA256_SUMS=()
        SOURCE_NAMES=()
        
        SOURCE_FILE=()
        CONFIGURE_ARGS=()
        SUPPORTED_SYSTEMS=()
        PATCH_FILES=()
        PATCH_STRIPS=()
        PATCH_STRIP_DEFAULT='1'
        MODULE_DOCFILES=()
        configure_with='undef'
}

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
	USE_FLAGS=''		# architectures (or empty)

	local tmp=''
	
	if [[ "$v" =~ "_" ]]; then
		tmp="${v#*_}"
		USE_FLAGS=":${tmp//_/:}:"
		v="${v%%_*}"
	fi
	V_PKG="${v%%-*}"	# version without the release number
	V_RELEASE="${v#*-}"	# release number 

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
}

pbuild.build_module() {
        module_name="$1"
        module_version="$2"
        module_release="$3"
        shift 3
        with_modules=( "$@" )

        # P and V can be used in the build-script, so we have to set them here
        P="${module_name}"
        V="${module_version}"
        
	std::info "%s" "${module_name}/${module_version}: Start building ..."
	eval $( "${MODULECMD}" bash purge )
	# :FIXME: this is a hack!!!
	# shouldn't this be set in the build-script?
	eval $( "${MODULECMD}" bash use Libraries )

        pbuild.init_env
	parse_version "${module_version}"

        SRC_DIR="${TEMP_DIR}/${module_name}-${module_version}/src"
        BUILD_DIR="${TEMP_DIR}/${module_name}-${module_version}/build"

        source "${BUILD_SCRIPT}"
        pbuild::make_all
        std::info "%s" "${module_name}/${module_version}: Done ..."
}

# Local Variables:
# mode: sh
# sh-basic-offset: 8
# tab-width: 8
# End:
