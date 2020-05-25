# Changelog of Pmodules

## Unreleased

**Added features:**

**Changed:**

**Deprecated:**

**Removed:**

**Fixed bugs:**


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
