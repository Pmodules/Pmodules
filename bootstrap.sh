#!/bin/bash

declare -a opts=()

while (( $# > 0 )); do
	case $1 in
		--debug )
			opts+=( "$1" )
			;;
		--config )
			opts+=( "$1=$2" )
			shift 1
			;;
		--config=* )
			opts+=( "$1" )
			;;
		--install-root )
			opts+=( "$1=$2" )
			shift 1
			;;
		--install-root=* )
			opts+=( "$1" )
			;;
		-f | --force )
			opts+=( "$1" )
			;;
		-* )
			std::die 1 "$1: illegal option"
			;;
		* )
			std::die 1 "No arguments are allowed."
			;;
	esac
	shift 1
done

${BASE_DIR}/compile_pmodules.sh "${opts[@]}" || exit 1
${BASE_DIR}/install_pmodules.sh "${opts[@]}" || exit 1

