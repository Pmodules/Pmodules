#!/bin/bash

###############################################################################
#
# initialize lib
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

# set default for the defined releases
if [[ -z ${PMODULES_DEFINED_RELEASES} ]]; then
	declare -r PMODULES_DEFINED_RELEASES=":unstable:stable:deprecated:"
fi

# flag: build in source or separate build directory
declare	    CompileInSource='no'

#..............................................................................
#
# The following variables are available in build-blocks and set read-only
# :FIXME: do we have to export them?
#

# install prefix of module.
# i.e:: ${PMODULES_ROOT}/${ModuleGroup)/${ModuleName}
declare -x  PREFIX=''

# Source directory for module. Will be set to "${PMODULES_TMPDIR}/src/$P-$V"
declare -x  MODULE_SRCDIR=''

# Build directory for module. Will be set to "${PMODULES_TMPDIR}/build/$P-$V"
declare -x  MODULE_BUILDDIR=''

##############################################################################
#
# Set release of module. Exit script, if given release name is invalid.
#
# Arguments:
#   $1: release name
#
# :FIXME:
#   This function is obsolete and should not be used any more!
#   Releases have to be defined in 'variants' configuration file.
#
pbuild::set_release() {
	#.....................................................................
	#
	# test whether the given argument is a valid release name
	#
	is_release() {
		[[ :${PMODULES_DEFINED_RELEASES}: =~ :$1: ]] && return 0
		std::die 1 "${P}: '$1' is not a valid release name."
	}

	is_release "$1" || std::die 1 "${P}: specified release '$1' is not valid!"
	ModuleRelease="$1"
}

##############################################################################
#
# Set flag to build module in source tree.
#
# Arguments:
#   none
#
pbuild::compile_in_sourcetree() {
	CompileInSource='yes'
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
#   $@: module name
#
# Notes:
#   The passed module name should be NAME/VERSION
#
pbuild::module_exists() {
	[[ -n $("${MODULECMD}" bash search -a --no-header "$1" 2>&1 1>/dev/null) ]]
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
pbuild::get_source() {
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
			file )
				cp "${url/file:}" "${dir}/${fname}"
				;;
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
                esac
	fi
	std::upvar "${var}" "${dir}/${fname}"
	[[ -r "${dir}/${fname}" ]]
}

#
# Search for variants file to use
#
# Arguments:
#   none
#
# Used global variables:
#   OS
#   BUILD_BLOCK_DIR
#   variants_file [out]
#
search_variants_file() {
	local -a eligible_variants_files=()
	eligible_variants_files+=( "${V}/variants.${OS}" )
	eligible_variants_files+=( "${V}/variants" )
	eligible_variants_files+=( "${V%.*}/variants.${OS}" )
	eligible_variants_files+=( "${V%.*}/variants" )
	eligible_variants_files+=( "${V%.*.*}/variants.${OS}" )
	eligible_variants_files+=( "${V%.*.*}/variants" )

	for variants_file in "${eligible_variants_files[@]}"; do
		if [[ -e "${BUILD_BLOCK_DIR}/${variants_file}" ]]; then
			variants_file="${BUILD_BLOCK_DIR}/${variants_file}"
		    	return 0
	    	fi
	done
	variants_file=''
	return 1
}


pbuild::pre_prep() {
	:
}

pbuild::post_prep() {
	:
}

#
# unpack file in given directory
#
pbuild::unpack() {
	local -r file="$1"
	local -r dir="$2"
	(
		mkdir -p "${dir}"
		cd "${dir}"
		local -r file_extension="${file##*.}"
		case "${file_extension}" in
			"zip" )
				std::die 42 "Zip files are not supported"
				;;
			* )
				# let's hope that tar supports 
				tar -xv --strip-components 1 -f "${file}" || \
					std::die 42 "${file}: Cannot untar file, maybe file format is not supported!"
				;;
		esac
	)
}

###############################################################################
#
# extract sources. For the time being only tar-files are supported.
#
pbuild::prep() {
	local source_file=''
	pbuild::get_source \
	    source_file \
	    "${SOURCE_URL}" \
	    "${PMODULES_DISTFILESDIR}" \
	    "${BUILD_BLOCK_DIR}" ||
	        std::die 4 "$P/$V: sources for not found."
	pbuild::unpack "${source_file}" "${MODULE_SRCDIR}"
	pbuild::patch_sources
	# create build directory
	mkdir -p "${MODULE_BUILDDIR}"
}

###############################################################################
#
# create an OS specific stub. If OS is 'Darwin' this creates a function named
# 'pbuild::patch_sources_Darwin()'
#
eval "pbuild::patch_sources_${OS}() { :; }"

pbuild::patch_sources() {
	pbuild::patch_sources_${OS}
}

pbuild::pre_configure() {
	:
}

pbuild::configure() {
	${MODULE_SRCDIR}/configure \
		--prefix="${PREFIX}"
}

pbuild::post_configure() {
	:
}

pbuild::pre_build() {
	:
}

pbuild::build() {
	make -j${JOBS}
}

pbuild::post_build() {
	:
}

pbuild::pre_install() {
	:
}

pbuild::install() {
	make install
}

pbuild::post_install() {
	:
}

eval "pbuild::post_install_${OS}() { :; }"

pbuild::install_doc() {
	local -r docdir="${PREFIX}/${_DOCDIR}/$P"

	std::info "${P}/${V}: Installing documentation to ${docdir}"
	install -m 0755 -d "${docdir}"
	install -m0444 "${MODULE_DOCFILES[@]/#/${MODULE_SRCDIR}/}" "${BUILD_BLOCK}" "${docdir}"
}

pbuild::cleanup_build() {
	[[ "${MODULE_BUILDDIR}" == "${MODULE_SRCDIR}" ]] && return 0

	# the following two checks we should de earlier!	
	if [[ -z "${MODULE_BUILDDIR}" ]]; then
	        std::die 1 "Oops: internal error: %s is %s..." \
			 MODULE_BUILDDIR 'set to empty string'
	fi
	if [[ ! -d "/${MODULE_BUILDDIR}" ]]; then
		std::die 1 "Oops: internal error: %s is %s..." \
			 MODULE_BUILDDIR=${MODULE_BUILDDIR} "not a directory"
	fi

	{
		cd "/${MODULE_BUILDDIR}/.."
		if [[ "$(pwd)" == "/" ]]; then
		        std::die 1 "Oops: internal error: %s is %s..." \
			     	 MODULE_BUILDDIR "set to '/'"
		fi
		echo "Cleaning up '${MODULE_BUILDDIR}'..."
		rm -rf "${MODULE_BUILDDIR##*/}"
	};
	return 0
}

pbuild::cleanup_src() {
	[[ -d /${MODULE_SRCDIR} ]] || return 0
    	{
		cd "/${MODULE_SRCDIR}/..";
		if [[ $(pwd) == / ]]; then
		        std::die 1 "Oops: internal error: %s is %s..." \
			     	 MODULE_SRCDIR "set to '/'"
		fi
		echo "Cleaning up '${MODULE_SRCDIR}'..."
		rm -rf "${MODULE_SRCDIR##*/}"
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

		local buildscript=$( std::get_abspath "${BUILD_BLOCK_DIR}"/../../*/${m/\/*}/build )
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
			if ! pbuild::module_exists "$m"; then
			        build_dependency "$m"
			fi

			local mod_name=''
			local mod_release=''
			read mod_name mod_release < <("${MODULECMD}" bash avail -a -m $m 2>&1 1>/dev/null | tail -1)

			if [[ ${mod_release} == deprecated ]]; then
				# set module release to 'deprecated' if a build dependency
				# is deprecated
				depend_release='deprecated'
			elif [[ ${mod_release} == unstable ]] && [[ -z ${depend_release} ]]; then
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
	#	MODULE_SRCDIR
	#	MODULE_BUILDDIR
	#	ModuleName
	#	ModuleRelease
	#	PREFIX
	#
	check_and_setup_env() {
		local FullModuleName=''
		
		if [[ -z ${ModuleGroup} ]]; then
			std::die 1 "${P}/${V}: group not set."
		fi
		MODULE_SRCDIR="${PMODULES_TMPDIR}/$P-$V/src"
		if [[ "${CompileInSource}" == "yes" ]]; then
		        MODULE_BUILDDIR="${MODULE_SRCDIR}"
		else
			MODULE_BUILDDIR="${PMODULES_TMPDIR}/$P-$V/build"
		fi

		# build module name
		# :FIXME: the MODULE_PREFIX should be derived from ModuleName
		# :FIXME: this should be read from a configuration file
		case ${ModuleGroup} in
		Tools )
			FullModuleName="${P}/${V}"
			ModuleName="${P}/${V}"
			;;
		Programming )
			FullModuleName="${P}/${V}"
			ModuleName="${P}/${V}"
			;;
		Libraries )
			FullModuleName="${P}/${V}"
			ModuleName="${P}/${V}"
			;;
		System )
			FullModuleName="${P}/${V}"
			ModuleName="${P}/${V}"
			;;
		Compiler )
			FullModuleName="${P}/${V}"
			FullModuleName+="/${COMPILER}/${COMPILER_VERSION}"
			
			ModuleName="${COMPILER}/${COMPILER_VERSION}/"
			ModuleName+="${P}/${V}"
			;;
		MPI )
			FullModuleName="${P}/${V}/"
			FullModuleName+="${MPI}/${MPI_VERSION}/"
			FullModuleName+="${COMPILER}/${COMPILER_VERSION}"
			
			ModuleName="${COMPILER}/${COMPILER_VERSION}/"
			ModuleName+="${MPI}/${MPI_VERSION}/"
			ModuleName+="${P}/${V}"
			;;
		HDF5 )
			FullModuleName="${P}/${V}"
			FullModuleName+="/${HDF5}/${HDF5_VERSION}"
			FullModuleName+="/${MPI}/${MPI_VERSION}"
			FullModuleName+="/${COMPILER}/${COMPILER_VERSION}"
			
			ModuleName="${COMPILER}/${COMPILER_VERSION}/"
			ModuleName+="${MPI}/${MPI_VERSION}/"
			ModuleName+="${HDF5}/${HDF5_VERSION}/"
			ModuleName+="${P}/${V}"
			;;
		OPAL )
			FullModuleName="${P}/${V}"
			FullModuleName+="/${OPAL}/${OPAL_VERSION}"
			FullModuleName+="/${MPI}/${MPI_VERSION}"
			FullModuleName+="/${COMPILER}/${COMPILER_VERSION}"
			
			ModuleName="${COMPILER}/${COMPILER_VERSION}/"
			ModuleName+="${MPI}/${MPI_VERSION}/"
			ModuleName+="${OPAL}/${OPAL_VERSION}/"
			ModuleName+="${P}/${V}"
			;;
		HDF5_serial )
			FullModuleName="${P}/${V}"
			FullModuleName+="/hdf5_serial/${HDF5_SERIAL_VERSION}"
			FullModuleName+="/${COMPILER}/${COMPILER_VERSION}"
			
			ModuleName="${COMPILER}/${COMPILER_VERSION}/"
			ModuleName+="hdf5_serial/${HDF5_SERIAL_VERSION}/"
			ModuleName+="${P}/${V}"
			;;
		* )
			FullModuleName="${P}/${V}"
			ModuleName="${P}/${V}"
			#std::die 1 "${P}/${V}: oops: unknown group: ${ModuleGroup}"
			;;
		esac

		# set PREFIX of module
		PREFIX="${PMODULES_ROOT}/${ModuleGroup}/${FullModuleName}"

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
	# setup environment for bootstrapping
	#
	check_and_setup_env_bootstrap() {
		if [[ -z ${ModuleGroup} ]]; then
			std::die 1 "${P}/${V}: group not set."
		fi

		MODULE_SRCDIR="${PMODULES_TMPDIR}/src/$P-$V"
		MODULE_BUILDDIR="${PMODULES_TMPDIR}/build/$P-$V"
		ModuleGroup='Tools'
		ModuleName="Pmodules/${PMODULES_VERSION}"
		# set PREFIX of module
		PREFIX="${PMODULES_ROOT}/${ModuleGroup}/${ModuleName}"
		
		ModuleRelease='unstable'
		std::info "${P}/${V}: will be released as \"${ModuleRelease}\""

		C_INCLUDE_PATH="${PREFIX}/include"
		CPLUS_INCLUDE_PATH="${PREFIX}/include"
		CPP_INCLUDE_PATH="${PREFIX}/include"
		LIBRARY_PATH="${PREFIX}/lib"
		LD_LIBRARY_PATH="${PREFIX}/lib"
		DYLD_LIBRARY_PATH="${PREFIX}/lib"

		PATH+=":${PREFIX}/bin"
		PATH+=":${PREFIX}/sbin"
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
		# unfortunatelly sometime we need an OS depended post-install
		post_install_linux() {
			cd "${PREFIX}"
			# solve multilib problem with LIBRARY_PATH on 64bit Linux
			[[ -d "lib" ]] && [[ ! -d "lib64" ]] && ln -s lib lib64
			return 0
		}

		std::info "${P}/${V}: running post-installation for ${OS} ..."
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
		local -r src="${BUILD_BLOCK_DIR}/modulefile"
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

	#......................................................................
	# build module $P/$V
	build_module() {
 		echo "Building $P/$V ..."
		[[ ${dry_run} == yes ]] && std::die 0 ""
		check_compiler

		if [[ ! -e "${MODULE_BUILDDIR}/.prep" ]] || \
		   [[ ${force_rebuild} == 'yes' ]] || \
		   [[ -z ${target} ]] || \
		   [[ "${target}" == "prep" ]]; then
			mkdir -p "${MODULE_SRCDIR}"
			cd "${MODULE_SRCDIR}"
			( pbuild::pre_prep )
			( pbuild::prep )
			( pbuild::post_prep )
			touch "${MODULE_BUILDDIR}/.prep"
		fi
		[[ "${target}" == "prep" ]] && return 0

		if [[ ! -e "${MODULE_BUILDDIR}/.configure" ]] || \
		   [[ ${force_rebuild} == 'yes' ]] || \
		   [[ -z ${target} ]] || \
		   [[ "${target}" == "configure" ]]; then
		        cd "${MODULE_BUILDDIR}"
			( pbuild::pre_configure )
			( pbuild::configure )
			( pbuild::post_configure )
			touch "${MODULE_BUILDDIR}/.configure"
		fi
		[[ "${target}" == "configure" ]] && return 0

		if [[ ! -e "${MODULE_BUILDDIR}/.compile" ]] || \
		   [[ ${force_rebuild} == 'yes' ]] || \
		   [[ -z ${target} ]] || \
		   [[ "${target}" == "compile" ]]; then
			cd "${MODULE_BUILDDIR}"
			( pbuild::pre_build )
			( pbuild::build )
			( pbuild::post_build )
			touch "${MODULE_BUILDDIR}/.compile"
		fi
		[[ "${target}" == "compile" ]] && return 0

		if [[ ! -e "${MODULE_BUILDDIR}/.install" ]] || \
		   [[ ${force_rebuild} == 'yes' ]] || \
		   [[ -z ${target} ]] || \
		   [[ "${target}" == "install" ]]; then
			cd "${MODULE_BUILDDIR}"
			( pbuild::pre_install )
			( pbuild::install )
			( pbuild::post_install_${OS} "$@" )
			( pbuild::post_install )
			( pbuild::install_doc )
			if [[ ${bootstrap} == 'no' ]]; then
				write_runtime_dependencies
				write_build_dependencies
			fi
			touch "${MODULE_BUILDDIR}/.install"
		fi
		[[ "${target}" == "install" ]] && return 0

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
		       [[ "${force_rebuild}" == 'yes' ]] || \
		       [[ -n "${target}" ]]; then
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
		check_and_setup_env_bootstrap
		build_module
	fi

	return 0
}

# Local Variables:
# mode: sh
# sh-basic-offset: 8
# tab-width: 8
# End:
