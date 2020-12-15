#!/usr/bin/env bash
# Print the first 5 lines of any downloaded IMDb .gz files
#
# See https://www.imdb.com/interfaces/ for a description of IMDb Datasets

for file in $(ls *.tsv.gz); do
    echo "File = $file"
    gzcat $file | head -5
    echo ""
done
