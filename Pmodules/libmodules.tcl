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

proc _pmodules_parse_pmodules_env { } {
	#
	# In this library we need the value of some BASH variables
	# defined in PMODULES_ENV. In this function we translate
	# these variables definitions - created in BASH with
	# 'typeset -p VAR' - to Tcl.
	#
	foreach line [split [base64::decode $::env(PMODULES_ENV)] "\n"] {
		if { ![regexp -- {.* -[aAx]* (.*)=\((.*)\)} $line -> name value] } {
			continue
		}
		switch $name {
			Dir2OverlayMap {
				array set ::Dir2OverlayMap [regsub -all  {[]=[]} $value " "]
			}
			OverlayInfo {
				array set ::OverlayInfo [regsub -all  {[]=[]} $value " "]
			}
		        UsedOverlays {
			        array set tmp [regsub -all  {[]=[]} $value " "]
  			        set ::UsedOverlays {}
				set l [lsort [array names tmp]]
			        foreach k $l {
				        lappend ::UsedOverlays $tmp($k)
			        }
			}
			UsedGroups {
				set ::UsedGroups $value
			}
		}
	}
}

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
		foreach overlay [lreverse_n $overlays_to_add 1] {
			debug "overlay=$overlay"
			debug "group=$group"
			debug "::variant=$::variant"
			set dir [file join \
				     $::OverlayInfo($overlay:mod_root) \
				     $group \
				     $::MODULEFILES_DIR \
				     {*}$::variant]
		        debug "dir=$dir"
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
				     $::OverlayInfo($overlay:mod_root) \
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
	regsub -- "-" ${NAME} "_" NAME

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
proc _find_overlay { modulefile_components } {
        debug "_find_overlay()"
        foreach ol $::UsedOverlays  {
                debug "$ol"
		set ol_mod_root $::OverlayInfo(${ol}:mod_root)
                if { [string range $ol_mod_root end end] == "/" } {
                        set ol_mod_root [string range $ol_mod_root 0 end-1]
                }
		debug "$ol_mod_root"
                set ol_mod_root_splitted [file split $ol_mod_root]
                set modulefile_root [file join \
					 {*}[lrange \
						 $modulefile_components \
						 0 [expr [llength $ol_mod_root_splitted] - 1]]]
		debug "$modulefile_root"
                if { [string compare $ol_mod_root $modulefile_root] == 0 } {
			debug "$ol_mod_root_splitted"
                        return $ol_mod_root_splitted
                }
        }
        debug "not found"
        return {}
}

proc _is_in_overlay { } {
	debug "_is_in_overlay?"
	set parts [_find_overlay [file split $::ModulesCurrentModulefile]]
	debug "_is_in_overlay: $parts"
	expr {[string compare $parts ""] == 0 }
}

proc _pmodules_init_global_vars { } {
	debug "_pmodules_init_global_vars() called"
	global	group
	global  GROUP
	global  name
	global	P
	global  version
	global	V
	global	V_MAJOR
	global	V_MINOR
	global	V_PATCHLVL
	global	V_RELEASE
	global	V_PKG
	global	variant
	global	PREFIX		# prefix of package

	set	modulefile_splitted	[file split $::ModulesCurrentModulefile]

	set     ol_mod_root_splitted [_find_overlay ${modulefile_splitted}]
	set	rel_modulefile	[lrange $modulefile_splitted [llength $ol_mod_root_splitted] end]
	set	group		[lindex $rel_modulefile 0]
	set	GROUP		"${group}"
	set	name		[lindex $modulefile_splitted end-1]
	set	P		"${name}"
	set	version		[lindex $modulefile_splitted end]
	set 	V		"${version}"
	lassign [split $V -]	V_PKG tmp
	set	V_RELEASE	[lindex [split $tmp _] 0]
	lassign [split $V_PKG .] V_MAJOR V_MINOR V_PATCHLVL
	set	variant 	[lrange $rel_modulefile 2 end]
	set mod_root [file join {*}$ol_mod_root_splitted]
	debug "mod_root=$mod_root"
	set ol $::Dir2OverlayMap($mod_root)
	debug "ol=$ol"
	set install_prefix [file split $::OverlayInfo(${ol}:inst_root)]
	set	prefix		"$install_prefix $group [lreverse_n $variant 2]"
	set	PREFIX		[file join {*}$prefix]
	debug "PREFIX=$PREFIX"
	debug "group of module $name: $group"
}

if { [info exists ::whatis] } {
	module-whatis	"$whatis"
}

_pmodules_parse_pmodules_env
if {[_is_in_overlay] == 0} {
	debug "setup env vars for module in overlay"
	_pmodules_init_global_vars 
	conflict	$name
    	_pmodules_setenv ${PREFIX} ${name} ${version}
	_pmodules_update_loaded_modules ${group} ${name} ${version}
}
debug "return from lib"

