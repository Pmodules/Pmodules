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

#..............................................................................
# global variables used in the library

declare -r  OS=$(uname -s)

# module name including path in hierarchy and version
# (ex: 'gcc/6.1.0/openmpi/1.10.2' for openmpi compiled with gcc 6.1.0)
declare -x  ModuleName=''

# group this module is in (ex: 'Programming')
declare -x  ModuleGroup=''

# release of module (ex: 'stable')
declare	-x  ModuleRelease=''

# relative path of documentation
# abs. path is "${PREFIX}/${_docdir}/$P"
declare -r  _DOCDIR='share/doc'

declare	SOURCE_URL=()
declare SOURCE_SHA256=()
declare	SOURCE_FILE=()
declare	CONFIGURE_ARGS=()

#..............................................................................
#
# The following variables are available in build-blocks and set read-only
# :FIXME: do we have to export them?
#

# install prefix of module.
# i.e:: ${PMODULES_ROOT}/${ModuleGroup)/${ModuleName}
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
pbuild::supported_os() {
	for os in "$@"; do
		[[ ${os} == ${OS} ]] && return 0
	done
	std::die 1 "${P}: Not available for ${OS}."
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
		std::die 42 "${FUNCNAME}: Missing group argument."
	fi
	ModuleGroup=$1
}

##############################################################################
#
# Set documentation file to be installed.
#
# Arguments:
#   $@: documentation files relative to source
#
pbuild::set_docfiles() {
	MODULE_DOCFILES=("$@")
}
pbuild::add_docfile() {
	MODULE_DOCFILES+=("$@")
}

##############################################################################
#
# Set supported compilers.
#
# Arguments:
#   $@: compilers
#
pbuild::set_supported_compilers() {
	MODULE_SUPPORTED_COMPILERS=("$@")
}


##############################################################################
#
# Test whether a module with the given name already exists.
#
# Arguments:
#   $1: module name
#
# Notes:
#   The passed module name should be NAME/VERSION
#   :FIXME: this does not really work in a hierarchical group without 
#           adding the dependencies...
#
pbuild::module_exists() {
	[[ -n $("${MODULECMD}" bash search -a --no-header "$1" 2>&1 1>/dev/null) ]]
}

##############################################################################
#
# Test whether a module with the given name is available.
#
# Arguments:
#   $1: module name
#
# Notes:
#   The passed module name must be NAME/VERSION! 
#
pbuild::module_is_avail() {
	local output=( $("${MODULECMD}" bash avail -a -m "$1" 2>&1 1>/dev/null) )
	[[ "${output[0]}" == "$1" ]]
}

pbuild::set_download_url() {
	SOURCE_URL+=( "$1" )
	SOURCE_SHA256+=( "$2" )
}

pbuild::use_cc() {
	# :FIXME: check whether this an executable
	[[ -x "$1" ]] || std::die 3 "Error in setting CC: '$1' is not an executable!"
	CC="$1"
}

#......................................................................
#
# Find/download tarball for given module.
# If the source URL is given, we look for the file-name specified in
# the URL. Otherwise we test for several possible names/extensions.
#
# The downloaded file will be stored with the name "$P-$V" and extension
# derived from URL. The download directory is the first directory passed.
#
# Arguments:
#   $1:	    store file name with upvar here
#   $2:	    download URL 
#   $3...:  download directories
#
# Returns:
#   0 on success otherwise a value > 0
#
download_source_file() {
	local "$1"
	local var="$1"
	local -r url="$2"
	shift 2
	dirs+=( "$@" )

	local -r fname="${url##*/}"
	local -r extension=$(echo ${fname} | sed 's/.*\(.tar.bz2\|.tbz2\|.tar.gz\|.tgz\|.tar.xz\|.zip\)/\1/')
	echo "fname=\"${fname}\""
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
				std::die 4 "Error in download URL: unknown download method '${method}'!"
				;;
                esac
	fi
	std::upvar "${var}" "${dir}/${fname}"
	[[ -r "${dir}/${fname}" ]]
}

pbuild::pre_prep() {
	:
}
eval "pbuild::pre_prep_${OS}() { :; }"

pbuild::post_prep() {
	:
}
eval "pbuild::post_prep_${OS}() { :; }"

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
		for (( i=0; i<${#PATCH_FILES[@]}; i++ )); do
			std::info "Appling patch '${PATCH_FILES[i]}' ..."
			local -i strip_val="${PATCH_STRIPS[i]:-${PATCH_STRIP_DEFAULT}}"
			patch -p${strip_val} < "${BUILDBLOCK_DIR}/${PATCH_FILES[i]}"
		done
	}

	[[ -z "${SOURCE_URL}" ]] && std::die 3 "Download source not set!"
	download_source_file \
	    SOURCE_FILE \
	    "${SOURCE_URL}" \
	    "${PMODULES_DISTFILESDIR}" \
	    "${BUILDBLOCK_DIR}" ||
	        std::die 4 "$P/$V: sources for not found."
	[[ -z "${SOURCE_FILE}" ]] && std::die 3 "Source file not set!"
	unpack "${SOURCE_FILE}" "${SRC_DIR}"
	patch_sources
	# create build directory
	mkdir -p "${BUILD_DIR}"
}

declare PATCH_FILES=()
declare PATCH_STRIPS=()
declare PATCH_STRIP_DEFAULT='1'

pbuild::add_patch() {
	[[ -z "$1" ]] && std::die 1 "pbuild::add_patch: missing argument!"
	PATCH_FILES+=( "$1" )
	PATCH_STRIPS+=( "$2" )
}
eval "pbuild::add_patch_${OS}() { pbuild::add_patch \"\$@\"; }"

pbuild::set_default_patch_strip() {
	[[ -n "$1" ]] || std::die 1 "Missing argument to '${FUNCNAME}'!"
	PATCH_STRIP_DEFAULT="$1"
}

###############################################################################
#
#
pbuild::pre_configure() {
	:
}
eval "pbuild::pre_configure_${OS}() { :; }"

pbuild::set_configure_args() {
	CONFIGURE_ARGS+=( "$@" )
}

pbuild::add_configure_args() {
	CONFIGURE_ARGS+=( "$@" )
}


pbuild::configure() {
	${SRC_DIR}/configure \
		--prefix="${PREFIX}" \
		"${CONFIGURE_ARGS[@]}" || std::die 3 "configure failed"
}

pbuild::post_configure() {
	:
}
eval "pbuild::post_configure_${OS}() { :; }"

pbuild::pre_compile() {
	:
}
eval "pbuild::pre_compile_${OS}() { :; }"

pbuild::compile() {
	make -j${JOBS}
}

pbuild::post_compile() {
	:
}
eval "pbuild::post_compile_${OS}() { :; }"

pbuild::pre_install() {
	:
}
eval "pbuild::pre_install_${OS}() { :; }"

pbuild::install() {
	make install
}

pbuild::post_install() {
	:
}
eval "pbuild::post_install_${OS}() { :; }"

pbuild::cleanup_build() {
	[[ "${BUILD_DIR}" == "${SRC_DIR}" ]] && return 0

	# the following two checks we should de earlier!	
	if [[ -z "${BUILD_DIR}" ]]; then
	        std::die 1 "Oops: internal error: %s is %s..." \
			 BUILD_DIR 'set to empty string'
	fi
	if [[ ! -d "/${BUILD_DIR}" ]]; then
		std::die 1 "Oops: internal error: %s is %s..." \
			 BUILD_DIR=${BUILD_DIR} "not a directory"
	fi

	{
		cd "/${BUILD_DIR}/.."
		if [[ "$(pwd)" == "/" ]]; then
		        std::die 1 "Oops: internal error: %s is %s..." \
			     	 BUILD_DIR "set to '/'"
		fi
		echo "Cleaning up '${BUILD_DIR}'..."
		rm -rf "${BUILD_DIR##*/}"
	};
	return 0
}

pbuild::cleanup_src() {
	[[ -d /${SRC_DIR} ]] || return 0
    	{
		cd "/${SRC_DIR}/..";
		if [[ $(pwd) == / ]]; then
		        std::die 1 "Oops: internal error: %s is %s..." \
			     	 SRC_DIR "set to '/'"
		fi
		echo "Cleaning up '${SRC_DIR}'..."
		rm -rf "${SRC_DIR##*/}"
   	};
	return 0
}

#
# The 'do it all' function.
#
pbuild::make_all() {
	local variant=''
	local depend_release=''
	local -a runtime_dependencies=()
	#
	# helper functions
	#

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
		local -r m=$1
		std::debug "${m}: module not available"
		local rels=( ${PMODULES_DEFINED_RELEASES//:/ } )
		[[ ${dry_run} == yes ]] && \
			std::die 1 "${m}: module does not exist, cannot continue with dry run..."

		echo "$m: module does not exist, trying to build it..."
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
		[[ -x "${buildscript}" ]] || std::die 1 "$m: build-block not found!"
		"${buildscript}" "${m#*/}" ${args[@]}
		pbuild::module_exists "$m" || std::die 1 "$m: oops: build failed..."
	}
	
	#......................................................................
	#
	# build dependencies can be defined
	# - on the command line via '--with=MODULE/VERSION'
	# - in a 'variants' file
	# - in the build block
	#
	# Arguments:
	#   none
	#
	# Variables
	#   ModuleRelease	    set if defined in a variants file
	#   runtime_dependencies    runtime dependencies from variants added
	#   depend_release	    set if a dependency is 'unstable' or 'deprecated'
	#
	load_build_dependencies() {
		local m
		if [[ -n "${variants_file}" ]]; then
		        # :FIXME:
			# handle conflicts in modules specified via command-line
			# argument and variants file
		        local pattern="/^$P\/$V[[:blank:]]/"
			for m in "${with_modules[@]}"; do 
				pattern+=" && /${m//\//\\/}/"
			done
			variant=$(awk "${pattern}" "${variants_file}" | tail -1)
			local variant_release=$(awk '{printf $2}' <<< "${variant}")
			if [[ -n "${variant_release}" ]]; then
				ModuleRelease="${variant_release}"
			fi
			with_modules+=( $(awk "{for (i=3; i<=NF; i++) printf \$i \" \"}" <<< "${variant}" ) )
		fi

		for m in "${with_modules[@]}"; do
			# :FIXME:
			# this check shouldn't be requiered here
			[[ -z $m ]] && continue

			# module name prefixes in dependency declarations:
			# 'b:' this is a build dependency
			# 'r:' this a run-time dependency, *not* required for building
			# without prefix: this is a build and run-time dependency
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
			# modules with and without a release number exist. Example:
			# mpc/1.1.0 and mpc/1.1.0-1. Since we get a sorted list 
			# from 'module avail' and the full version should be set
			# in the variants file, we look for the first exact match.
			local name=''
			name=$("${MODULECMD}" bash avail -a -m $m 2>&1 1>/dev/null | awk "/^${m/\//\\/}[[:blank:]]/ {print \$1}" )

			if [[ -z "${name}" ]]; then
			        build_dependency "$m"
			fi

			local release=( $("${MODULECMD}" bash avail -a -m $m 2>&1 1>/dev/null | awk "/^${m/\//\\/}[[:blank:]]/ {print \$2}" ))
			[[ -z "${release}" ]] && std::die 5 "Internal error..."

			if [[ ${release} == deprecated ]]; then
				# set module release to 'deprecated' if a build dependency
				# is deprecated
				depend_release='deprecated'
			elif [[ ${release} == unstable ]] && [[ -z ${depend_release} ]]; then
				# set module release to 'unstable' if a build dependency is
				# unstable and release not yet set
				depend_release='unstable'
			fi
			
			echo "Loading module: ${m}"
			module load "${m}"
		done
	}

	#......................................................................
	#
	# check and setup module specific environment.
	#
	# The following variables must already be set:
	#	ModuleGroup	    module group
	#	P		    module name
	#	V		    module version
	#	MODULEPATH	    module path
	#	PMODULES_DISTFILESDIR directory where all the tar-balls are stored
	#
	# The following variables might already be set
	#	${_P}_VERSION	    module version
	#	ModuleRelease	    module release, one of 'unstable', 'stable',
	#			    'deprecated'
	#
	# The following variables are set in this function
	#	SRC_DIR
	#	BUILD_DIR
	#	ModuleName
	#	ModuleRelease
	#	PREFIX
	#
	check_and_setup_env() {
		
		# build module name
		# :FIXME: this should be read from a configuration file
		if [[ -z ${ModuleGroup} ]]; then
			std::die 1 "${P}/${V}: group not set."
		fi
		local module_name=()
		case ${ModuleGroup} in
		Compiler )
			module_name+=( "${COMPILER}/${COMPILER_VERSION}" )
			module_name+=( "${P}/${V}" )
			;;
		MPI )
			module_name+=( "${COMPILER}/${COMPILER_VERSION}" )
			module_name+=( "${MPI}/${MPI_VERSION}" )
			module_name+=( "${P}/${V}" )
			;;
		HDF5 )
			module_name+=( "${COMPILER}/${COMPILER_VERSION}" )
			module_name+=( "${MPI}/${MPI_VERSION}" )
			module_name+=( "${HDF5}/${HDF5_VERSION}" )
			module_name+=( "${P}/${V}" )
			;;
		OPAL )
			module_name+=( "${COMPILER}/${COMPILER_VERSION}" )
			module_name+=( "${MPI}/${MPI_VERSION}" )
			module_name+=( "${OPAL}/${OPAL_VERSION}" )
			module_name+=( "${P}/${V}" )
			;;
		HDF5_serial )
			module_name+=( "${COMPILER}/${COMPILER_VERSION}" )
			module_name+=( "hdf5_serial/${HDF5_SERIAL_VERSION}" )
			module_name+=( "${P}/${V}" )
			;;
		* )
			module_name+=("${P}/${V}" )
			;;
		esac

		# set full module name
		ModuleName=$( IFS='/'; echo "${module_name[*]}" ; )
		# set PREFIX of module
		PREFIX="${PMODULES_ROOT}/${ModuleGroup}/"
		for ((i=${#module_name[@]}-1; i >= 0; i--)); do
			PREFIX+="${module_name[i]}"
		done

		# get module release if already available
		local cur_module_release=''
		local saved_modulepath=${MODULEPATH}
		rels=( ${PMODULES_DEFINED_RELEASES//:/ } )
		for rel in "${rels[@]}"; do
			eval $("${MODULECMD}" bash unuse ${rel})
		done
		for rel in "${rels[@]}"; do
			eval $("${MODULECMD}" bash use ${rel})
			if pbuild::module_exists "${P}/${V}"; then
				cur_module_release=${rel}
				std::info "${P}/${V}: already exists and released as \"${rel}\""
				break
			fi
		done
		MODULEPATH=${saved_modulepath}

		# set release of module
		if [[ "${depend_release}" == 'deprecated' ]] || \
		       # release is deprecated
		       #   - if a build-dependency is deprecated or 
		       #   - the module already exists and is deprecated or
		       #   - is forced to be deprecated by setting this on the command line
		       [[ "${cur_module_release}" == 'deprecated' ]] \
		       || [[ "${ModuleRelease}" == 'deprecated' ]]; then
			ModuleRelease='deprecated'
		elif [[ "${depend_release}" == 'stable' ]] \
			 || [[ "${cur_module_release}" == 'stable' ]] \
			 || [[ "${ModuleRelease}" == 'stable' ]]; then
 			 # release is stable
			 #   - if all build-dependency are stable or
			 #   - the module already exists and is stable
			 #   - an unstable release of the module exists and the release is
			 #     changed to stable on the command line
			ModuleRelease='stable'
		else
			# release is unstable
			#   - if a build-dependency is unstable or 
			#   - if the module does not exists and no other release-type is
			#     given on the command line
			#   - and all the cases I didn't think of
			ModuleRelease='unstable'
		fi
		std::info "${P}/${V}: will be released as \"${ModuleRelease}\""
	}

	#......................................................................
	# test whether the module can be compiled with loaded compiler
	check_compiler() {
		test -z ${MODULE_SUPPORTED_COMPILERS} && return 0
		for cc in ${MODULE_SUPPORTED_COMPILERS[@]}; do
			if [[ ${COMPILER}/${COMPILER_VERSION} =~ ${cc} ]]; then
				return 0
			fi
		done
		std::die 1 "${P}/${V}: cannot be build with ${COMPILER}/${COMPILER_VERSION}."
	}

	#......................................................................
	# non-redefinable post-install
	post_install() {
		install_doc() {
			local -r docdir="${PREFIX}/${_DOCDIR}/$P"

			std::info "${P}/${V}: Installing documentation to ${docdir}"
			install -m 0755 -d "${docdir}"
			install -m0444 "${MODULE_DOCFILES[@]/#/${SRC_DIR}/}" \
						"${BUILD_SCRIPT}" "${docdir}"
		}

		# unfortunatelly sometime we need an OS depended post-install
		post_install_linux() {
			std::info "${P}/${V}: running post-installation for ${OS} ..."
			cd "${PREFIX}"
			# solve multilib problem with LIBRARY_PATH on 64bit Linux
			[[ -d "lib" ]] && [[ ! -d "lib64" ]] && ln -s lib lib64
			return 0
		}

		[[ "${OS}" == "Linux" ]] && post_install_linux
		return 0
	}

	#......................................................................
	# write run time dependencies to file
	write_runtime_dependencies() {
		local -r fname="${PREFIX}/.dependencies"
		std::info "${P}/${V}: writing run-time dependencies to ${fname} ..."
		local dep
		echo -n "" > "${fname}"
		for dep in "${runtime_dependencies[@]}"; do
			[[ -z $dep ]] && continue
			if [[ ! $dep =~ .*/.* ]]; then
				# no version given: derive the version from the currently
				# loaded modules
				dep=$( "${MODULECMD}" bash list -t 2>&1 1>/dev/null | grep "${dep}/" )
			fi
			echo "${dep}" >> "${fname}"
		done
	}

	#......................................................................
	# Write all loaded modules as build dependencies to file.
	write_build_dependencies() {
		local -r fname="${PREFIX}/.build_dependencies"
		std::info "${P}/${V}: writing build dependencies to ${fname} ..."
		"${MODULECMD}" bash list -t 2>&1 1>/dev/null | grep -v "Currently Loaded" > "${fname}" || :
	}
	
 	#......................................................................
	# Install modulefile
	install_modulefile() {
		local -r src="${BUILDBLOCK_DIR}/modulefile"
		if [[ ! -r "${src}" ]]; then
			std::info "${P}/${V}: skipping modulefile installation ..."
			return
		fi
		# assemble name of modulefile
		local dst="${PMODULES_ROOT}/"
		dst+="${ModuleGroup}/"
		dst+="${PMODULES_MODULEFILES_DIR}/"
		dst+="${ModuleName}"  # = group hierarchy + name/version

		# directory where to install modulefile
 		local -r dstdir=${dst%/*}

		std::info "${P}/${V}: installing modulefile in '${dstdir}' ..."
		mkdir -p "${dstdir}"
		install -m 0444 "${src}" "${dst}"
	}

 	#......................................................................
	# Install release-file
	set_module_release() {
		# directory where to install module- and release-file
		local target_dir="${PMODULES_ROOT}/"
		target_dir+="${ModuleGroup}/"
		target_dir+="${PMODULES_MODULEFILES_DIR}/"
		target_dir+="${ModuleName%/*}"  # = group hierarchy + name

		mkdir -p "${target_dir}"
		std::info "${P}/${V}: setting release to '${ModuleRelease}' ..."
		echo "${ModuleRelease}" > "${target_dir}/.release-$V"
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
			cd "${dir}" && "pbuild::pre_${target}_${OS}"
			cd "${dir}" && "pbuild::pre_${target}"
			cd "${dir}" && "pbuild::${target}"
			cd "${dir}" && "pbuild::post_${target}_${OS}"
			cd "${dir}" && "pbuild::post_${target}"
			touch "${BUILD_DIR}/.${target}"
		fi
	}

	#......................................................................
	# build module $P/$V
	build_module() {
 		echo "Building $P/$V ..."
		[[ ${dry_run} == yes ]] && std::die 0 ""
		check_compiler
		mkdir -p "${SRC_DIR}"

		build_target "${SRC_DIR}" prep
		[[ "${build_target}" == "prep" ]] && return 0

		build_target "${BUILD_DIR}" configure
		[[ "${build_target}" == "configure" ]] && return 0

		build_target "${BUILD_DIR}" compile
		[[ "${build_target}" == "compile" ]] && return 0

		build_target "${BUILD_DIR}" install
		[[ "${build_target}" == "install" ]] && return 0

		[[ ${enable_cleanup_build} == yes ]] && pbuild::cleanup_build
		[[ ${enable_cleanup_src} == yes ]] && pbuild::cleanup_src
		return 0
	}
	
	##############################################################################
	#
	# here we really start with make_all()
	#

	# setup module specific environment
	if [[ "${bootstrap}" == 'no' ]]; then
		load_build_dependencies
		check_and_setup_env
		if [[ ! -d "${PREFIX}" ]] || \
		       [[ "${force_rebuild}" == 'yes' ]]; then
			build_module
			install_modulefile
		else
 			std::info "${P}/${V}: already exists, not rebuilding ..."
			if [[ "${opt_install_modulefile}" == "yes" ]]; then
				install_modulefile
			fi
		fi
		set_module_release
	else
		#check_and_setup_env_bootstrap
		build_module
	fi

	return 0
}

# Local Variables:
# mode: sh
# sh-basic-offset: 8
# tab-width: 8
# End:
