#!/usr/bin/env bash
# Print the first 5 lines of any downloaded IMDb .gz files
#
# See https://www.imdb.com/interfaces/ for a description of IMDb datasets

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd $DIRNAME
export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

for file in $(ls *.tsv.gz); do
    printf "File = $file\n"
    gzcat $file | head -5
    printf "\n"
done
