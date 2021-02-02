#!/usr/bin/env bash
#
# Print the first 5 lines of any downloaded IMDb .gz files
#
# See https://www.imdb.com/interfaces/ for a description of IMDb datasets

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

# Make sure prerequisites are satisfied
ensurePrerequisites

for file in *.tsv.gz; do
    [[ -e $file ]] || break # handle the case of no files
    printf "==> $file\n"
    gzcat "$file" | head -5
    printf "\n"
done
