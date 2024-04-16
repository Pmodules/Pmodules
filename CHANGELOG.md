# Changelog of Pmodules

## Version 1.1.19
### modulecmd
* arguments to CMake and autotools can now be defined in the
  YAML configuration file. (issue #249, #253)
* Required patches can now be defined in the YAML configuration
  file (issue #249)
* BUGFIX: parsing the version number and setting the variables
  V_MAJOR, V_MINOR, V_PATCHLVL was broken in cases where the
  version number consist of less then three numbers and plus a
  suffix. (issue #248)
* BUGFIX: don't abbreviate out of search if not running in a
  terminal. (issue #250)

### build-system
* Option '--clean-install' added. If this option is set, the 
  module is removed before building, if the module already
  exist. (issue #247)
* The number of directory components to be removed while
  un-taring can now be configured in the YAML configuration
  file. If not specified, 1 is used as default. (issue #252)

## Version 1.1.18
### modulecmd
* BUGFIX: output of load hints fixed
  (issue #241)

### build-system
* BUGFIX: parsing arguments fixed (issue #238)
* BUGFIX: group dependencies specified with the option '--with' were ignored
  (issue #236)
* BUGFIX: writing list of 'systems' to module configuration file fixed
  (issues #235, #243)
* Files in `$PMODULES_TMPDIR/<module>` are now removed before
  and after building a module (except cleanup has been disbaled).
  (issues #242, #245)
* Set prefix and directory/name of modulefile based on group not on
  environment variables like `{COMPILER,MPI,HDF5}_VERSION` (issue #244)

### Toolchain
* update to Tcl 8.6.14 (issue #239)

### General
* link to documentation added to usage/help text (issue #237)

## Version 1.1.17
### build-system
**Fixes**
* usage output reviewed
* compiling in source tree fixed if YAML config file is used

## Version 1.1.16

### modulecmd
**User visible changes**
* YAML module configuration file. Configured in this file are
  * the release stage
  * the list of systems the module is available
  * the list of systems the module shadowed

  Wherby the items in list of systems are either
  * hostnames or glob style patterns of hostnames (e.g. merlin-*)
  * OS names like rhel7
  
  The filename is `.config-<version>` and is located in the same directory as the modulefile.
  For now the `.release-<version>` files are still used if no YAML configuration file exist.

### build-system
**User visible changes**
* YAML build configuration files. For now `variants` files are still supported.

---

## Version 1.1.15

### modulecmd
**User visible changes**
* prevent loading of a module on dedicated systems via blocklist

### build-system
**User visible changes**
* the function to compare versions can now be called with a single
  argument. In this case the given version is compared to version
  of currently build module.

**Internal changes and fixes***
* bugfix: due to a bug in compiling the list of (legacy) config files,
  each module was build twice.

---

## Version 1.1.14

### build-system 
**Internal changes and fixes**
* lookup of default legacy config files fixed

---

## Version 1.1.13

### modulecmd
**User visible changes**
* collections
* shadowing modules with an overlay
* Lmod support
* argument/option handling fixed
* using groups/extending MODULEPATH fixed (module use ...)

**Internal changes and fixes**
* use Lua and Lmod from Pmodules
* std::upvar() replaced
* Bugfixes
---

## Version 1.1.12

### modulecmd
**User visible changes**
* experimental support for Lmod
* support for use flags has been removed.
  (A postfix like '_slurm' can still be used)

---

## Version 1.1.11

### modulecmd
**User visible changes**
* Improved error handling and messages
* Python support added

**Internal changes and fixes**
* Bugfixes

### build-system
**User visible changes**
* building with legacy variants files fixed.
* building with YAML config files is still experimental
  and not recommended for now

---

## Version 1.1.10 

### modulecmd
**User visible changes**
* New options for `module search`.
  * With the option `--group` the search can be restricted to a
    group.
  * With the option `--newest` only the newest versions are
    displayed.
* `find` as alias for the sub-command `search` added.
* Bugfix: the sub-commands `whatis` and `keyword|apropos` were
  broken by design. 
* Bugfix: after loading a `Pmodules` module, it was not shown with
  `module list`.
* Bugfix in scanning the depth of groups.
* Bugfix: after `module purge` the environment variable
  `PMODULES_HOME` was not defined an more.
* Bugfix: source the shell init file only if a `Pmodules` module
  is loaded.
* Bugfix: unsetting aliases in modulefiles was not handled
  properly in `module purge`

**Internal changes and fixes**
* initialisation error for bash and zsh fixed

### build-system
**User visible changes**
* `modbuild` is now defined as function like `module`. Therefor no
  `Pmodules` module must be loaded to build a module with `modbuild`
* The system can now be defined in the module (YAML) configuration
  file.
* Build dependencies can (and should) now be specified with
  `build_requires` in the YAML configuration file.
* Bugfix: cleanup of modulefiles in overlays fixed. A module can be in
  more than one overlay. These overlays must be specified in the
  module configuration file. 
* Bugfix: querying dependencies from YAML configuration file
  fixed. Under some conditions the string 'null' was in the list
  of dependencies.
* Bugfix: create group directory if it doesn't exist.
* Bugfix: create the module `$PREFIX` before processing the
  install targets not before all targets. If `$PREFIX` is created
  before processing any target and the build fails, `modbuild`
  assumes that the module have been already built successfully.

**Internal changes and fixes**
* code review/re-factoring
* `modbuild` is now using the Bash installed in `Pmodules` itself.
* test code with `set -o nounset`, several issues with this
  setting fixed (not necessarily bugs).

**other changes**
* The build script to bootstrap Pmodules itself doesn't use modbuild
  any more to compile required software packages.  With this change
  we can remove some special cases from modbuild.
* The bootstrap script requires Bash 5.0 or newer now.
* Bugfix: in the `Pmodules` modulefile force the sourcing of the
  shell init script while in mode `load` only.

---

## Version 1.1.9

### modulecmd
**User visible changes**
* Overlay info added to output of sub-command `search`.
* Output of `module search --verbose` revised for better readability.

**Internal changes and fixes**
* The shell`s init file is sourced, when Pmodules is loaded as module.
  This is required if there are changes in the module function or too
  define new shell functions.
* A bug in `libmodules.tcl:module-addgroup()` which crashed 
  `module load ...` has been fixed.
* In versions before 1.1.9 a colon at the beginning or end of `MODULEPATH`
  crashed the module function. This has been fixed. 

### build-system
**User visible changes**
* The command `modbuild` is now defined as shell function analog to
  the `module` command. The main reason to introduce this function
  is due to the fact that Bash version 5 or newer is now required
  by `modbuild`. The function `modbuild` load Bash 5.x as module
  before calling the modbuild-script. If you want to use the script
  directly, a Bash binary with version 5.x must be in PATH.
* If a build-script is in the current working directory,
  `modbuild` can now be called without specifying the build-script.
* In case of an error in a build-step the build process did not 
  abort as it should. This has been fixed.
* The option `--overlay` can now be used
  - to define an overlay if legacy variants files are used
  - to override the overlay in a YAML variants file.
* The new keyword `with` has been introduced in YAML variants file
  to specified hierarchical dependencies.
* The function `pbuild::supported_os` has been
  removed. `pbuild::supported_systems` provides the same
  functionality for legacy configuration files. In YAML module
  configuration files `systems` have to be used.

**Internal changes and fixes**
* bugfix in setting `PATH`
* requires bash 5 or later

---

## Version 1.1.8

### modulecmd
**User visible changes**
* configuration in YAML files
* modulefiles and software must not
  have a common root directory
* the installation root must be specified, it doesn`t default
  to the base 'overlay' any more.
* zsh initialisation fixed.

**Internal changes and fixes**
* std::upvar() replaced with reference variables in part of the 
  code.
* environment variable `PMODULES_ROOT` removed.
* unsetting aliases fixed.
* update to bash 5.1.16
* update to findutils 4.9 (macOS only)
* minor fixes

### build-system
**User visible changes**
* YAML format for variants files
	
**Internal changes and fixes**
* use lib `libpmodules.bash`
* bugfixes

### modmanage
**User visible changes**
* none, support for overlays still missing

**Internal changes and fixes**
* none

---

## Version 1.1.7
### modulecmd
* list of available overlays in subcommand `use` is now better readable

### buid-system
* overlay definition must now be in YAML format
* support for YAML formatted variant files (the legacy format 
  is still supported)
* build-system in 1.1.6 was still work in progress and broken

---

## Version 1.1.6
### modulecmd
* bugfix in searching/loading modules in a hierarchical
  group

---

## Version 1.1.5
### modulecmd
* first public version with the overlay feature

---

## Version 1.0.0rc11
### modulecmd
**User visible changes**
* handling of set-alias in modulefile fixed
---

## Version 1.0.0rc10
### modulecmd
**User visible changes**
* The term "releases" has been replaced with "release stages". 
  The visible changes are the change of the option 
  `--all-releases` to `--all-release-stages`, adapted
  help text and configuration files.
* New configuration file `Pmodules.conf` to configure the 
  default visible group, the default visible release stages
  and the defined releases stages. These information has
  been stripped from the profiles `profiles.{bash,csh,zsh}`.
* module are now sorted numerically in output of
  `module avail`.
* option `-?` added as alias for `--help`.
* new option `--glob` for `module search`. This enables 
  shell glob-pattern searches.
**Internal changes and fixes**
* bugfix in removing temp-file in exit function.
* terse output of `module avail` fixed.
* broken help for sub-commands fixed.
* missing group in output of `module avail` fixed.
* broken output of `module search --print-modulefiles` fixed.
* argument handling fixed after `--`.
* cleanup option/argument handling.

### build-system
**User visible changes**
* none
**Internal changes and fixes**
* bugfixes in the functions `pbuild::version_{le,gt}
* bugfix in recognising newer CentOS versions

### modmanage
**User visible changes**
* complete re-implementation of (broken) modmanage
---

## Version 1.0.0rc9
### modulecmd
**User visible changes**
* a Pmodules module must be the first module loaded
* new option `--group|-g GROUP` to list available modules in `GROUP`
* align columns in output of `module avail`
* remove path to Pmodules bin directory while unloading a Pmodules module
* exclude a Pmodules module from being purged 
* follow sym-links in `ROOT/GROUP/modulefiles`

**Internal changes and fixes**
* use default field separator by unsetting `IFS`
* use read-only variables for all used commands with full path  
* better tmp-file creation/deletion
* more bugfixes

### build-system
**User visible changes***
* group hierarchy can now be defined in a config file

**Internal changes and fixes**
* more bugfixes

---

## Version 1.0.0rc8
### modulecmd
**User visible changes**
* Pmodules can now be loaded as module
* Since `${PMODULES_HOME}/bin` has been removed from `PATH` in `1.0.0rc7` a Pmodules
  module must be loaded to make the build system available.

**Internal changes and fixes**
* use system binaries in `/bin:/usr/bin` if possible
---

## Version 1.0.0rc7
### modulecmd
**User visible changes**
* add options to `module search` to show dependencies

**Internal changes and fixes**
* hardcoded path in `profile.csh`fixed
* bugfixes
* Update to BASH 5.1
* Update to Tcl 8.6.10

### build-system
**User visible changes**
* building deprecated modules must be forced
* support for versioned modulefiles in build-blocks: if a modulefile 
  `modulefile-X[.Y[.Z]]` exists in the build-block it will be taken
  in favour of `modulefile`-
* bootstrap/build script reviewed, `--config` option removed, help for all  
  sub-commands added

**Internal changes and fixes**
* installation of fallback shared libraries fixed.
* bugfixes

### modmanage
**User visible changes**
* Support of run-time dependencies which are required but must not be loaded
---

## Version 1.0.0rc6
### modulecmd
- Support for shell `sh` added (#86, #90).
- Broken 'module load'  with (T)CSH fixed (#88).
- prepend instead of append Pmodules bin directory to `PATH` (#87).

### build-system
- Support added for a wildcard (`.*`) version as argument to `modbuild` (#78)
- Handle empty list of be installed shared libraries fixed (#89).

### Building and installing Pmodules
- Bugs in bootstrapping Pmodules fixed (#82)
---

## Version 1.0.0rc5 (since 1.0.0rc2)
### modulecmd
- log `module load` commands to system logger (#80)
- Bugs fixed in printing load hints (#48, #49)
- `--with` option of sub-command search now accepts a comma separated list of strings
- `PMODULES_ENV` is exported only on content changes
- more bugfixes

### build-system
- The argument passed with the option `--system` is not any more a synonym for
  the kernel of the system (like Linux, Darwin). It now defines a target operating
  system like RHEL6, macOS1014 etc (#72).
- calling `pbuild::make_all` in a build-script is now deprecate
- bugfixes
---

## 1.0.0rc4
- never tagged
---

## 1.0.0rc3
- never tagged
