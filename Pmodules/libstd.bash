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
        if (( ${#@} > 0 )); then
                local -r fmt=$1
                shift
                std::log 2 "$fmt" "$@"
        fi
        exit $ec
}

std::def_cmd(){
	which "$1" 2>/dev/null || std::die 255 "'$1' not found!"
}

#..............................................................................
#
# compare two version numbers
#
# std::version_compare
#	- returns 0 if the version numbers are equal
#	- returns 1 if first version number is higher
#	- returns 2 if second version number is higher
#
# std::version_lt
#	- returns 0 if second version number is higher
# std::version_le
#	- returns 0 if second version number is higher or equal
# std::version_gt
#	- returns 0 if first version number is higher
# std::version_ge
#	- returns 0 if first version number is higher or equal
#
# otherwise a value != 0 is returned
#
# Arguments:
#	$1 first version number
#	$2 second version number
#
# Note:
#	Original implementation found on stackoverflow:
# https://stackoverflow.com/questions/4023830/how-to-compare-two-strings-in-dot-separated-version-format-in-bash
#
std::version_compare () {
        is_uint() {
                [[ $1 =~ ^[0-9]+$ ]]
        }

        [[ "$1" == "$2" ]] && return 0
	local ver1 ver2
        IFS='.' read -r -a ver1 <<<"$1"
        IFS='.' read -r -a ver2 <<<"$2"

        # fill empty fields in ver1 with zeros
        local i
        for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
                ver1[i]=0
        done
        for ((i=0; i<${#ver1[@]}; i++)); do
                [[ -z ${ver2[i]} ]] && ver2[i]=0
                if is_uint "${ver1[i]}" && is_uint "${ver2[i]}"; then
                        ((10#${ver1[i]} > 10#${ver2[i]})) && return 1
                        ((10#${ver1[i]} < 10#${ver2[i]})) && return 2
                else
                        [[ ${ver1[i]} > ${ver2[i]} ]] && return 1
                        [[ ${ver1[i]} < ${ver2[i]} ]] && return 2
                fi
        done
        return 0
}
readonly -f std::version_compare

std::version_lt() {
	local -r __doc__="
	result:
	    0 if version in $1 is less than version in $2.
	    >=1: otherwise
	"
	if (( $# == 1 )); then
		local vers1="${V_PKG}"
		local vers2="$1"
	else
		local vers1="$1"
		local vers2="$2"
	fi
        std::version_compare "${vers1}" "${vers2}"
        (( $? == 2 ))
}
readonly -f std::version_lt

std::version_le() {
	local -r __doc__="
	result:
	    0 if version in $1 is less than or equal version in $2.
	    >=1: otherwise
	"
	if (( $# == 1 )); then
		local vers1="${V_PKG}"
		local vers2="$1"
	else
		local vers1="$1"
		local vers2="$2"
	fi
        std::version_compare "${vers1}" "${vers2}"
        local -i exit_code=$?
        (( exit_code == 0 || exit_code == 2 ))
}
readonly -f std::version_le

std::version_gt() {
	local -r __doc__="
	result:
	    0 if version in $1 is greate than version in $2.
	    >=1: otherwise
	"
	if (( $# == 1 )); then
		local vers1="${V_PKG}"
		local vers2="$1"
	else
		local vers1="$1"
		local vers2="$2"
	fi
        std::version_compare "${vers1}" "${vers2}"
        (( $? == 1 ))
        local -i exit_code=$?
        (( exit_code == 1 ))
}
readonly -f std::version_gt

std::version_ge() {
	local -r __doc__="
	result:
	    0 if version in $1 is greate than or equal version in $2.
	    >=1: otherwise
	"
	#	- returns 0 if version numbers are equal
	if (( $# == 1 )); then
		local vers1="${V_PKG}"
		local vers2="$1"
	else
		local vers1="$1"
		local vers2="$2"
	fi
        std::version_compare "${vers1}" "${vers2}"
        (( $? == 1 ))
        local -i exit_code=$?
        (( exit_code == 0 || exit_code == 1 ))
}
readonly -f std::version_gt

std::version_eq() {
	local -r __doc__="
	result:
	    0 if versions are equal
	    >=1 otherwise
	"
	if (( $# == 1 )); then
		local vers1="${V_PKG}"
		local vers2="$1"
	else
		local vers1="$1"
		local vers2="$2"
	fi
        std::version_compare "${vers1}" "${vers2}"
}
readonly -f std::version_eq

awk=$(std::def_cmd 'awk');		declare -r awk
base64=$(std::def_cmd 'base64');	declare -r base64
bash=$(std::def_cmd 'bash');		declare -r bash
cat=$(std::def_cmd 'cat');		declare -r cat
cp=$(std::def_cmd 'cp');		declare -r cp
curl=$(std::def_cmd 'curl');		declare -r curl
envsubst=$(std::def_cmd 'envsubst');	declare -r envsubst
dirname=$(std::def_cmd 'dirname');	declare -r dirname
file=$(std::def_cmd 'file');		declare -r file
find=$(std::def_cmd 'find');		declare -r find
getopt=$(std::def_cmd 'getopt');	declare -r getopt
grep=$(std::def_cmd 'grep');		declare -r grep
hostname=$(std::def_cmd 'hostname');	declare -r hostname
install=$(std::def_cmd 'install');	declare -r install
logger=$(std::def_cmd 'logger');	declare -r logger
make=$(std::def_cmd 'make');		declare -r make
mkdir=$(std::def_cmd 'mkdir');		declare -r mkdir
mktemp=$(std::def_cmd 'mktemp');	declare -r mktemp
modulecmd=$(std::def_cmd 'modulecmd');	declare -- modulecmd
patch=$(std::def_cmd 'patch');		declare -r patch
pwd=$(std::def_cmd 'pwd');		declare -r pwd
rm=$(std::def_cmd 'rm');		declare -r rm
rmdir=$(std::def_cmd 'rmdir');		declare -r rmdir
sed=$(std::def_cmd 'sed');		declare -r sed
seq=$(std::def_cmd 'seq');		declare -r seq
sevenz=$(std::def_cmd 'sevenz');	declare -r sevenz
sort=$(std::def_cmd 'sort');		declare -r sort
tar=$(std::def_cmd 'tar');		declare -r tar
tee=$(std::def_cmd 'tee');		declare -r tee
touch=$(std::def_cmd 'touch');		declare -r touch
tput=$(std::def_cmd 'tput');		declare -r tput
uname=$(std::def_cmd 'uname');		declare -r uname
yq=$(std::def_cmd 'yq');		declare -r yq

KernelName=$(${uname} -s);		declare -r KernelName
if [[ ${KernelName} == 'Darwin' ]]; then
	PATH+=':/opt/local/bin'
	otool=$(std::def_cmd 'otool');	declare -r otool
	shasum=$(std::def_cmd 'shasum');declare -r shasum
	sysctl=$(std::def_cmd 'sysctl');declare -r sysctl
	declare -r sha256sum="${shasum -a 256}"
else
	ldd=$(std::def_cmd 'ldd');	declare -r ldd
	patchelf=$(std::def_cmd 'patchelf');	declare -r patchelf
	sha256sum=$(std::def_cmd 'sha256sum');
	declare -r sha256sum
fi

#
# get answer to yes/no question
#
# $1: prompt
#
std::get_YN_answer() {
	local -r prompt="$1"
	local ans
	read -r -p "${prompt}" ans
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
	local -r fname="$1"
	local -- abspath=''
	#[[ -r "${fname}" ]] || return 1
	if [[ -d ${fname} ]]; then
		abspath=$(cd "${fname}" && pwd -L)
	else
		local -r dname=$(dirname "${fname}")
		abspath=$(cd "${dname}" && pwd -L)/$(basename "${fname}")
	fi
	echo "${abspath}"
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
        local -nr path="$1"
	shift 1
        local -ar remove_dirs=("$@")
	local new_path=''
	local -a _path=()
	IFS=':' read -r -a _path <<<"${path}"
	local dir=''
	for dir in "${remove_dirs[@]}"; do
		# loop over all entries in path
		for entry in "${_path[@]}"; do
			[[ "${entry}" != "${dir}" ]] && new_path+=":${entry}"
		done
	done
	path="${new_path:1}"		# remove leading ':'
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
		suse )
			echo "sles${VERSION_ID%.*}"
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
	local -a signature=()
	read -r -a signature <(typeset -p "$1")
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

std::is_member_of_array(){
	local -- item="$1"
	local -n array="$2"
	local -- el=''
	for el in "${array[@]}"; do
		[[ "${item}" == "${el}" ]] && return 0
	done
	return 1
}

std::find_executables(){
	${find} "$@" -type f -printf "%i %P\n" | \
		${sort} -n -k1 -u              | \
		${awk} '{print $2}'            | \
		${file} -f -                   | \
		${awk} '$2 ~ /ELF/ && $3 ~ /64-bit/ && $5 ~ /executable/  {print substr($1, 1, length($1)-1)}'
}

std::find_shared_objects(){
	${find} "$@" -type f -printf "%i %P\n" | \
		${sort} -n -k1 -u              | \
		${awk} '{print $2}'            | \
		${file} -f -                   | \
		${awk} '$2 ~ /ELF/ && $3 ~ /64-bit/ && $5 ~ /shared/ && $6 ~ /object/  {print substr($1, 1, length($1)-1)}'
}

std::get_dir_depth(){
	echo "$1" | ${grep} -o / | wc -l
}
# Local Variables:
# mode: sh
# sh-basic-offset: 8
# tab-width: 8
# End:
