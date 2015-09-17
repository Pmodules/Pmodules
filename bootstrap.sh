#!/bin/bash
declare -r BASE_DIR=$(cd "$(dirname $0)/../.." && pwd)
declare -r BOOTSTRAP_DIR="${BASE_DIR}/Bootstrap"

${BOOTSTRAP_DIR}/compile_pmodules.sh
${BOOTSTRAP_DIR}/install_pmodules.sh

