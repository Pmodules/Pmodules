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
			OverlayDict {
				array set ::OverlayDict [regsub -all  {[]=[]} $value " "]
			}
		        OverlayList {
			        array set tmp [regsub -all  {[]=[]} $value " "]
  			        set ::OverlayList {}
				set l [lsort [array names tmp]]
			        foreach k $l {
				        lappend ::OverlayList $tmp($k)
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
		foreach overlay $::OverlayList {
			lappend overlays_to_add $overlay
			debug $overlay
			if { [string compare $::OverlayDict($overlay) $::ol_replacing] == 0 } {
				break
			}
		}
		foreach overlay [lreverse_n $overlays_to_add 1] {
			debug "overlay=$overlay"
			debug "group=$group"
			debug "::variant=$::variant"
			set dir [file join \
				     $overlay \
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
                foreach overlay $::OverlayList {
                        set dir [file join \
                                     $overlay \
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

	set NAME [string toupper $name]
	regsub -- "-" ${NAME} "_" NAME

	if { ! [info exist ::dont-setenv] } {
		set ::dont-setenv {}
	}

	if { ${version} != "" } {
		if { [lsearch ${::dont-setenv} "${NAME}_VERSION"] == -1 } {
			setenv		${NAME}_VERSION		$version
		}
	}

	if { [file isdirectory "$PREFIX"] } {
		if { [lsearch ${::dont-setenv} "${NAME}_PREFIX"] == -1 } {
			setenv		${NAME}_PREFIX		$PREFIX
		}
		if { [lsearch ${::dont-setenv} "${NAME}_DIR"] == -1 } {
			setenv		${NAME}_DIR		$PREFIX
		}
		if { [lsearch ${::dont-setenv} "${NAME}_HOME"] == -1 } {
			setenv		${NAME}_HOME		$PREFIX
		}
	} else {
		debug "$PREFIX is not a directory"
	}

	if { [file isdirectory "$PREFIX/bin"] } {
		if { [lsearch ${::dont-setenv} "PATH"] == -1 } {
			prepend-path	PATH			$PREFIX/bin
		}
	}

	if { [file isdirectory "$PREFIX/sbin"] } {
		if { [lsearch ${::dont-setenv} "PATH"] == -1 } {
			prepend-path	PATH			$PREFIX/sbin
		}
	}

	if { [file isdirectory "$PREFIX/share/man"] } {
		if { [lsearch ${::dont-setenv} "MANPATH"] == -1 } {
			prepend-path	MANPATH			$PREFIX/share/man
		}
	}

	# set various environment variables - as long as they are not blacklisted
	debug "prepend to include paths"
	if { [file isdirectory "$PREFIX/include"] } {
		if { [lsearch ${::dont-setenv} "C_INCLUDE_PATH"] == -1 } {
			prepend-path	C_INCLUDE_PATH		$PREFIX/include
		}
		if { [lsearch ${::dont-setenv} "CPLUS_INCLUDE_PATH"] == -1 } {
			prepend-path	CPLUS_INCLUDE_PATH	$PREFIX/include
		}
		if { [lsearch ${::dont-setenv} "${NAME}_INCLUDE_DIR"] == -1 } {
			setenv		${NAME}_INCLUDE_DIR	$PREFIX/include
		}
	}

	debug "prepend to library paths"
	if { [file isdirectory "$PREFIX/lib"] } {
		if { [lsearch ${::dont-setenv} "LIBRARY_PATH"] == -1 } {
			prepend-path	LIBRARY_PATH		$PREFIX/lib
		}
		if { [lsearch ${::dont-setenv} "LD_LIBRARY_PATH"] == -1 } {
			prepend-path	LD_LIBRARY_PATH		$PREFIX/lib
		}
		if { [lsearch ${::dont-setenv} "${NAME}_LIBRARY_DIR"] == -1 } {
			setenv		${NAME}_LIBRARY_DIR	$PREFIX/lib
		}
	}

	if { [file isdirectory "$PREFIX/lib/pkgconfig"] } {
		if { [lsearch ${::dont-setenv} "PKG_CONFIG_PATH"] == -1 } {
			prepend-path	PKG_CONFIG_PATH		$PREFIX/lib/pkgconfig
		}
	}

	if { [file isdirectory "$PREFIX/lib/cmake"] } {
		if { [lsearch ${::dont-setenv} "CMAKE_MODULE_PATH"] == -1 } {
			prepend-path	CMAKE_MODULE_PATH	$PREFIX/lib/cmake
		}
	}

	debug "prepend to library paths (64bit)"
	if { [file isdirectory "$PREFIX/lib64"] } {
		if { [lsearch ${::dont-setenv} "LIBRARY_PATH"] == -1 } {
			prepend-path	LIBRARY_PATH		$PREFIX/lib64
		}
		if { [lsearch ${::dont-setenv} "LD_LIBRARY_PATH"] == -1 } {
			prepend-path	LD_LIBRARY_PATH		$PREFIX/lib64
		}
		if { [lsearch ${::dont-setenv} "${NAME}_LIBRARY_DIR"] == -1 } {
			setenv		${NAME}_LIBRARY_DIR	$PREFIX/lib64
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
#   ${PMODULES_ROOT}/group/modulefiles/name/version
# or
#   ${PMODULES_ROOT}/group/modulefiles/X1/Y1/name/version
# or
#   ${PMODULES_ROOT}/group/modulefiles/X1/Y1//X2/Y2/name/version
#
proc _find_overlay { modulefile_components } {
        debug "_find_overlay()"
        foreach overlay $::OverlayList  {
                debug "$overlay"
                if { [string range $overlay end end] == "/" } {
                        set overlay [string range $overlay 0 end-1]
                }
                set	overlay_components	[file split $overlay]
                set	overlay_num_components	[llength $overlay_components]
                set	modulefile_root	[file join \
                                             {*}[lrange \
                                                     $modulefile_components \
                                                     0 [expr $overlay_num_components - 1]]]
                if { [string compare $overlay $modulefile_root] == 0 } {
                        return $overlay_components
                }
        }
        debug "not found"
        return {}
}

proc _is_in_overlay { } {
	debug "_is_in_overlay?"
	set parts [_find_overlay [file split $::ModulesCurrentModulefile]]
	expr {[string compare $parts ""] == 0 }
}

proc _pmodules_init_global_vars { } {
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

	set	modulefile_components	[file split $::ModulesCurrentModulefile]

	set     overlay_components [_find_overlay ${modulefile_components}]
	set	rel_modulefile	[lrange $modulefile_components [llength $overlay_components] end]
	set	group		[lindex $rel_modulefile 0]
	set	GROUP		"${group}"
	set	name		[lindex $modulefile_components end-1]
	set	P		"${name}"
	set	version		[lindex $modulefile_components end]
	set 	V		"${version}"
	lassign [split $V -]	V_PKG tmp
	set	V_RELEASE	[lindex [split $tmp _] 0]
	lassign [split $V_PKG .] V_MAJOR V_MINOR V_PATCHLVL
	set	variant 	[lrange $rel_modulefile 2 end]
	set	prefix		"$overlay_components $group [lreverse_n $variant 2]"
	set	PREFIX		[file join {*}$prefix]
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

