#!/usr/bin/env bash
#
# Download needed files from IMDb, even if they already exist
#
# See https://www.imdb.com/interfaces/ for a description of IMDb datasets

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

# Keep track of elapsed time
SECONDS=0

function terminate() {
    saveDurations "$SECONDS"
    # Only keep 3 duration lines for this script
    trimDurations 3
    exit
}

# Make sure we can execute curl. If not, quit.
checkForExecutable curl

gz_files=(name.basics.tsv.gz title.basics.tsv.gz title.episode.tsv.gz
    title.principals.tsv.gz)

printf "==> Downloading new IMDb .gz files.\n"

# Let us know how long it took last time
printDuration

for file in "${gz_files[@]}"; do
    source="https://datasets.imdbws.com/$file"
    printf "Downloading $source\n"
    curl -s -O "$source"
done

# Caches are no longer valid
rm -rf "$cacheDirectory"
mkdir -p "$cacheDirectory"

printf "==> Recording IMDb .gz file sizes.\n"
rg -cz "^." "${gz_files[@]}" | sort | perl -p -e 's/:/\t/;' >"$numRecordsFile"

# Save durations and exit
terminate
