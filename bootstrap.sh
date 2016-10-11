#!/bin/bash
declare -r BASE_DIR=$(cd "$(dirname $0)" && pwd)

${BASE_DIR}/compile_pmodules.sh
${BASE_DIR}/install_pmodules.sh

