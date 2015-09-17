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

proc module-addgroup { group } {
	global env
	global name
	global version

	debug $group
	set Implementation [file join {*}$::implementation]

	set	GROUP [string toupper $group]
	regsub -- "-" ${GROUP} "_" GROUP
	setenv	${GROUP}		$name
	setenv	${GROUP}_VERSION	$version

	set	::${group}		$name
	set	::${group}_version	$version

	if { [module-info mode load] } {
		debug "mode is load"

		append-path MODULEPATH $::PmodulesRoot/$group/$::PmodulesModulfilesDir/$Implementation
		append-path PMODULES_USED_GROUPS $group
		debug "mode=load: new MODULEPATH=$env(MODULEPATH)"
		debug "mode=load: new PMODULES_USED_GROUPS=$env(PMODULES_USED_GROUPS)"
	} elseif { [module-info mode remove] } {
		# remove orphan modules
		debug "remove orphan modules"
		set GROUP [string toupper $group]
		if { [info exists env(PMODULES_LOADED_${GROUP})] } {
			set modules [split $env(PMODULES_LOADED_${GROUP}) ":"]
			foreach m ${modules} {
				if { ${m} == "--APPMARKER--" } {
					continue
				}
				if { [is-loaded ${module_name}] } {
					debug "unloading module: $m"
					module unload ${m}
				}
			}
		}
		remove-path MODULEPATH $::PmodulesRoot/$group/$::PmodulesModulfilesDir/$Implementation
		remove-path PMODULES_USED_GROUPS $group
		debug "mode=remove: $env(MODULEPATH)"
		debug "mode=remove: $env(PMODULES_USED_GROUPS)"
	}
	if { [module-info mode switch2] } {
		debug "mode=switch2"
		append-path MODULEPATH $::PmodulesRoot/$group/$::PmodulesModulfilesDir/[module-info name]
		append-path PMODULES_USED_GROUPS ${group}
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

#
# load dependencies, but do *not* unload dependencies
#
proc _pmodules_load_dependencies { fname } {
	if { ! [ file exists ${fname} ] } {
		return
	}
	if { ! [module-info mode load] } {
		return
	}
	debug "load dependencies from: ${fname}"
	#  Slurp up the data file
	set fp [open ${fname} r]
	set file_data [read ${fp}]
	close ${fp}
	set data [split ${file_data} "\n"]
	foreach line ${data} {
		debug "MODULEPATH=$::env(MODULEPATH)"
		set module_name [string trim $line]
		if { ${module_name} == "#" || ${module_name} == "" } {
			continue
		}
		if { [is-loaded ${module_name}] } {
			debug "module already loaded: ${module_name}"
			continue
		}
		debug "module load: ${module_name}"
		module load ${module_name}
     }
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

	set		NAME			[string toupper $name]
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

proc module-url { _url } {
	set ::url ${_url}
}

proc module-license { _license } {
	set ::license ${_license}
}

proc module-maintainer { _maintainer } {
	set ::maintainer ${_maintainer}
}

proc module-help { _help } {
	set ::help ${_help}
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
	if { [info exists ::url] } {
		puts stderr "Homepage:   ${::url}"
	}
	if { [info exists ::license] } {
		puts stderr "License:    ${::license}"
	}
	if { [info exists ::maintainer] } {
		puts stderr "Maintainer: ${::maintainer}"
	}
	if { [info exists ::help] } {
		puts stderr "${::help}\n"
	}
}

#
# intialize global vars
# Modulefile is something like
#
#   ${PMODULES_ROOT}/group/${PMODULES_MODULEFILES_DIR}/name/version
# or
#   ${PMODULES_ROOT}/group/${PMODULES_MODULEFILES_DIR}/X1/Y1/name/version
# or
#   ${PMODULES_ROOT}/group/${PMODULES_MODULEFILES_DIR}/X1/Y1//X2/Y2/name/version
#
proc _pmodules_init_global_vars { } {
	global	group
	global  name
	global  version
	global	implementation
	global	PREFIX		# prefix of package

	debug	"$::ModulesCurrentModulefile"
	set	::PmodulesRoot		$::env(PMODULES_ROOT)
	set	::PmodulesModulfilesDir	$::env(PMODULES_MODULEFILES_DIR)
	set	modulefile		[file split $::ModulesCurrentModulefile]
	set	pmodules_root		[file split $::PmodulesRoot]
	set	pmodules_root_num_dirs	[llength $pmodules_root]

	set	modulefile_root	[file join {*}[lrange $modulefile 0 [expr $pmodules_root_num_dirs - 1]]]
	if { $::PmodulesRoot != $modulefile_root } {
		debug "stop sourcing: ${::PmodulesRoot} != $modulefile_root"
		return
	} 
	debug	"modulefile is inside our root"
	set	rel_modulefile	[lrange $modulefile [llength $pmodules_root] end]
	set	group		[lindex $rel_modulefile 0]
	set	name		[lindex $modulefile end-1]
	set	version		[lindex $modulefile end]
	set	implementation	[lrange $rel_modulefile 2 end]
	set	prefix		"$pmodules_root $group [lreverse_n $implementation 2]"
	set	PREFIX		[file join {*}$prefix]

	debug "PREFIX=$PREFIX"
	debug "group of module $name: $group"
}

proc _pmodules_output_message { fname } {
	if { [ file exists "${fname}" ] } {
		set fp [open "${fname}" r]
		set info_text [read $fp]
		close $fp
		puts stderr ${info_text}
	}
}

if { [info exists ::whatis] } {
	module-whatis	"$whatis"
}

_pmodules_init_global_vars 

#
# we cannot load another module with the same name
#
conflict	$name

if { [module-info mode load] } {
	debug "${name}/${version}: loading ... "
	_pmodules_output_message "${PREFIX}/.info"
	_pmodules_load_dependencies "${PREFIX}/.dependencies"
}

_pmodules_setenv ${PREFIX} ${name} ${version}
_pmodules_update_loaded_modules ${group} ${name} ${version}

debug "return from lib"
