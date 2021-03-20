#!/usr/bin/env bash
#
# Print the instances of any "word" in downloaded IMDb data files

# This can produce a lot of output. To see how many lines, run
# ./countIMDbInstances.sh first.

# INVOCATION:
#    ./listIMDbInstances.sh nm1524628 tt5123128
#    ./listIMDbInstances.sh Catarella

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

# Make sure prerequisites are satisfied
ensurePrerequisites

for srchString in "$@"; do
    for file in *.tsv.gz; do
        [[ -e $file ]] || break # handle the case of no files
        printf "==> in $file\n"
        rg -wNz "$srchString" "$file"
        printf "\n"
    done
    printf "\n"
done
