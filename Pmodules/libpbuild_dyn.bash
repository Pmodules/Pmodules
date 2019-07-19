#!/bin/bash

eval "pbuild::pre_prep_${system}() { :; }"
eval "pbuild::pre_prep_${OS}() { :; }"
eval "pbuild::post_prep_${system}() { :; }"
eval "pbuild::post_prep_${OS}() { :; }"

eval "pbuild::add_patch_${system}() { pbuild::add_patch \"\$@\"; }"
eval "pbuild::add_patch_${OD}() { pbuild::add_patch \"\$@\"; }"

eval "pbuild::pre_configure_${system}() { :; }"
eval "pbuild::pre_configure_${OS}() { :; }"
eval "pbuild::post_configure_${system}() { :; }"
eval "pbuild::post_configure_${OS}() { :; }"

eval "pbuild::pre_compile_${system}() { :; }"
eval "pbuild::pre_compile_${OS}() { :; }"
eval "pbuild::post_compile_${system}() { :; }"
eval "pbuild::post_compile_${OS}() { :; }"

eval "pbuild::pre_install_${system}() { :; }"
eval "pbuild::pre_install_${OS}() { :; }"
eval "pbuild::post_install_${system}() { :; }"
eval "pbuild::post_install_${OS}() { :; }"
