#!/usr/bin/env bash
# Count the instances of any "word" in downloaded IMDb data files

# INVOCATION:
#    ./countIMDbInstances.sh tt5123128 nm1524628
#    ./countIMDbInstances.sh Catarella

for srchString in "$@"; do
    for file in $(ls *.gz); do
        count=$(rg -wcz "$srchString" $file)
        if [ "$count" == "" ]; then
            count=0
        fi
        printf "%-10s %5d  %s\n" "$srchString" $count $file
    done
    printf "\n"
done
