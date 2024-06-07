#!/usr/bin/env bash
# Count the instances of any "word" in downloaded IMDb data files

# INVOCATION:
#    ./countIMDbInstances.sh tt5123128 nm1524628
#    ./countIMDbInstances.sh Catarella

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
        count=$(rg -wcz "$srchString" "$file")
        if [[ "$count" == "" ]]; then
            count=0
        fi
        printf "%-10s %5d  %s\n" "$srchString" "$count" "$file"
    done
    printf "\n"
done
