#!/bin/bash


# number of parallel make jobs
declare -i  JOBS=3


declare -x  PREFIX=''
declare -x  DOCDIR=''
declare -x  MODULE_GROUP=''
declare	-x  MODULE_RELEASE=''
declare     cur_module_release=''

declare     DEPEND_RELEASE=''
declare -x  MODULE_NAME=''

# these directories are module dependend
declare -x  MODULE_SRCDIR=''
declare -x  MODULE_BUILDDIR=''

declare -x  MODULE_BUILD_DEPENDENCIES
declare -x  MODULE_DEPENDENCIES

declare -x  C_INCLUDE_PATH
declare -x  CPLUS_INCLUDE_PATH
declare -x  CPP_INCLUDE_PATH
declare -x  LIBRARY_PATH
declare -x  LD_LIBRARY_PATH
declare -x  DYLD_LIBRARY_PATH

##############################################################################
#
# test whether a the string passed in $1 is a valid release name
#
# $1: string to be tested
#
is_release () {
	[[ ${releases} =~ :$1: ]]
}

##############################################################################
#
# set supported OS
#
# $1: OS (as printed by 'uname -s')
#
pbuild::supported_os() {
	for os in "$@"; do
		[[ ${os} == ${OS} ]] && return 0
	done
	std::die 0 "${P}: Not available for ${OS}."
}

##############################################################################
#
# install module in given group
#
# $1: group
#
pbuild::add_to_group() {
	if [[ -z ${1} ]]; then
		std::die 42 "${FUNCNAME}: Missing group argument."
	fi
	if [[ ! -d ${PMODULES_ROOT}/${PMODULES_TEMPLATES_DIR}/${1} ]]; then
		std::die 43 "${1}: group does not exist."
	fi
	MODULE_GROUP=$1
}

##############################################################################
#
# set build-/runtime dependencies
#
# $@: dependencies
#
pbuild::set_build_dependencies() {
	MODULE_BUILD_DEPENDENCIES=("$@")
}

pbuild::set_runtime_dependencies() {
	MODULE_DEPENDENCIES=("$@")
}

##############################################################################
#
# set documentation file to be installed
#
# $@: documentation files relative to source
#
pbuild::set_docfiles() {
	MODULE_DOCFILES=("$@")
}

##############################################################################
#
# set supported compilers
#
# $@: compilers
#
pbuild::set_supported_compilers() {
	MODULE_SUPPORTED_COMPILERS=("$@")
}

##############################################################################
#
# test availablity of a module
#
# $@: module
#
pbuild::module_is_available() {
	[[ -n $("${MODULECMD}" bash avail "$1" 2>&1 1>/dev/null) ]]
}


##############################################################################
# 
# cleanup environment
#
pbuild::cleanup_env() {

	C_INCLUDE_PATH=''
	CPLUS_INCLUDE_PATH=''
	CPP_INCLUDE_PATH=''
	LIBRARY_PATH=''
	LD_LIBRARY_PATH=''
	DYLD_LIBRARY_PATH=''

	CFLAGS=''
	CPPFLAGS=''
	CXXFLAGS=''
	LIBS=''
	LDFLAGS=''
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
	std::info "Installing documentation to ${DOCDIR}"
	install -m 0755 -d "${DOCDIR}"
	install -m0444 "${MODULE_DOCFILES[@]/#/${MODULE_SRCDIR}/}" "${BUILD_BLOCK}" "${DOCDIR}"
}

pbuild::cleanup_build() {
	[[ -n "${MODULE_BUILDDIR}" ]]     \
		|| std::die 1 "Oops: internal error: MODULE_BUILDDIR is set to empty string..."
	[[ "${MODULE_BUILDDIR}" == "/" ]] \
		&& std::die 1 "Oops: internal error: MODULE_BUILDDIR is set to '/'..."
	[[ -d "/${MODULE_BUILDDIR}" ]]    \
		|| std::die 1 "Oops: internal error: MODULE_BUILDDIR=${MODULE_BUILDDIR} is not a directory..."
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
	#
	# helper functions
	#

	##############################################################################
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

	##############################################################################
	#
	# test whether a module is loaded or not
	#
	# $1: module name
	#
	is_loaded() {
		[[ :${LOADEDMODULES}: =~ :$1: ]]
	}

	##############################################################################
	#
	load_build_dependencies() {
		for m in "${MODULE_BUILD_DEPENDENCIES[@]}"; do
			[[ -z $m ]] && continue
			if [[ ! $m =~ "*/*" ]]; then
				local _V=$(echo -n $m | tr [:lower:] [:upper:] )_VERSION
				if [[ -n ${!_V} ]]; then
		    			m=$m/${!_V}
				else
					echo "$m: warning: No version set, loading default ..."
				fi
			fi
			is_loaded "$m" && continue
			if ! pbuild::module_is_available "$m"; then
				std::debug "${m}: module not available"
				local rels=( ${releases//:/ } )
				for rel in "${rels[@]}"; do
					std::debug "${m}: check release \"${rel}\""
					eval $("${MODULECMD}" bash use ${rel})
					if pbuild::module_is_available "${m}"; then
						std::die 1 "${m}: module available with release \"${rel}\", add this release with \"module use ${rel}\" and re-run build script."
					fi
				done
				[[ ${dry_run} == yes ]] && {
					std::die 1 "${m}: module does not exist, cannot continue with dry run..."
				}

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
					--release=* )
						args+=( $1 )
						;;
					--with=*/* )
						args+=( $1 )
						;;
					*=* )
						args+=( $1 )
						;;
					esac
					shift
				done
				"${BUILD_SCRIPTSDIR}"/*/"${m/\/*}/build" ${args[@]}
				if [[ -z $(module avail "$m" 2>&1) ]]; then
					std::die 1 "$m: oops: build failed..."
				fi
			fi
			# :FIXME: this doesn't work any more!
			local modulepath_root="${PMODULES_ROOT}/${PMODULES_MODULEFILES_DIR}"
			local tmp=$( module display "${m}" 2>&1 | grep -m1 -- "${modulepath_root}" )
			tmp=${tmp/${modulepath_root}\/}
			tmp=${tmp%%/*}
			local _family=( ${tmp//./ } )
			if [[ ${_family[1]} == deprecated ]]; then
				# set module release to 'deprecated' if a build dependency
				# is deprecated
				DEPEND_RELEASE='deprecated'
			elif [[ ${_family[1]} == unstable ]] && [[ -z ${DEPEND_RELEASE} ]]; then
				# set module release to 'unstable' if a build dependency is
				# unstable and release not yet set
				DEPEND_RELEASE='unstable'
			fi

			
			echo "Loading module: ${m}"
			module load "${m}"
		done
	}

	
	##############################################################################
	#
	# find tarball 
	# $1: download directory
	# $2: name without version
	# $3: version
	#
	find_tarball() {
		local -r dir=$1
		local -r name=$2
		local -r version=$3

		TARBALL=""
		local ext
		for ext in tar tar.gz tgz tar.bz2 tar.xz; do
			local fname="${dir}/${name}-${OS}-${version}.${ext}"
			if [[ -r "${fname}" ]]; then
				TARBALL="${fname}"
				break
			fi
			local fname="${dir}/${name}-${version}.${ext}"
			if [[ -r "${fname}" ]]; then
				TARBALL="${fname}"
				break
			fi
		done
		if [[ -z ${TARBALL} ]]; then
			std::error "tar-ball for $P/$V not found."
			exit 43
		fi
	}

	##############################################################################
	#
	# check and setup module specific environment.
	#
	# The following variables must already be set:
	#	MODULE_GROUP	    module group
	#	P		    module name
	#	_P		    module name in upper case
	#	MODULEPATH	    module path
	#	BUILD_DOWNLOADSDIR  directory where all the tar-balls are stored
	#
	# The following variables might already be set
	#	V		    module version, if not set ${_P}_VERSION must
	#			    evaluate to a version
	#	${_P}_VERSION	    module version
	#	MODULE_RELEASE	    module release, one of 'unstable', 'stable',
	#			    'deprecated'
	#
	# The following variables are set in this function
	#	MODULE_SRCDIR
	#	MODULE_BUILDDIR
	#	MODULE_RPREFIX
	#	MODULE_NAME
	#	MODULE_RELEASE
	#	PREFIX
	#	DOCDIR
	#
	check_and_setup_env() {
		if [[ -z ${MODULE_GROUP} ]]; then
			std::die 1 "$P: group not set."
		fi

		# this allows us to specify the version as PKGNAME_VERSION=1.2.3 on
		# the cmd-line
		if [[ -z $V ]]; then
			V=$(eval echo \$${_P}_VERSION)
		fi

		# oops, we need a version
		if [[ -z $V ]]; then
			std::die 1 "$P: Missing version."
		fi
		MODULE_SRCDIR="${BUILD_TMPDIR}/src/${P/_serial}-$V"
		MODULE_BUILDDIR="${BUILD_TMPDIR}/build/$P-$V"

		# build module name
		# :FIXME: the MODULE_PREFIX should be derived from MODULE_NAME
		# :FIXME: this should be read from a configuration file
		case ${MODULE_GROUP} in
		Tools )
			MODULE_RPREFIX="${P}/${V}"
			MODULE_NAME="${P}/${V}"
			;;
		Programming )
			MODULE_RPREFIX="${P}/${V}"
			MODULE_NAME="${P}/${V}"
			;;
		Libraries )
			MODULE_RPREFIX="${P}/${V}"
			MODULE_NAME="${P}/${V}"
			;;
		System )
			MODULE_RPREFIX="${P}/${V}"
			MODULE_NAME="${P}/${V}"
			;;
		Compiler )
			MODULE_RPREFIX="${P}/${V}"
			MODULE_RPREFIX+="/${COMPILER}/${COMPILER_VERSION}"
			
			MODULE_NAME="${COMPILER}/${COMPILER_VERSION}/"
			MODULE_NAME+="${P}/${V}"
			;;
		MPI )
			MODULE_RPREFIX="${P}/${V}/"
			MODULE_RPREFIX+="${MPI}/${MPI_VERSION}/"
			MODULE_RPREFIX+="${COMPILER}/${COMPILER_VERSION}"
			
			MODULE_NAME="${COMPILER}/${COMPILER_VERSION}/"
			MODULE_NAME+="${MPI}/${MPI_VERSION}/"
			MODULE_NAME+="${P}/${V}"
			;;
		HDF5 )
			MODULE_RPREFIX="${P}/${V}"
			MODULE_RPREFIX+="/${HDF5}/${HDF5_VERSION}"
			MODULE_RPREFIX+="/${MPI}/${MPI_VERSION}"
			MODULE_RPREFIX+="/${COMPILER}/${COMPILER_VERSION}"
			
			MODULE_NAME="${COMPILER}/${COMPILER_VERSION}/"
			MODULE_NAME+="${MPI}/${MPI_VERSION}/"
			MODULE_NAME+="${HDF5}/${HDF5_VERSION}/"
			MODULE_NAME+="${P}/${V}"
			;;
		OPAL )
			MODULE_RPREFIX="${P}/${V}"
			MODULE_RPREFIX+="/${OPAL}/${OPAL_VERSION}"
			MODULE_RPREFIX+="/${MPI}/${MPI_VERSION}"
			MODULE_RPREFIX+="/${COMPILER}/${COMPILER_VERSION}"
			
			MODULE_NAME="${COMPILER}/${COMPILER_VERSION}/"
			MODULE_NAME+="${MPI}/${MPI_VERSION}/"
			MODULE_NAME+="${OPAL}/${OPAL_VERSION}/"
			MODULE_NAME+="${P}/${V}"
			;;
		HDF5_serial )
			MODULE_RPREFIX="${P}/${V}"
			MODULE_RPREFIX+="/hdf5_serial/${HDF5_SERIAL_VERSION}"
			MODULE_RPREFIX+="/${COMPILER}/${COMPILER_VERSION}"
			
			MODULE_NAME="${COMPILER}/${COMPILER_VERSION}/"
			MODULE_NAME+="hdf5_serial/${HDF5_SERIAL_VERSION}/"
			MODULE_NAME+="${P}/${V}"
			;;
		* )
			std::die 1 "$P: oops: unknown group: ${MODULE_GROUP}"
			;;
		esac

		# set PREFIX of module
		PREFIX="${PMODULES_ROOT}/${MODULE_GROUP}/${MODULE_RPREFIX}"

		# get module release if already installed
		local saved_modulepath=${MODULEPATH}
		rels=( ${releases//:/ } )
		for rel in "${rels[@]}"; do
			eval $("${MODULECMD}" bash unuse ${rel})
		done
		for rel in "${rels[@]}"; do
			eval $("${MODULECMD}" bash use ${rel})
			if pbuild::module_is_available "${P}/${V}"; then
				cur_module_release=${rel}
				std::info "${P}/${V}: already available and released as \"${rel}\""
				break
			fi
		done
		MODULEPATH=${saved_modulepath}

		# set release of module
		# release is deprecated
		#   - if a build-dependency is deprecated or 
		#   - the module already exists and is deprecated or
		#   - is forced to be deprecated by setting this on the command line
		if [[ "${depend_release}" == 'deprecated' ]] || \
		       [[ "${cur_module_release}" == 'deprecated' ]] \
		       || [[ "${MODULE_RELEASE}" == 'deprecated' ]]; then
			MODULE_RELEASE='deprecated'
			std::info "${P}/${V}: will be released as \"deprecated\""
			#
			# release is stable
			#   - if all build-dependency are stable or
			#   - the module already exists and is stable
			#   - an unstable release of the module exists and the release is
			#     changed to stable on the command line
		elif [[ "${depend_release}" == 'stable' ]] \
			 || [[ "${cur_module_release}" == 'stable' ]] \
			 || [[ "${MODULE_RELEASE}" == 'stable' ]]; then
			MODULE_RELEASE='stable'
			std::info "${P}/${V}: will be released as \"stable\""
			#
			# release is unstable
			#   - if a build-dependency is unstable or 
			#   - if the module does not exists and no other release-type is
			#     given on the command line
			#   - and all the cases I didn't think of
		else
			MODULE_RELEASE='unstable'
			std::info "${P}/${V}: will be released as \"unstable\""
		fi

		# directory for README's, license files etc
		DOCDIR="${PREFIX}/share/doc/$P"

		# set tar-ball and flags for tar
		find_tarball "${BUILD_DOWNLOADSDIR}" "${P/_serial}" "${V}"

	}

	# redefine function for bootstrapping
	check_and_setup_env_bootstrap() {
		if [[ -z ${MODULE_GROUP} ]]; then
			std::die 1 "$P: group not set."
		fi

		if [[ -z $V ]]; then
			V=$(eval echo \$${_P}_VERSION)
		fi

		# oops, we need a version
		if [[ -z $V ]]; then
			std::die 1 "$P: Missing version."
		fi
		MODULE_SRCDIR="${BUILD_TMPDIR}/src/${P/_serial}-$V"
		MODULE_BUILDDIR="${BUILD_TMPDIR}/build/$P-$V"
		MODULE_GROUP='Tools'
		MODULE_NAME="Pmodules/${PMODULES_VERSION}"
		# set PREFIX of module
		PREFIX="${PMODULES_ROOT}/${MODULE_GROUP}/${MODULE_NAME}"
		
		MODULE_RELEASE='unstable'
		std::info "${MODULE_NAME}: will be released as \"${MODULE_RELEASE}\""

		# directory for README's, license files etc
		DOCDIR="${PREFIX}/share/doc/$P"

		# set tar-ball and flags for tar
		find_tarball "${BUILD_DOWNLOADSDIR}" "${P/_serial}" "${V}"

		C_INCLUDE_PATH="${PREFIX}/include"
		CPLUS_INCLUDE_PATH="${PREFIX}/include"
		CPP_INCLUDE_PATH="${PREFIX}/include"
		LIBRARY_PATH="${PREFIX}/lib"
		LD_LIBRARY_PATH="${PREFIX}/lib"
		DYLD_LIBRARY_PATH="${PREFIX}/lib"

		PATH+=":${PREFIX}/bin"
	}

	##############################################################################	
	check_compiler() {
		test -z ${MODULE_SUPPORTED_COMPILERS} && return 0
		for cc in ${MODULE_SUPPORTED_COMPILERS[@]}; do
			if [[ ${COMPILER}/${COMPILER_VERSION} =~ ${cc} ]]; then
				return 0
			fi
		done
		std::die 0 "Package cannot be build with ${COMPILER}/${COMPILER_VERSION}."
	}

	##############################################################################
	prep() {
		# untar sources
		if [[ ! -d ${MODULE_SRCDIR} ]]; then
			mkdir -p "${BUILD_TMPDIR}/src"
			(cd "${BUILD_TMPDIR}/src" && tar xvf "${TARBALL}")
		fi

		# create build directory
		mkdir -p "${MODULE_BUILDDIR}"
	}

	##############################################################################
	post_install() {
		# unfortunatelly sometime we need an OS depended post-install
		post_install_linux() {
			cd "${PREFIX}"
			# solve multilib problem with LIBRARY_PATH on 64bit Linux
			[[ -d "lib" ]] && [[ ! -d "lib64" ]] && ln -s lib lib64
			return 0
		}

		std::info "Run post-installation for ${OS} ..."
		[[ "${OS}" == "Linux" ]] && post_install_linux
		std::info "Post-installation done ..."
		return 0
	}

	##############################################################################
	write_runtime_dependencies() {
		local -r fname="${PREFIX}/.dependencies"
		std::info "Writing run-time dependencies to ${fname}"
		local dep
		echo -n "" > "${fname}"
		for dep in "${MODULE_DEPENDENCIES[@]}"; do
			[[ -z $dep ]] && continue
			if [[ ! $dep =~ .*/.* ]]; then
				local _V=$(echo -n $dep | tr [:lower:] [:upper:] )_VERSION
				dep=$dep/${!_V}
			fi
			echo "${dep}" >> "${fname}"
		done
	}

	##############################################################################
	write_build_dependencies() {
		local -r fname="${PREFIX}/.build_dependencies"
		std::info "Writing build dependencies to ${fname}"
		local dep
		echo -n "" > "${fname}"
		for dep in "${MODULE_BUILD_DEPENDENCIES[@]}"; do
			[[ -z $dep ]] && continue
			if [[ ! $dep =~ "*/*" ]]; then
				local _V=$(echo -n $dep | tr [:lower:] [:upper:] )_VERSION
				dep=$dep/${!_V}
			fi
			echo "${dep}" >> "${fname}"
		done
	}

	##############################################################################
	set_legacy_link() {
		local -r link_name="${PMODULES_ROOT}/${PMODULES_MODULEFILES_DIR}/${MODULE_GROUP}/${MODULE_NAME}"
		local -r dir_name=${link_name%/*}
		local -r release_file="${dir_name}/.release-${MODULE_NAME##*/}"
		if [[ ! -e "${_path}" ]]; then
			(
				std::info "Setting new sym-link \"${link_name}\" ..."
				mkdir -p "${dir_name}"
				cd "${dir_name}"
				local x
				IFS='/' x=( ${dir_name/${PMODULES_ROOT}\/${PMODULES_MODULEFILES_DIR}\/} )
				local n=${#x[@]}
				local -r _target="../"$(eval printf "../%.s" {1..${n}})${PMODULES_TEMPLATES_DIR##*/}/"${MODULE_GROUP}/${P}/modulefile"
				ln -fs "${_target}" "${MODULE_NAME##*/}"
			)
		fi
		std::info "${MODULE_NAME}: set release to '${MODULE_RELEASE}'"
		echo "${MODULE_RELEASE}" > "${release_file}"
	}

	##############################################################################
	set_link() {
		local -r link_name="${PMODULES_ROOT}/${MODULE_GROUP}/${PMODULES_MODULEFILES_DIR}/${MODULE_NAME}"
		local -r dir_name=${link_name%/*}
		local -r release_file="${dir_name}/.release-${MODULE_NAME##*/}"
		if [[ ! -e "${_path}" ]]; then
			(
				std::info "Setting new sym-link \"${link_name}\" ..."
				mkdir -p "${dir_name}"
				cd "${dir_name}"
				local x
				IFS='/' x=( ${dir_name/${PMODULES_ROOT}\/${MODULE_GROUP}\/} )
				local n=${#x[@]}
				local -r _target="../"$(eval printf "../%.s" {1..${n}})${PMODULES_TEMPLATES_DIR##*/}/"${MODULE_GROUP}/${P}/modulefile"
				ln -fs "${_target}" "${MODULE_NAME##*/}"
			)
		fi
		std::info "${MODULE_NAME}: set release to '${MODULE_RELEASE}'"
		echo "${MODULE_RELEASE}" > "${release_file}"
	}

	##############################################################################
	#
	# here we really start with make_all()
	#
	local building='no'
	echo "${P}:"
	set_default_versions "${BUILD_VERSIONSFILE}"

	# setup module specific environment
	if [[ ${bootstrap} == no ]]; then
		load_build_dependencies
		check_and_setup_env
	else
		check_and_setup_env_bootstrap
	fi

	if [[ ! -d "${PREFIX}" ]] || [[ ${force_rebuild} == 'yes' ]] || [[ ${bootstrap} == 'yes' ]]; then
		building='yes'
 		echo "Building $P/$V ..."
		[[ ${dry_run} == yes ]] && std::die 0 ""
		check_compiler

		if [[ ! -e "${MODULE_BUILDDIR}/.prep" ]]; then
			prep
			touch "${MODULE_BUILDDIR}/.prep"
		fi
		[[ "${target}" == "prep" ]] && return 0

		if [[ ! -e "${MODULE_BUILDDIR}/.configure" ]]; then
			cd "${MODULE_SRCDIR}"
			pbuild::pre_configure
			cd "${MODULE_BUILDDIR}"
			pbuild::configure
			touch "${MODULE_BUILDDIR}/.configure"
		fi
		[[ "${target}" == "configure" ]] && return 0

		if [[ ! -e "${MODULE_BUILDDIR}/.compile" ]]; then
			cd "${MODULE_BUILDDIR}"
			pbuild::build
			touch "${MODULE_BUILDDIR}/.compile"
		fi
		[[ "${target}" == "compile" ]] && return 0

		if [[ ! -e "${MODULE_BUILDDIR}/.install" ]]; then
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
 		echo "Not rebuilding $P/$V ..."
	fi
	if [[ ${bootstrap} == 'no' ]]; then
		if [[ -d "${PMODULES_ROOT}/${PMODULES_MODULEFILES_DIR}" ]]; then
			set_legacy_link
		fi
		set_link
	fi
	return 0
}

# Local Variables:
# mode: sh
# sh-basic-offset: 8
# tab-width: 8
# End:
