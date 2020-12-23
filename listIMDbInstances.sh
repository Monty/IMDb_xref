#!/usr/bin/env bash
# Print the instances of any "word" in downloaded IMDb data files

# This can produce a lot of output. To see how many lines, run ./countIMDbInstances.sh first.

# INVOCATION:
#    ./listIMDbInstances.sh nm1524628 tt5123128
#    ./listIMDbInstances.sh Catarella

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd $DIRNAME
export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

for srchString in "$@"; do
    for file in $(ls *.tsv.gz); do
        printf "==> $file\n"
        rg -wNz "$srchString" $file
        printf "\n"
    done
    printf "\n"
done
