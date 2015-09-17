#!/usr/bin/env bash

# Hardcoded path to dialog software
DIALOG_CMD=$PMODULES_HOME/bin/dialog

declare -a modlist      # module info
declare -A selected     # module info indices selected
declare -a depcnt       # dependency reference counter by module info index
declare -A uidmap       # unique module id to module info index
declare -A modmap       # map module names to module info indices for modlist
declare -A fdmap        # module name to family definition mapping
declare -A fmmap        # module name to family member mapping
declare -a relmap       # module info index to release mapping
declare tempfile        # temporary dialog results

set_difference() {  #  $1 \ $2
    local -a operand1=($1)
    local -a operand2=($2)
    local -A members
    local -i elem
    for elem in "${operand1[@]}"; do
        members[$elem]=1
    done
    for elem in "${operand2[@]}"; do
        unset members[$elem]
    done
    echo ${!members[@]}
}

set_merge() {  # $1 U $2  (where $1 and $2 are disjoint)
    if [[ -z "$1" ]]; then
        echo "$2"
    elif [[ -z "$2" ]]; then
        echo "$1"
    else
        echo "$1 $2"
    fi
}

set_union() { # $1 U $2 (sorted)
    local -a operand1=($1)
    local -a operand2=($2)
    local -A members
    local -i elem
    for elem in ${operand1[@]} ${operand2[@]}; do
        members[$elem]=1
    done
    { IFS=$'\n'; echo "${!members[*]}"; } | sort -n
}

# unique id for a module
unique_id() { # $1: module info index
    local -a minfo=( ${modlist[$1]} )
    if (( ${#minfo[@]} < 4 )); then
        echo ${minfo[0]}
    else
        echo "${minfo[@]:3} ${minfo[0]}"
    fi
}

mod_path() {   # $1: module info index
    local -i i
    local -a m=(${modlist[$1]})
    local res="$PMODULES_ROOT/${fmmap[${m[0]%%/*}]}/${m[0]}"
    for (( i=${#m[@]}; i>3; i-- )); do
        res+="/${m[i-1]}"
    done
    echo "$res"
}

calc_deps() {  # $1: module info index
    local dpath="$(mod_path $1)/.dependencies"
    [[ ! -r "$dpath" ]] && return
    local -a d=( $(< "$dpath") ) # dependencies as versioned module names
    local -A p     # map family to versioned module name
    local -A did   # map dependency (versioned module name) to unique module id
    local -a deps  # set of module info indices
    local m n f
    for m in ${d[@]}; do
        n=${m%%/*}
        f=${fdmap[$n]}
        [[ -n "$f" ]] && { p[$f]=$m; }
        f=${fmmap[$n]}
        if [[ -z "$f" ]]; then
            did[$m]=$m
        else
            n=${p[$f]}
            if [[ -z "$n" ]]; then
                did[$m]=$m
            else
                did[$m]="${did[$n]} $m"
            fi
        fi
        deps+=( ${uidmap["${did[$m]}"]} )
    done
    echo "${deps[@]}"
}

update_deps() { # $1: 1-add dependency, -1-remove dependency   $2: set of module info indices
    [[ -z "$2" ]] && return
    local -a q=($2)     # work queue
    local deps=""       # set of dependencies
    local -i m
    while (( ${#q[@]} > 0 )); do
        m=${q[-1]}
        unset q[-1]
        d="$(calc_deps $m)"
        [[ -z "$d" ]] && continue
        d="$(set_difference "$d" "$deps")"
        [[ -z "$d" ]] && continue
        q+=($d)
        deps="$(set_merge "$d" "$deps")"
    done
    for m in $deps; do
        let depcnt[m]+=$1
    done
}

# "$1": source module environment
find_modules() {
    # construct modlist/modmap/uidmap/depcnt/fmmap/relmap arrays from module search output
    local -a mc         # module info components
    local -i i=0
    local current=""
    local name m uid
    while read m; do
        mc=($m)
        [[ "${mc[2]}" == "Legacy" ]] && continue    # filter out legacy stuff
        name=${mc[0]%%/*}
        if [[ "$current" != "$name" ]]; then
            modmap[$name]="$i"
            current=$name
        else
            modmap[$name]+=" $i"
        fi
        modlist[i]=$m
        uid="$(unique_id $i)"
        uidmap["$uid"]=$i
        depcnt[i]=0
        [[ -z ${fmmap[$name]} ]] && { fmmap[$name]=${mc[2]}; }
        relmap[i]=${mc[1]}
        i+=1
    done < <(${PMODULES_HOME}/bin/modulecmd bash search --src="$1" --no-header -a 2>&1)
}

# "$1": source module environment
find_families() {
    # construct fdmap
    local -a t  # tcl file components
    local l s n
    while read l; do
        s=${l%%:*}
        s=${s%/*}
        n=${s##*/}
        if [[ -z "${fdmap[$n]}" ]]; then
            t=( ${l##*:} )
            fdmap[$n]=${t[-1]//\"}
        fi
    done < <(grep -R set-family "$1/*/${PMODULES_MODULEFILES_DIR}")
}

select_uid() { # $1: module uid
    local -a uidc=($1) # uid components
    local name=${uidc[-1]%%/*} # module name
    local midx=${uidmap["$1"]} # module info index
    [[ -z "$midx" ]] && return
    selected[$name]="$(set_union "${selected[$name]}" "$midx")"
    update_deps 1 "$midx"
}

preselect() { # "$1": prefix for preselected modules
    # module paths must not contain white space
    [[ -z "$1" ]] && return
    local -a mpc # module path components
    local -i i
    local uid n
    pushd "$1/$PMODULES_MODULEFILES_DIR" > /dev/null || exit 1;
    trap "popd" EXIT

    for m in $(find . -follow -type f); do
        n=${m##*/}
        [[ "${n:0:1}" == "." ]] && continue
        uid=""
        mpc=( ${m//\// } )
        for ((i=2; i<${#mpc[@]}-2; i+=2)); do
            uid+="${mpc[i]}/${mpc[i+1]} "
        done
        uid+="${mpc[-2]}/${mpc[-1]}"
        PMODULES_ROOT="$1" select_uid "$uid"
    done

    popd
    trap - EXIT
}

is_dependency() { # $1: module name
    local -a map=(${modmap[$1]})
    local -i m
    for ((m=0; m<${#map[@]}; m++)); do
        (( ${depcnt[${map[m]}]} > 0 )) && return 0
    done
    return 1
}

dialog_1() {
    local -a input
    local marker
    local m
    for m in $(IFS=$'\n'; echo "${!modmap[*]}" | sort); do
        marker=""
        [[ -n ${selected[$m]} ]] && { marker+="*"; }
        is_dependency $m && { marker+="+"; }
        input+=($m "$marker$m")
    done

    $DIALOG_CMD --ok-label 'Select' \
	--extra-button --extra-label 'Exit' \
	--no-tags \
	--menu Modules 50 80 50  "${input[@]}" 2>$tempfile
    return $?
}

module_id() { # $@: module info components
    echo "$1 ${@:4}"
}

module_release() { # $@: module info components
    echo "$2"
}

dialog_2() {   # $1: module name
    local -a map=(${modmap[$1]})
    local -a sel=(${selected[$1]})
    local -i j          # mapping index
    local -i k=0        # selection index
    local -a input
    local marker minfo rel m s
    for (( j=0; j!=${#map[@]}; j++ )); do
        minfo=${modlist[${map[j]}]}
        m="$(module_id $minfo)"
        rel=" ($(module_release $minfo))"
        [[ $rel = " (stable)" ]] && { rel=""; }
        [[ "${map[j]}" = "${sel[k]}" ]] && { s="on"; k+=1; } || { s="off"; }
        (( ${depcnt[${map[j]}]} > 0 )) && { marker="+"; l+=1; } || { marker=""; }
        input+=( ${map[j]} "$marker$m$rel" $s )
    done

    $DIALOG_CMD --extra-button --extra-label 'Clear' --no-tags --checklist Versions 80 90 80 "${input[@]}" 2>$tempfile
    return $?
}

# final dialog output
module_out() { # $1: module info index
    local -a args=(${modlist[$1]})
    echo "${args[@]}"
}

# "$1": prefix for preselected modules (destination module environment)
# "$2": prefix for selectable modules (source module environment)
module_picker() {
    find_families "$2"
    find_modules "$2"
    preselect "$1"

    tempfile=$(mktemp ${TMPDIR:-/tmp}/msyncXXXXXX) || {
        echo "Unable to create temporary file!"
        exit 1
    }
    trap "rm -f $tempfile" EXIT

    local -i level=1
    local -i operation=0      # 0: OK, 1: Cancel
    local oldsel
    local sel
    local m
    while (( level != 0 )); do
        case $level in
            1)
                dialog_1
                res=$?
                case $res in
                    0)  #OK
                        sel=$(< $tempfile)
                        level=2
                        ;;
                    1)  #Cancel
                        operation=1
                        level=0
                        ;;
                    3|255) #ESC/Exit = Commit
                        for m in ${selected[@]}; do
                            depcnt[m]=1
                        done
                        for ((m=0; m<${#depcnt[@]}; m++)); do
                            (( ${depcnt[m]} > 0 )) && module_out $m >&2
                        done
                        level=0
                        ;;
                    *)
                        echo "Unknown return value from dialog_1: $res"
                        exit 1
                        ;;
                esac
                ;;
            2)
                dialog_2 $sel
                res=$?
                case $res in
                    0)  #OK
                        oldsel=${selected[$sel]}        # old selection
                        selected[$sel]=$(< $tempfile)   # new selection
                        PMODULES_ROOT="$2" update_deps -1 "$(set_difference "$oldsel" "${selected[$sel]}")" # remove dependencies
                        PMODULES_ROOT="$2" update_deps 1 "$(set_difference "${selected[$sel]}" "$oldsel")"  # add dependencies
                        level=1
                        ;;
                    1|255)  #ESC/Cancel
                        level=1
                        ;;
                    3) #Clear
                        oldsel=${selected[$sel]}  # old selection
                        selected[$sel]=""         # new selection
                        update_deps -1 "$oldsel"  # remove dependencies
                        level=1
                        ;;
                    *)
                        echo "Unknown return value from dialog_2: $res"
                        exit 1
                        ;;
                esac
                ;;
            *)
                echo "Unknown level: $level"
                exit 1
                ;;
        esac
    done

    rm -f $tempfile
    trap - EXIT

    return $operation
}

# if DIALOG_LIB is NOT set, call module picker
[[ ${DIALOG_LIB:+"is_lib"} == "is_lib" ]] || {
    if [[ -x ${PMODULES_HOME}/bin/modulecmd ]]; then
        module_picker "${1:-$PMODULES_ROOT}" "${2:-/afs/psi.ch/sys/psi.x86_64_slp6}"
        exit $?
    else
        echo "ERROR: module environment configuration: ${PMODULES_HOME}/bin/modulecmd is not an executable!"
        exit 1
    fi
}
