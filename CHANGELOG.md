# Changelog of Pmodules

## Version 1.0.0rc10
* **modulecmd**
  * *User visible changes*
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
  * *Internal changes and fixes*
    * bugfix in removing temp-file in exit function.
    * terse output of `module avail` fixed.
    * broken help for sub-commands fixed.
    * missing group in output of `module avail` fixed.
    * broken output of `module search --print-modulefiles` fixed.
    * argument handling fixed after `--`.
    * cleanup option/argument handling.
* **build-system**
  * *User visible changes*
    * none
  * *Internal changes and fixes*
    * bugfixes in the functions `pbuild::version_{le,gt}
    * bugfix in recognising newer CentOS versions
* **modmanage**
  * *User visible changes*
    * complete re-implementation of (broken) modmanage

## Version 1.0.0rc9
* **modulecmd**
  * *User visible changes*
    * a Pmodules module must be the first module loaded
    * new option `--group|-g GROUP` to list available modules in `GROUP`
    * align columns in output of `module avail`
    * remove path to Pmodules bin directory while unloading a Pmodules module
    * exclude a Pmodules module from being purged 
    * follow sym-links in `ROOT/GROUP/modulefiles`
  * *Internal changes and fixes*
    * use default field separator by unsetting `IFS`
    * use read-only variables for all used commands with full path  
    * better tmp-file creation/deletion
    * more bugfixes
* **build-system**
  * *User visible changes*
    * group hierarchy can now be defined in a config file
  * *Internal changes and fixes*
    * more bugfixes

## Version 1.0.0rc8
* **modulecmd**
  * *User visible changes*
    * Pmodules can now be loaded as module
    * Since `${PMODULES_HOME}/bin` has been removed from `PATH` in `1.0.0rc7` a Pmodules
      module must be loaded to make the build system available.
  * *Internal changes and fixes*
    * use system binaries in `/bin:/usr/bin` if possible

## Version 1.0.0rc7

* **modulecmd**
  * *User visible changes*
    * add options to `module search` to show dependencies
  * *Internal changes and fixes*
    * hardcoded path in `profile.csh`fixed
    * bugfixes
    * Update to BASH 5.1
    * Update to Tcl 8.6.10
* **build-system**
  * *User visible changes*
    * building deprecated modules must be forced
    * support for versioned modulefiles in build-blocks: if a modulefile 
      `modulefile-X[.Y[.Z]]` exists in the build-block it will be taken
      in favour of `modulefile`-
    * bootstrap/build script reviewed, `--config` option removed, help for all  
      sub-commands added
  * *Internal changes and fixes*
    * installation of fallback shared libraries fixed.
    * bugfixes
* **modmanage**
  * *User visible changes*
    * Support of run-time dependencies which are required but must not be loaded

## Version 1.0.0rc6

**Added features:**

- Support for shell `sh` added (#86, #90).
- Support added for a wildcard (`.*`) version as argument to `modbuild` (#78)

**Fixed bugs:**

- Handle empty list of be installed shared libraries fixed (#89).
- Broken 'module load'  with (T)CSH fixed (#88).
- prepend instead of append Pmodules bin directory to `PATH` (#87).
- Bugs in bootstrapping Pmodules fixed (#82)


## Version 1.0.0rc5 (since 1.0.0rc2)

**Added features:**

- log `module load` commands to system logger (#80)


**Changed:**

- The argument passed with the `--system` is not any more a synonym for kernel of the system a build process is running on. It now defines a target operating system like RHEL6, macOS1014 etc (#72).


**Deprecated:**

- calling `pbuild::make_all` in a build-script is now deprecate

**Fixed bugs:**

- Bugs fixed in printing load hints (#48, #49)
- Several bugs in build-systen and `modulecmd` fixed.
- `--with` option of sub-command search now accepts a comma separated list of strings
- `PMODULES_ENV` is exported only on content changes


## 1.0.0rc4
  - never tagged
  
## 1.0.0rc3
  - never tagged
