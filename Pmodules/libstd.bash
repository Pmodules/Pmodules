#!/bin/bash

#
# logging/message functions
#
std::log() {
        local -ri fd=$1
        local -r fmt="$2"
        shift 2
        printf -- "$fmt" "$@" 1>&$fd
        echo
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
	[[ -r "${fname}" ]] || return 1
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
                        eval $P=${d}
                else
                        eval $P=${!P}:${d}
                fi
        fi
}

std::prepend_path () {
        local -r P=$1
        local -r d=$2

        if ! echo ${!P} | egrep -q "(^|:)${d}($|:)" ; then
                if [[ -z ${!P} ]]; then
                        eval $P=${d}
                else
                        eval $P=${d}:${!P}
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
# split file name
#
std::split_fname() {
        local -r savedIFS="${IFS}"
        IFS='/'
        local std__split_fname_result__=( $(echo "${@: -1}") )
        IFS=${savedIFS}
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


# Assign variables one scope above the caller
# Usage: local varname [varname ...] && 
#        upvars [-v varname value] | [-aN varname [value ...]] ...
# Available OPTIONS:
#     -aN  Assign next N values to varname as array
#     -v   Assign single value to varname
# Return: 1 if error occurs
# Example:
#
#    f() { local a b; g a b; declare -p a b; }
#    g() {
#        local c=( foo bar )
#        local "$1" "$2" && upvars -v $1 A -a${#c[@]} $2 "${c[@]}"
#    }
#    f  # Ok: a=A, b=(foo bar)
#
std::upvars() {
    if ! (( $# )); then
        echo "${FUNCNAME[0]}: usage: ${FUNCNAME[0]} [-v varname"\
            "value] | [-aN varname [value ...]] ..." 1>&2
        return 2
    fi
    while (( $# )); do
        case $1 in
            -a*)
                # Error checking
                [[ ${1#-a} ]] || { echo "bash: ${FUNCNAME[0]}: \`$1': missing"\
                    "number specifier" 1>&2; return 1; }
                printf %d "${1#-a}" &> /dev/null || { echo "bash:"\
                    "${FUNCNAME[0]}: \`$1': invalid number specifier" 1>&2
                    return 1; }
                # Assign array of -aN elements
                [[ "$2" ]] && unset -v "$2" && eval $2=\(\"\${@:3:${1#-a}}\"\) && 
                shift $((${1#-a} + 2)) || { echo "bash: ${FUNCNAME[0]}:"\
                    "\`$1${2+ }$2': missing argument(s)" 1>&2; return 1; }
                ;;
            -v)
                # Assign single value
                [[ "$2" ]] && unset -v "$2" && eval $2=\"\$3\" &&
                shift 3 || { echo "bash: ${FUNCNAME[0]}: $1: missing"\
                "argument(s)" 1>&2; return 1; }
                ;;
            --help) echo "\
Usage: local varname [varname ...] &&
   ${FUNCNAME[0]} [-v varname value] | [-aN varname [value ...]] ...
Available OPTIONS:
-aN VARNAME [value ...]   assign next N values to varname as array
-v VARNAME value          assign single value to varname
--help                    display this help and exit
--version                 output version information and exit"
                return 0 ;;
            --version) echo "\
${FUNCNAME[0]}-0.9.dev
Copyright (C) 2010 Freddy Vulto
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law."
                return 0 ;;
            *)
                echo "bash: ${FUNCNAME[0]}: $1: invalid option" 1>&2
                return 1 ;;
        esac
    done
}

# Local Variables:
# mode: sh
# sh-basic-offset: 8
# tab-width: 8
# End:
