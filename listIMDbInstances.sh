#!/usr/bin/env bash
# Print the instances of any "word" in downloaded IMDb data files

# This can produce a lot of output. To see how many lines, run ./countIMDbInstances.sh first.

# INVOCATION:
#    ./listIMDbInstances.sh nm1524628 tt5123128
#    ./listIMDbInstances.sh Catarella

for srchString in "$@"; do
    for file in $(ls *.tsv.gz); do
        printf "==> $file\n"
        rg -wNz "$srchString" $file
        printf "\n"
    done
    printf "\n"
done
