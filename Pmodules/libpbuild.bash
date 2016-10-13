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

# assemble default path
PATH='/usr/bin:/bin:/usr/sbin:/sbin'

if [[ "${OS}" == "Darwin" ]]; then
        # :FIXME: do we really need this?
	# if required we should do this in the build-block
        [[ -d "/opt/X11/bin" ]] && PATH+=':/opt/X11/bin' || \
		std::info "Xquarz is not installed in '/opt/X11'"
fi

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

# Source directory for module.
# This is "${PMODULES_TMPDIR}/src/$P-$V"
declare -x  MODULE_SRCDIR=''

# Build directory for module
# This is either "${PMODULES_TMPDIR}/build/$P-$V"
# or "${PMODULES_TMPDIR}/build/$P-$V"
declare -x  MODULE_BUILDDIR=''

##############################################################################
#
# Set release of module. Exit script, if given release name is invalid.
#
# Arguments:
#   $1: release name
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
pbuild::module_is_available() {
	[[ -n $("${MODULECMD}" bash avail "$1" 2>&1 1>/dev/null) ]]
}

#......................................................................
#
# Find tarball for given module.
# Sets global variable TARBALL if found or exit with error message.
#
# Arguments:
#   $1:	    name
#   $2:	    version
#   $3...:  download directories
#
# Used global variables:
#   BUILD_BLOCK_DIR [in]
#   TARBALL [out]
#
find_tarball() {
	local -r name="$1"
	local    version="$2"
	shift 2
	local -a dirs=( "${BUILD_BLOCK_DIR}" )
	dirs+=( "$@" )

	local release="${version##*-}"
	version=${version%-*}
	local ext
	for dir in "${dirs[@]}"; do
		for ext in tar tar.gz tgz tar.bz2 tar.xz; do
			local fname
			local -a fnames
			fnames+=( "${dir}/${name}-${OS}-${version}-${release}.${ext}" )
			fnames+=( "${dir}/${name}-${OS}-${version}.${ext}" )
			fnames+=( "${dir}/${name}-${version}-${release}.${ext}" )
			fnames+=( "${dir}/${name}-${version}.${ext}" )
			for fname in "${fnames[@]}"; do
				if [[ -r "${fname}" ]]; then
				    echo "${fname}"
				    return
				fi
			done
		done
	done
	std::error "${name}/${version}: source not found."
	exit 43
}

###############################################################################
#
# extract sources. For the time being only tar-files are supported.
#
pbuild::prep() {

	TARBALL=$( find_tarball "${P/_serial}" "${V}" "${PMODULES_DISTFILESDIR}" )

	# untar sources
	if [[ ! -d ${MODULE_SRCDIR} ]]; then
		mkdir -p "${PMODULES_TMPDIR}/src/$P-$V"
		(
			cd "${PMODULES_TMPDIR}/src/$P-$V"
			tar -xv --strip-components 1 -f "${TARBALL}"
		)
		(cd "${MODULE_SRCDIR}" && pbuild::patch_sources)
	fi

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

pbuild::build() {
	make -j${JOBS}
}

pbuild::install() {
	make install
}

pbuild::post_install() {
	:
}

pbuild::install_doc() {
	local -r docdir="${PREFIX}/${_DOCDIR}/$P"

	std::info "${P}/${V}: Installing documentation to ${docdir}"
	install -m 0755 -d "${docdir}"
	install -m0444 "${MODULE_DOCFILES[@]/#/${MODULE_SRCDIR}/}" "${BUILD_BLOCK}" "${docdir}"
}

pbuild::cleanup_build() {
	[[ "${MODULE_BUILDDIR}" == "${MODULE_SRCDIR}" ]] && return
	
	if [[ -z "${MODULE_BUILDDIR}" ]]; then
	        std::die 1 "Oops: internal error: %s is %s..." \
			 MODULE_BUILDDIR 'set to empty string'
	fi
	if [[ "${MODULE_BUILDDIR}" == "/" ]]; then
	        std::die 1 "Oops: internal error: %s is %s..." \
		     	 MODULE_BUILDDIR "set to '/'"
	fi
	if [[ ! -d "/${MODULE_BUILDDIR}" ]]; then
		std::die 1 "Oops: internal error: %s is %s..." \
			 MODULE_BUILDDIR=${MODULE_BUILDDIR} "not a directory"
	fi
	echo "Cleaning up '/${MODULE_BUILDDIR}'..."
	rm -rf  "/${MODULE_BUILDDIR}"
}

pbuild::cleanup_src() {
    (
	[[ -d /${MODULE_SRCDIR} ]] || return 0
	cd "/${MODULE_SRCDIR}/..";
	if [[ $(pwd) != / ]]; then
		echo "Cleaning up $(pwd)"
		rm -rf ${MODULE_SRCDIR##*/}
	fi
    );
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
	# load default versions
	#
	set_default_versions() {
		local -r fname="$1"
		[[ -r ${fname} ]] || return 0
		
		local varname=''
		while read _name _version; do
			[[ -z ${_name} ]] && continue
			[[ -z ${_version} ]] && continue
			[[ "${_name:0:1}" == '#' ]] && continue
			var_name=$(echo ${_name} | tr [:lower:] [:upper:])_VERSION
			# don't set version, if already set
			if [[ -z ${!var_name} ]]; then
				eval ${var_name}="${_version}"
			fi
		done < "${fname}"

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
		[[ -n $(module avail "$m" 2>&1) ]] || std::die 1 "$m: oops: build failed..."
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
		local -a eligible_variants_files=()
		eligible_variants_files+=( "${V}/variants" )
		eligible_variants_files+=( "${V}/variants.${OS}" )
		eligible_variants_files+=( "${V%.*}/variants" )
		eligible_variants_files+=( "${V%.*}/variants.${OS}" )
		eligible_variants_files+=( "${V%.*.*}/variants" )
		eligible_variants_files+=( "${V%.*.*}/variants.${OS}" )
		local found='no'
		local variants_file=''
		for variants_file in "${eligible_variants_files[@]}"; do
			    if [[ -e "${BUILD_BLOCK_DIR}/${variants_file}" ]]; then
				    found='yes'
				    variants_file="${BUILD_BLOCK_DIR}/${variants_file}"
				    break
			    fi
		done
		
		local m
		if [[ "${found}" == "yes" ]]; then
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
			if [[ $m =~ b:* ]]; then
				m=${m#*:}   # remove 'b:'
			elif [[ $m =~ r:* ]]; then
				m=${m#*:}   # remove 'r:'
				runtime_dependencies+=( "$m" )
			else
				runtime_dependencies+=( "$m" )
			fi
			is_loaded "$m" && continue
			if ! pbuild::module_is_available "$m"; then
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
		MODULE_SRCDIR="${PMODULES_TMPDIR}/src/$P-$V"
		if [[ "${CompileInSource}" == "yes" ]]; then
		        MODULE_BUILDDIR="${MODULE_SRCDIR}"
		else
			MODULE_BUILDDIR="${PMODULES_TMPDIR}/build/$P-$V"
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
			if pbuild::module_is_available "${P}/${V}"; then
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
			std::info "${P}/${V}: will be released as \"deprecated\""
		elif [[ "${depend_release}" == 'stable' ]] \
			 || [[ "${cur_module_release}" == 'stable' ]] \
			 || [[ "${ModuleRelease}" == 'stable' ]]; then
 			 # release is stable
			 #   - if all build-dependency are stable or
			 #   - the module already exists and is stable
			 #   - an unstable release of the module exists and the release is
			 #     changed to stable on the command line
			ModuleRelease='stable'
			std::info "${P}/${V}: will be released as \"stable\""
		else
			# release is unstable
			#   - if a build-dependency is unstable or 
			#   - if the module does not exists and no other release-type is
			#     given on the command line
			#   - and all the cases I didn't think of
			ModuleRelease='unstable'
			std::info "${P}/${V}: will be released as \"unstable\""
		fi

		# directory for README's, license files etc
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

		# set tar-ball and flags for tar
		TARBALL=$( find_tarball "${P/_serial}" "${V}" "${PMODULES_DISTFILESDIR}" )

		C_INCLUDE_PATH="${PREFIX}/include"
		CPLUS_INCLUDE_PATH="${PREFIX}/include"
		CPP_INCLUDE_PATH="${PREFIX}/include"
		LIBRARY_PATH="${PREFIX}/lib"
		LD_LIBRARY_PATH="${PREFIX}/lib"
		DYLD_LIBRARY_PATH="${PREFIX}/lib"

		PATH+=":${PREFIX}/bin"
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
	# Set sym-link to modulefile and write release file
	set_link() {
		local  link_name="${PMODULES_ROOT}/"
		link_name+="${ModuleGroup}/"
		link_name+="${PMODULES_MODULEFILES_DIR}/"
		link_name+="${ModuleName}"
		local -r dir_name=${link_name%/*}
		if [[ ! -e "${link_name}" ]]; then
			(
				std::info "${P}/${V}: setting new sym-link '${link_name}' ..."
				mkdir -p "${dir_name}"
				cd "${dir_name}"
				local x
				IFS='/' x=( ${dir_name/${PMODULES_ROOT}\/${ModuleGroup}\/} )
				local -i n=${#x[@]}
				local _target=$(eval printf "../%.s" {1..${n}})
				_target+="${PMODULES_TEMPLATES_DIR}/${P}/modulefile"
				ln -fs "${_target}" "${ModuleName##*/}"
			)
		fi
		std::info "${P}/${V}: setting release to '${ModuleRelease}' ..."
		local -r release_file="${dir_name}/.release-${ModuleName##*/}"
		echo "${ModuleRelease}" > "${release_file}"
	}

 	#......................................................................
	# Install modulefile to template directory
	install_modulefile() {
		local -r src="${BUILD_BLOCK_DIR}/modulefile"
		if [[ ! -r "${src}" ]]; then
			std::info "${P}/${V}: skipping modulefile installation ..."
			return
		fi
		local -r dst="${PMODULES_ROOT}/${ModuleGroup}/${PMODULES_TEMPLATES_DIR}/${P}"

		std::info "${P}/${V}: installing modulefile in '${dst}' ..."
		mkdir -p "${dst}"
		install -m 0444 "${src}" "${dst}"
	}
	
	##############################################################################
	#
	# here we really start with make_all()
	#
	local building='no'
	echo "${P}:"

	# setup module specific environment
	if [[ ${bootstrap} == no ]]; then
		load_build_dependencies
		check_and_setup_env
	else
		check_and_setup_env_bootstrap
	fi

	if [[ ! -d "${PREFIX}" ]] || \
	       [[ ${force_rebuild} == 'yes' ]] || \
	       [[ ${bootstrap} == 'yes' ]]; then
		building='yes'
 		echo "Building $P/$V ..."
		[[ ${dry_run} == yes ]] && std::die 0 ""
		check_compiler

		if [[ ! -e "${MODULE_BUILDDIR}/.prep" ]] || [[ ${force_rebuild} == 'yes' ]] ; then
			pbuild::prep
			touch "${MODULE_BUILDDIR}/.prep"
		fi
		[[ "${target}" == "prep" ]] && return 0

		if [[ ! -e "${MODULE_BUILDDIR}/.configure" ]] || \
		   [[ ${force_rebuild} == 'yes' ]]; then
		        cd "${MODULE_SRCDIR}"
			pbuild::pre_configure
			cd "${MODULE_BUILDDIR}"
			pbuild::configure
			touch "${MODULE_BUILDDIR}/.configure"
		fi
		[[ "${target}" == "configure" ]] && return 0

		if [[ ! -e "${MODULE_BUILDDIR}/.compile" ]]  || [[ ${force_rebuild} == 'yes' ]]; then
			cd "${MODULE_BUILDDIR}"
			pbuild::build
			touch "${MODULE_BUILDDIR}/.compile"
		fi
		[[ "${target}" == "compile" ]] && return 0

		if [[ ! -e "${MODULE_BUILDDIR}/.install" ]] || [[ ${force_rebuild} == 'yes' ]]; then
			cd "${MODULE_BUILDDIR}"
			pbuild::install
			pbuild::post_install
			if typeset -F pbuild::post_install_${OS} 1>/dev/null 2>&1; then
			        pbuild::post_install_${OS} "$@"
			fi
			pbuild::install_doc
			post_install
			if [[ ${bootstrap} == 'no' ]]; then
				write_runtime_dependencies
				write_build_dependencies
			fi
			touch "${MODULE_BUILDDIR}/.install"
		fi
		[[ "${target}" == "install" ]] && return 0
		
		[[ ${enable_cleanup_build} == yes ]] && pbuild::cleanup_build
		[[ ${enable_cleanup_src} == yes ]] && pbuild::cleanup_src
		
	else
 		std::info "${P}/${V}: already exists, not rebuilding ..."
	fi
	if [[ ${bootstrap} == 'no' ]]; then
		set_link
		install_modulefile
	fi
	return 0
}

# Local Variables:
# mode: sh
# sh-basic-offset: 8
# tab-width: 8
# End:
