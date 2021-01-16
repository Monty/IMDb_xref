#!/usr/bin/env bash
#
# Explain any files in the function directory named *.function
#
# USAGE:
#   ./explain_functions.sh
#
# NOTES:
#   Runs the 'help' function in any *.function files that have one

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME"/..

export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

for file in $(ls functions/*.function); do
    if [ "$(grep -cF 'help()' $file)" -ne 0 ]; then
        clear
        function="$(basename ${file%\.function})"
        eval $function -h
        printf "\n"
    fi
done
