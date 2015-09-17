#!/bin/bash
#
#############################################################################
#              D O   N O T   C H A N G E   T H I S   F I L E !              #
#############################################################################

#############################################################################
# read Pmodules configuration
#
_init_env_file="$(dirname ${BASH_SOURCE})/environment.bash"
if [[ ! -r "${_init_env_file}" ]]; then
	echo "Oops: cannot initialize Modules!"
	echo "${_init_env_file}: file does not exist or is not readable."
	return 1
fi
source "${_init_env_file}"
unset _init_env_file

############################################################################
# check configuration
#
if [[ -z ${PMODULES_ROOT} ]]; then 
	echo "Oops: Pmodules root not set." 1>&2
	return 1
fi
if [[ ! -d ${PMODULES_ROOT} ]]; then 
	echo "Oops: ${PMODULES_ROOT}: Set as Pmodules root, but this is not a directory." 1>&2
	return 1
fi
if [[ -z ${PMODULES_VERSION} ]]; then
	echo "Oops: ${PMODULES_VERSION}: Pmodules version not set." 1>&2
	return 1
fi
if [[ -z ${PMODULES_HOME} ]]; then 
	echo "Oops: Pmodules home not set." 1>&2
	return 1
fi
if [[ ! -d ${PMODULES_HOME} ]]; then
	echo "Oops: ${PMODULES_HOME}: Set as Pmodules home, but this is not a directory." 1>&2
	return 1
fi

############################################################################
# inititialize Pmodules for bash
#
_init_bash="${PMODULES_HOME}/init/bash"
if [[ ! -r "${_init_bash}" ]]; then
	echo "Oops: cannot initialize Modules!"
	echo "${_init_bash}: File does not exist or is not readable."
	return 1
fi
source "${_init_bash}"
unset _init_bash

# Local Variables:
# mode: sh
# sh-basic-offset: 8
# tab-width: 8
# End:
