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
        [[ ${PMODULES_DEBUG} ]] || return 0
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
	local -r P=$1
	local -r d=$2

        if ! echo ${!P} | egrep -q "(^|:)${d}($|:)" ; then
		if [[ -z ${!P} ]]; then
			export "$P=${d}"
		else
			export "$P=${!P}:${d}"
        	fi
	fi
}

std::prepend_path () {
        local -r P=$1
        local -r d=$2

        if ! echo ${!P} | egrep -q "(^|:)${d}($|:)" ; then
                if [[ -z ${!P} ]]; then
                        export "$P=${d}"
                else
                        export "$P=${d}:${!P}"
                fi
        fi
}

std::remove_path() {
        local -r P=$1
        local -r d=$2
	local new_path=''
	local -r _P=( ${!P//:/ } )
	# loop over all entries in path
	for entry in "${_P[@]}"; do
		[[ "${entry}" != "${d}" ]] && new_path+=":${entry}"
	done
	# remove leading ':'
	eval ${P}="${new_path:1}"
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
# split file name
#
# Args:
#     $1  upvar
#     $2  fname (=${@: -1})
#   or
#     $1  upvar
#     $2  number of components
#     $3  fname (=${@: -1})
#
std::split_fname() {
	local "$1"
	local  -r fname="${@: -1}"
	if [[ "${fname:0:1}" == '/' ]]; then
		local -r tmp="${fname:1}"
	else
		local -r tmp="${fname}"
	fi
	
        IFS='/'
        local std__split_fname_result__=( ${tmp} )
	unset IFS
        eval $1=\(\"\${std__split_fname_result__[@]}\"\)
	if (( $# >= 3 )); then
	        eval $2=${#std__split_fname_result__[@]}
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

#--- upvars.sh ---------------------------------------------------------
# Bash: Passing variables by reference
# Copyright (C) 2010 Freddy Vulto
# Version: upvars-0.9.dev
# See: http://fvue.nl/wiki/Bash:_Passing_variables_by_reference
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


# Assign variable one scope above the caller
# Usage: local "$1" && upvar $1 "value(s)"
# Param: $1  Variable name to assign value to
# Param: $*  Value(s) to assign.  If multiple values, an array is
#            assigned, otherwise a single value is assigned.
# NOTE: For assigning multiple variables, use 'upvars'.  Do NOT
#       use multiple 'upvar' calls, since one 'upvar' call might
#       reassign a variable to be used by another 'upvar' call.
# Example: 
#
#    f() { local b; g b; echo $b; }
#    g() { local "$1" && upvar $1 bar; }
#    f  # Ok: b=bar
#
std::upvar() {
    if unset -v "$1"; then           # Unset & validate varname
        if (( $# == 2 )); then
            eval $1=\"\$2\"          # Return single value
        else
            eval $1=\(\"\${@:2}\"\)  # Return array
        fi
    fi
}

std.get_os_release_linux() {
        local lsb_release=$(which lsb_release)
        local ID=''
        local VERSION_ID=''

        if [[ -n $(which lsb_release) ]]; then
                ID=$(lsb_release -is)
                VERSION_ID=$(lsb_release -rs)
        elif [[ -r '/etc/os-release' ]]; then
	        source /etc/os-release
        else
                std::die 4 "Cannot determin OS release!\n"
        fi

	case "${ID}" in
		RedHatEnterpriseServer | RedHatEnterprise | Scientific | rhel | centos | CentOS | fedora )
			echo "rhel${VERSION_ID%%.*}"
			;;
		Ubuntu )
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
	${func_map[${OS}]}
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

# Local Variables:
# mode: sh
# sh-basic-offset: 8
# tab-width: 8
# End:
