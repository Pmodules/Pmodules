#!/bin/bash

if [[  -z ${bindir} ]]; then
        local bindir=$(dirname "${BASH_SOURCE}")
	bindir=$(cd "${bindir}"/.. && pwd)"/bin"
	sbindir=$(cd "${bindir}"/.. && pwd)"/sbin"
fi

pmodules::get_options() {
	"${sbindir}/getopt" "$@"
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
	    [[ -d "${src_prefix}/Tools/Pmodules/${PMODULES_VERSION}" ]] || std::die 1 "
Error: the module environment '${src_prefix}' has not been initialized properly!"
}

pmodules::check_env() {
	pmodules::check_env_vars
	pmodules::check_directories "${PMODULES_ROOT}"
}


# Local Variables:
# mode: sh
# sh-basic-offset: 8
# tab-width: 8
# End:
