#
# :TODO:
# switch/swap
# unload modules if parent removed
#

if {[info exists env(PMODULES_DEBUG)] && $env(PMODULES_DEBUG)} {
	proc debug {msg} {
		set level [expr [info level] -2] 
		set r [catch {info level ${level}} e]
		if {$r} {
			set caller ""
		} else {
			set caller [lindex [split [info level [expr [info level] - 3]]] 0]
		}
		puts -nonewline stderr "${caller}: "
		puts stderr ${msg}
	}
} else {
	proc debug {msg} {}
}

debug "loading libmodules"

package require base64

set ::MODULEFILES_DIR "modulefiles"
set ::ol_replacing "r"

# variable derived from PMODULES_ENV
array set ::OverlayInfo {}
set ::UsedGroups {}
set ::UsedOverlays {}

proc _pmodules_parse_pmodules_env { } {
	#
	# In this library we need the value of some BASH variables
	# defined in PMODULES_ENV. In this function we translate
	# these variables definitions - created in BASH with
	# 'typeset -p VAR' - to Tcl.
	#
	foreach line [split [base64::decode $::env(PMODULES_ENV)] "\n"] {
		# lines are something like "declare -a UsedGroups=value"
		# assign variable name -> key and value -> value
		if { ![regexp -- {.* -[aAx]* (.*)=\((.*)\)} $line -> key value] } {
			continue
		}
		switch $key {
			OverlayInfo {
				set tmp_olinfo [regsub -all {[]=[]} $value " "]
				array set ::OverlayInfo $tmp_olinfo
			}
		        UsedOverlays {
				# convert a string like
				# [0]="Alps_A100" [1]="PSI" [2]="Alps" [3]="merlin" [4]="base"
				# to
				# Alps_A100 PSI Alps merlin base
				set tmpstr [regsub -all  {\[[0-9]+\]=} $value ""]
				set tmpstr [regsub -all  {\"} $tmpstr ""]
  			        set ::UsedOverlays [split $tmpstr]
			}
			UsedGroups {
				set ::UsedGroups $value
			}
		}
	}
	debug "return"
}

debug "module-addgroup"
proc module-addgroup { group } {
	global env
	global name
	global version

	debug "called with arg $group"
        debug "mode=[module-info mode]"
        
	set	GROUP [string toupper $group]
	regsub -- "-" ${GROUP} "_" GROUP
	setenv	${GROUP}		$name
	setenv	${GROUP}_VERSION	$version

	set	::${group}		$name
	set	::${group}_version	$version

	if { [module-info mode load] } {
	        set overlays_to_add {}
		foreach overlay $::UsedOverlays {
			lappend overlays_to_add $overlay
		        set ol_type $::OverlayInfo($overlay:type)
		        debug "ol_type=$ol_type"
			if { [string compare $ol_type $::ol_replacing] == 0 } {
				break
			}
		}
		foreach overlay [lreverse $overlays_to_add] {
			debug "overlay=$overlay"
			debug "modulefiles_root=$::OverlayInfo($overlay:modulefiles_root)"
			debug "group=$group"
			debug "::variant=$::variant"
			set dir [file join \
				     $::OverlayInfo($overlay:modulefiles_root) \
				     $group \
				     $::MODULEFILES_DIR \
				     {*}$::variant]
			if { [file isdirectory $dir] } {
				debug "prepend $dir to MODULEPATH "
				prepend-path MODULEPATH $dir
			}
		}
		debug "end foreach"
		prepend-path UsedGroups $group
	} elseif { [module-info mode remove] } {
		set GROUP [string toupper $group]
		debug "mode=remove: hierarchical group '${GROUP}'"
		
		if { [info exists ::env(PMODULES_LOADED_${GROUP})] } {
			debug "mode=remove: unloading orphan modules"
			set modules [split $env(PMODULES_LOADED_${GROUP}) ":"]
			foreach m ${modules} {
				if { ${m} == "--APPMARKER--" } {
					continue
				}
				if { [is-loaded ${m}] } {
					debug "mode=remove: unloading $m"
					module unload ${m}
				}
			}
		} else {
			debug "mode=remove: no orphan modules to unload"
		}
		debug "mode=remove: $env(MODULEPATH)"
                foreach overlay $::UsedOverlays {
                        set dir [file join \
				     $::OverlayInfo($overlay:modulefiles_root) \
                                     $group \
                                     $::MODULEFILES_DIR \
                                     {*}$::variant]
		        debug "remove $dir"
                        remove-path MODULEPATH $dir
                }
		remove-path UsedGroups $group
                debug "mode=remove: $env(UsedGroups)"
	}
}

proc set-family { group } {
        module-addgroup $group
}

proc _pmodules_update_loaded_modules { group name version } {
	if { ${group} == "--APPMARKER--" } {
		return
	}
	set GROUP [string toupper $group]
	debug "${GROUP} $name/$version"
	append-path PMODULES_LOADED_${GROUP} "$name/$version"
	remove-path PMODULES_LOADED_${GROUP} "--APPMARKER--"
}

proc lreverse_n { list n } {
        set res {}
        set i [expr [llength $list] - $n]
        while {$i >= 0} {
                lappend res {*}[lrange $list $i [expr $i+$n-1]]
                incr i -$n
        }
        set res
}

#
# set standard environment variables
#
proc _pmodules_setenv { PREFIX name version } {
	#
	# Hack for supporting legacy modules
	if { "${::group}" == "Legacy" } {
		debug "this is a legacy module..."
		return
	}
	if { ![file isdirectory "$PREFIX"] } {
	    debug "$PREFIX is not a directory"
	    return
	}
	if { ! [info exist ::dont-setenv] } {
		set ::dont-setenv {}
	}

	set		NAME			[string toupper $name]
	regsub -all -- "-" ${NAME} "_" NAME

	set prefix_evars [dict create \
			      "${NAME}_VERSION"			"${version}" \
			      "${NAME}_PREFIX"			"${PREFIX}" \
			      "${NAME}_DIR"			"${PREFIX}" \
			      "${NAME}_HOME"			"${PREFIX}" \
			   ]
	set setenv_dirs  [dict create \
			      "${PREFIX}/include"		"${NAME}_INCLUDE_DIR" \
			      "${PREFIX}/lib"			"${NAME}_LIBRARY_DIR" \
			      "${PREFIX}/lib64"			"${NAME}_LIBRARY_DIR" \
			    ]
	set prepend_dirs [dict create \
			      "${PREFIX}/bin"			{ "PATH" } \
			      "${PREFIX}/sbin"			{ "PATH" } \
			      "${PREFIX}/share/man"		{ "MANPATH" } \
			      "${PREFIX}/include"		{ "C_INCLUDE_PATH" "CPLUS_INCLUDE_PATH" } \
			      "${PREFIX}/lib"			{ "LIBRARY_PATH" "LD_LIBRARY_PATH"} \
			      "${PREFIX}/lib64"			{ "LIBRARY_PATH" "LD_LIBRARY_PATH"} \
			      "${PREFIX}/lib/pkgconfig"		{ "PKG_CONFIG_PATH" } \
			      "${PREFIX}/share/pkgconfig"	{ "PKG_CONFIG_PATH" } \
			      "${PREFIX}/lib/cmake"		{ "CMAKE_MODULE_PATH" } \
			      "${PREFIX}/share/cmake"		{ "CMAKE_MODULE_PATH" } \
			      "${PREFIX}/share/${name}/cmake"	{ "CMAKE_MODULE_PATH" } \
			     ]

	dict for {key value} $prefix_evars {
		if { [lsearch ${::dont-setenv} $key] >= 0 } {
			continue
		}
		setenv $key $value
	}
	dict for {key value} $setenv_dirs {
		if { [lsearch ${::dont-setenv} $value] >= 0 || ![file isdirectory $key] } {
			continue
		}
		setenv $value $key
	}
	dict for {key value} $prepend_dirs {
		if { ![file isdirectory $key] } {
			continue
		}
		foreach var $value {
			if { [lsearch ${::dont-setenv} $var] >= 0 } {
				continue
			}
			prepend-path $var $key
		}
	}
}

proc module-url { url } {
	set ::g_url ${url}
}

proc module-license { license } {
	set ::g_license ${license}
}

proc module-maintainer { maintainer } {
	set ::g_maintainer ${maintainer}
}

proc module-help { help } {
	set ::g_help ${help}
}

proc ModulesHelp { } {
	if { [info exists ::whatis] } {
		puts stderr "${::whatis}"
	} else {
		module whatis ModulesCurrentModulefile
	}
	if { [info exists ::version] } {
		puts stderr "Version:    ${::version}"
	} else {
		module whatis
	}
	if { [info exists ::g_url] } {
		puts stderr "Homepage:   ${::g_url}"
	}
	if { [info exists ::g_license] } {
		puts stderr "License:    ${::g_license}"
	}
	if { [info exists ::g_maintainer] } {
		puts stderr "Maintainer: ${::g_maintainer}"
	}
	if { [info exists ::g_help] } {
		puts stderr "${::g_help}\n"
	}
}

#
# intialize global vars
# Modulefile is something like
#
#   <root_dir>/group/modulefiles/name/version
# or
#   <root_dir>/group/modulefiles/X1/Y1/name/version
# or
#   <root_dir>/group/modulefiles/X1/Y1//X2/Y2/name/version
#
proc _find_overlay { modulefile } {
        debug "_find_overlay(${modulefile})"
        foreach ol $::UsedOverlays  {
                debug "ol = $ol"
		set ol_modulefiles_root $::OverlayInfo(${ol}:modulefiles_root)
		debug "ol_modulefiles_root: ${ol_modulefiles_root}"
		if { [string match "$ol_modulefiles_root/*" $modulefile] } {
			return "$ol"
		}
	}
        debug "overlay not found"
        return {}
}

proc _pmodules_init_global_vars { } {
	debug "_pmodules_init_global_vars() called"
	global  GROUP
	global	P		# name of module (without version)
	global	V		# full version of module 
	global	V_MAJOR
	global	V_MINOR
	global	V_PATCHLVL
	global	V_RELEASE
	global	V_PKG		# version without release no. and/or suffix
	global	PREFIX		# prefix of package

	set current_modulefile [file split $::ModulesCurrentModulefile]

	set P [lindex $current_modulefile end-1]
	set V [lindex $current_modulefile end]
	set suffixes [lassign [split $V _] v]
	lassign [split $v -]	V_PKG V_RELEASE
	lassign [split $V_PKG .] V_MAJOR V_MINOR V_PATCHLVL

	set ol [_find_overlay $::ModulesCurrentModulefile]
	if { $::OverlayInfo(${ol}:layout) == "Pmodules" } {
		set modulefiles_root [file split $::OverlayInfo(${ol}:modulefiles_root)]
		set rel_modulefile [lrange $current_modulefile [llength $modulefiles_root] end]
		debug "modulefiles_root: ${modulefiles_root}"
		debug "rel_modulefile: ${rel_modulefile}"
		set GROUP [lindex $rel_modulefile 0]
		set install_prefix [file split $::OverlayInfo(${ol}:install_root)]
		set ::variant [lrange $rel_modulefile 2 end]
		set prefix "$install_prefix $GROUP [lreverse_n $::variant 2]"
		set PREFIX [file join {*}$prefix]
	} else {
		set GROUP "None"
		set ::variant {}
		set PREFIX $::OverlayInfo(${ol}:install_root)
	}

	# :FIXME: the following vars are still used
	set ::name $P
	set ::version $V
	set ::group $GROUP

	debug	"ol=$ol"
	debug	"PREFIX=$PREFIX"
	debug	"group of module $P: $GROUP"
}

if { [info exists ::whatis] } {
	module-whatis	"$whatis"
}

debug "init"
_pmodules_parse_pmodules_env
if {[_find_overlay $::ModulesCurrentModulefile] != ""} {
	debug "setup env vars for module in overlay"
	_pmodules_init_global_vars 
	conflict	$name
    	_pmodules_setenv ${PREFIX} ${name} ${version}
	_pmodules_update_loaded_modules ${group} ${name} ${version}
}
debug "return from lib"

# Local Variables:
# tcl-indent-level: 8
# End:
