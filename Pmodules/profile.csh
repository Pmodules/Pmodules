#!/bin/tcsh

#############################################################################
# read Pmodules configuration
#
set _init_env_file="/opt/psi/config/environment.bash"
if ( ! -r "$_init_env_file" ); then
	echo "Oops: cannot initialize Modules!"
	echo "$_init_env_file: file does not exist or is not readable."
	return 1
fi
source "$_init_env_file"
unset _init_env_file

############################################################################
# check configuration
#
if ( ! $?PMODULES_PREFIX ) then 
	echo "Oops: Pmodules prefix not set."
	return 1
endif

if ( "$PMODULES_PREFIX" == "" ) then
	echo "Oops: Pmodules prefix set to empty string!"
endif
if ( ! -d ${PMODULES_PREFIX} ) then 
	echo "Oops: ${PMODULES_PREFIX}: Set as Pmodules prefix, but this is not a directory!"
	return 1
endif

if ( ! $?PMODULES_VERSION ) then
	echo "Oops: Pmodules version not set!"
	return 1
endif
if ( "$PMODULES_VERSION" == "" ) then
	echo "Oops: Pmodules version set to empty string!"
	return 1
endif

if ( $?PMODULES_HOME ) then
	echo "Oops: Pmodules home not set!"
	return 1
endif
if ( "$PMODULES_HOME" == "" ) then
	echo "Oops: Pmodules home set to empty string!"
	return 1
fi
if ( ! -d "$PMODULES_HOME" ) then
	echo "Oops: $PMODULES_HOME: Set as Pmodules home, but this is not a directory!"
	return 1
endif

############################################################################
# inititialize Pmodules for bash
#
set _init_csh="$PMODULES_HOME/init/csh"
if ( ! -r "$_init_csh" ) then
	echo "Oops: cannot initialize Modules!"
	echo "$_init_csh: File does not exist or is not readable."
	return 1
fi
source "$_init_csh"
unset _init_csh

# Local Variables:
# mode: csh
# sh-basic-offset: 8
# tab-width: 8
# End:
