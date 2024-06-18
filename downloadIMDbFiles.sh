#!/usr/bin/env bash
#
# Download needed files from IMDb, even if they already exist
#
# See https://www.imdb.com/interfaces/ for a description of IMDb datasets

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

# Keep track of elapsed time
SECONDS=0

function terminate() {
    saveDurations "$SECONDS"
    # Only keep 3 duration lines for this script
    trimDurations -m 3
    #
    saveHistory "$numRecordsFile"
    # Only keep 5 history files for this script
    trimHistory -m 5
    exit
}

# Make sure we can execute curl. If not, quit.
checkForExecutable curl

printf "==> Downloading new IMDb .gz files.\n"

# Let us know how long it took last time
printDuration

for file in "${gzFiles[@]}"; do
    source="https://datasets.imdbws.com/$file"
    printf "Downloading %s\n" "$source"
    curl -s -O "$source"
done

# Caches are no longer valid
rm -rf "$cacheDirectory"
mkdir -p "$cacheDirectory"

printf "==> Recording IMDb .gz file sizes.\n"
rg -cz "^." "${gzFiles[@]}" | sort | perl -p -e 's/:/\t/;' >"$numRecordsFile"

# Save durations and exit
terminate
