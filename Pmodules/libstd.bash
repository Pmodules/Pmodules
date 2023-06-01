#!/bin/bash

#
# logging/message functions
#
std::log() {
        local -ri fd=$1
        local -r fmt="$2"
        shift 2
        printf -- "${fmt}" "$@" 1>&$fd
        printf -- "\n" 1>&$fd
}

std::info() {
        std::log 2 "$1" "${@:2}"
}

std::error() {
        std::log 2 "$1" "${@:2}"
}

std::debug() {
        [[ -v PMODULES_DEBUG ]] || return 0
        std::log 2 "$@"
}

std::die() {
        local -ri ec=$1
        shift
        if [[ -n $@ ]]; then
                local -r fmt=$1
                shift
                std::log 2 "$fmt" "$@"
        fi
        exit $ec
}

std::def_cmds(){
	local path="$1"
	shift
	for cmd in "$@"; do
		eval declare -gr ${cmd}=$(PATH="${path}" /usr/bin/which $cmd 2>/dev/null)
		if [[ -z "${!cmd}" ]]; then
			std::die 255 "${cmd} not found"
		fi
	done
}

#
# get answer to yes/no question
#
# $1: prompt
#
std::get_YN_answer() {
	local -r prompt="$1"
	local ans
	read -p "${prompt}" ans
	case ${ans} in
		y|Y ) 
			return 0;;
		* )
			return 1;;
	esac
}

#
# return normalized abolute pathname
# $1: filename
std::get_abspath() {
	local -r fname=$1
	#[[ -r "${fname}" ]] || return 1
	if [[ -d ${fname} ]]; then
		echo $(cd "${fname}" && pwd)
	else
		local -r dname=$(dirname "${fname}")
		echo $(cd "${dname}" && pwd)/$(basename "${fname}")
	fi
}

std::append_path () {
        local -nr P="$1"
	shift 1
	local dir
	local dirs=''
	for dir in "$@"; do
		[[ "${P}" == @(|*:)${dir}@(|:*) ]] && continue
		dirs+=":${dir}"
	done

        if [[ -z ${P} ]]; then
                P="${dirs:1}"		# remove leading ':'
        else
		P="${P}${dirs}"
        fi
}

std::prepend_path () {
        local -nr P="$1"
	shift 1

	local dir
	local dirs=''
	for dir in "$@"; do
		[[ "${P}" == @(|*:)${dir}@(|:*) ]] && continue
		dirs+="${dir}:"
	done

        if [[ -z ${P} ]]; then
                P="${dirs:0:-1}"	# remove trailing ':'
        else
		P="${dirs}${P}"
        fi
}

std::remove_path() {
        local -nr P="$1"
	shift 1
        local -ar dirs="$@"
	local new_path=''
	local -r _P=( ${P//:/ } )
	local dir=''
	for dir in "${dirs[@]}"; do
		# loop over all entries in path
		for entry in "${_P[@]}"; do
			[[ "${entry}" != "${dir}" ]] && new_path+=":${entry}"
		done
	done
	P="${new_path:1}"		# remove leading ':'
}

#
# Replace or remove a directory in a path variable.
#
# To remove a dir:
#	std::replace_path PATH <pattern>
#
# To replace a dir:
#	std::replace_path PATH <pattern> /replacement/path
#
# Args:
#	$1 name of the shell variable to set (e.g. PATH)
#	$2 a grep pattern identifying the element to be removed/replaced
#	$3 the replacement string (use "" for removal)
#
# Based on solution published here:
# https://stackoverflow.com/questions/273909/how-do-i-manipulate-path-elements-in-shell-scripts 
#
std::replace_path () {
	local -r path="$1"
	local -r removepat="$2"
	local -r replacestr="$3"

	local -r removestr=$(echo "${!path}" | tr ":" "\n" | grep -m 1 "^$removepat\$")
	export $path="$(echo "${!path}" | tr ":" "\n" | sed "s:^${removestr}\$:${replacestr}:" |
                   sed '/^\s*$/d' | tr "\n" ":" | sed -e 's|^:||' -e 's|:$||')"
}

#
# Functions to split a path into its components.
#
# Args:
#     $1  upvar
#     $2  absolute or relative path (depends on the function)
#     $3  opt upvar: number of components
#
# Notes:
# std::split_path()
#     if the path is absolute, the first element of the returned array is empty.
#
# std::split_abspath()
#     the path must begin with a slash, otherwise std::die() is called with
#     an internal error message.
#
# std::split_relpath()
#     analog to std::split_abspath() with a relative path.
#
std::split_path() {
	local -n parts="$1"
	local -r path="$2"

        IFS='/'
        local std__split_path_result=( ${std__split_path_tmp} )
	unset IFS
	parts="${std__split_path_result[@]}"
	if (( $# >= 3 )); then
		# return number of parts
		local -n num="$3"
	        num="${#std__split_path_result[@]}"
	fi
}

std::split_abspath() {
	local -n parts="$1"
	local -r path="$2"
	if [[ "${path:0:1}" == '/' ]]; then
		local -r std__split_path_tmp="${path:1}"
	else
		std::die 255 "Oops: Internal error in '${FUNCNAME[0]}' called by '${FUNCNAME[1]}' }"
	fi

        IFS='/'
        local std__split_path_result=( ${std__split_path_tmp} )
	unset IFS
	parts="${std__split_path_result[@]}"
	if (( $# >= 3 )); then
		# return number of parts
		local -n num="$3"
	        num="${#std__split_path_result[@]}"
	fi
}

std::split_relpath() {
	local -n parts="$1"
	local -r path="$2"
	if [[ "${path:0:1}" == '/' ]]; then
		std::die 255 "Oops: Internal error in '${FUNCNAME[0]}' called by '${FUNCNAME[1]}' }"
	else
		local -r std__split_path_tmp="${path}"
	fi

        IFS='/'
        local std__split_path_result=( ${std__split_path_tmp} )
	unset IFS
	parts="${std__split_path_result[@]}"
	if (( $# >= 3 )); then
		# return number of parts
		local -n num="$3"
	        num="${#std__split_path_result[@]}"
	fi
}

std::read_versions() {
	local -r fname="$1"
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

std.get_os_release_linux() {
        #local lsb_release=$(which lsb_release)
        local ID=''
        local VERSION_ID=''

        if [[ -n $(which lsb_release 2>/dev/null) ]]; then
                ID=$(lsb_release -is)
                VERSION_ID=$(lsb_release -rs)
        elif [[ -r '/etc/os-release' ]]; then
	        source /etc/os-release
        else
                std::die 4 "Cannot determin OS release!\n"
        fi

	case "${ID,,}" in
		redhatenterpriseserver | redhatenterprise | scientific | springdale | rhel | centos | fedora )
			echo "rhel${VERSION_ID%%.*}"
			;;
		ubuntu )
			echo "Ubuntu${VERSION_ID%.*}"
			;;
		* )
			echo "Unknown"
			exit 1
			;;
	esac
}
std.get_os_release_macos() {
	VERSION_ID=$(sw_vers -productVersion)
	echo "macOS${VERSION_ID%.*}"
}

std::get_os_release() {
	local -A func_map;
	func_map['Linux']=std.get_os_release_linux
	func_map['Darwin']=std.get_os_release_macos
	${func_map[$(uname -s)]}
}

std::get_type() {
	local -a signature=$(typeset -p "$1")
	case ${signature[1]} in
		-Ai* )
			echo 'int dict'
			;;
		-A* )
			echo 'dict'
			;;
		-ai* )
			echo 'int array'
			;;
		-a* )
			echo 'array'
			;;
		-i* )
			echo 'integer'
			;;
		-- )
			echo 'string'
			;;
		* )
			echo 'none'
			return 1
	esac
}

std::parse_yaml() {
	#
	# parse a YAML file
	# See: https://gist.github.com/pkuczynski/8665367
	#
	local -r fname="$1"
	local -r prefix="$2"
	local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
	sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
            -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" "${fname}" |
		awk -F$fs '{
		      indent = length($1)/2;	
		      vname[indent] = $2;	
		      for (i in vname) {
                          if (i > indent) {delete vname[i]}
                      }
		      if (length($3) > 0) {
		          vn="";
                          for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
		          printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
	              }
                }'
}
# Local Variables:
# mode: sh
# sh-basic-offset: 8
# tab-width: 8
# End:
