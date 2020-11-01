# Pmodules

Pmodules are a hierarchical module environment based on [Environment Modules](http://modules.sourceforge.net).
For the time being they are still using the C implementation of the Environment Modules.

*Future plans*
* Version 2 will be a re-implementation in Tcl using the modulecmd of Environment Modules.
* Version 3 will be implementat as extension of Environment Modules.

## Install a new Pmodules environment

All Pmodules and all required software is installed in a directory hierarchy 
in one unique root directory. If required or prefered dedicated directories can
be defined for temporary files and/or downloaded files.

In the most cases a Pmodules environment will be installed on a network file-system, 
but local disk is of course also possible. Just make sure you have write access to
to Pmodules root directory. The Pmodules root directory defaults to `/opt/psi`. 

*Installation*
1. clone this repository and cd into it.
2. create the Pmodules root directory and make sure you have write access with
   the user you want to use to setup the new Pmodules environment. In the following 
   steps we use `$PMODULES_ROOT` as symbols for the root directory.
3. Run  
   ```
   ./build configure --prefix=$PMODULES_ROOT
   ```
   to configure a new Pmodules environment. This command creates the configuration 
   file `$PMODULES_ROOT/config/modbuild.conf` and some directories under `$PMODULES_ROOT`
   required in the next steps.
4. Run
   ```
   ./build compile --prefix=$PMODULES_ROOT
   ```
   to compile and install the required tools.
5. Run
   ```
   ./build install --prefix=$PMODULES_ROOT
   ```
   to install the Pmodules scripts.
   
If you don't want to use `$PMODULES_ROOT/var/tmp/${USER}` for temporary files
you can override the default by using the option `--tmpdir=TEMP_DIR` in step 3.

If you don't want to use `$PMODULES_ROOT/var/distfiles` for downloaded files
you can override the default by using the option `--distfilesdir=DISTDIR` in step 3.

## Install a new Pmodules version

TBW