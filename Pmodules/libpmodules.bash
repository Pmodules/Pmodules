#!/bin/bash

if [[  -z ${bindir} ]]; then
        local bindir=$(dirname "${BASH_SOURCE}")
	bindir=$(cd "${bindir}"/.. && pwd)"/bin"
fi

pmodules::get_options() {
	"${bindir}/getopt" "$@"
}

pmodules::check_env_vars() {
	[[ -n "${PMODULES_ROOT}" ]] &&
	    [[ -n "${PMODULES_CONFIG_DIR}" ]] &&
	    [[ -n "${PMODULES_TEMPLATES_DIR}" ]] &&
	    [[ -n "${PMODULES_HOME}" ]] &&
	    [[ -n "${PMODULES_VERSION}" ]] || std::die 1 "
Error: the module environment you are going to use as source has not been
initialized properly!"
}

pmodules::check_directories() {
	local -r src_prefix="$1"

	[[ -d "${src_prefix}" ]] &&
	    [[ -d "${src_prefix}/${PMODULES_CONFIG_DIR}" ]] &&
	    [[ -d "${src_prefix}/${PMODULES_TEMPLATES_DIR}" ]] &&
	    [[ -d "${src_prefix}/Tools/Pmodules/${PMODULES_VERSION}" ]] || std::die 1 "
Error: the module environment '${src_prefix}' has not been initialized properly!"
}

pmodules::check_env() {
	pmodules::check_env_vars
	pmodules::check_directories "${PMODULES_ROOT}"
}


std::log() {
        local -ri fd=$1
        local -r fmt="$2\n"
        shift 2
        printf -- "$fmt" "$@" 1>&$fd
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

# Local Variables:
# mode: sh
# sh-basic-offset: 8
# tab-width: 8
# End:
