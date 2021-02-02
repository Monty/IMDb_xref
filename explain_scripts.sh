#!/usr/bin/env bash
#
# Explain any shell scripts in this directory
#
# USAGE:
#   ./explain_scripts.sh
#
# NOTES:
#   Runs the 'help' function in any *.sh files that have one

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

for script in $(ls *.sh); do
    if [ "$(grep -cF 'help()' $script)" -ne 0 ]; then
        [ $script == "explain_scripts.sh" ] && continue
        clear
        eval ./$script -h
        waitUntil -k
    fi
done

# clear
# printf "The functions directory contains scripts useful for developers.\n"
if waitUntil $ynPref -cN \
    "The functions directory contains developer scripts. Would you like see them now?"; then
    eval functions/explain_functions.sh
fi
