#!/usr/bin/env bash
#
# Regnerate credits cache (.xref_cache/tt*)
#
# shellcheck disable=SC2317     # Command appears to be unreachable

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

# Keep track of elapsed time
SECONDS=0

# Don't leave tempfiles around
trap terminate EXIT
#
function terminate() {
    saveDurations "$SECONDS"
    # Only keep 3 duration lines for this script
    trimDurations -m 3
    # Only keep 5 history files for this script
    trimHistory -m 5
    rm -f "$CACHE_LIST" "$TCONST_LIST" "$TMPFILE"
    exit
}

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

# Make sure we can execute curl. If not, quit.
checkForExecutable curl

printf "==> Downloading fullcredits files.\n"

# Let us know how long it took last time
printDuration

# https://www.imdb.com/title/tt5017060/fullcredits?ref_=tt_ql_1
# https://www.imdb.com/title/tt4786824/fullcredits?ref_=tt_ql_1
CACHE_LIST=$(mktemp)
TCONST_LIST=$(mktemp)
TMPFILE=$(mktemp)

ls -1 "$cacheDirectory" | rg "^tt" >"$TMPFILE"
rg "^tt" LinksToTitles.csv | cut -f 1 >>"$TMPFILE"
# Don't process all tconsts
# rg -I "^tt" ./*tconst Contrib/*tconst | cut -f 1 >>"$TMPFILE"

sort -fu "$TMPFILE" >"$TCONST_LIST"

while IFS='' read -r line; do
    printf "Person\tShow Title\tEpisode Title\tRank\tJob\tCharacter Name\tnconstID\ttconstID\n" \
        >"$cacheDirectory/$line"
    source="https://www.imdb.com/title/$line/fullcredits?ref_=tt_ql_1"
    curl -s "$source" -o "$TMPFILE"
    awk -f getFullcredits.awk "$TMPFILE" |
        sort -f -t$'\t' --key=5,5 --key=4,4n --key=1,1 |
        sed "s+&quot;+'+g" >>"$cacheDirectory/$line"
    showTitle="$(tail -1 "$cacheDirectory/$line" | cut -f 2)"
    printf "Writing $cacheDirectory/$line\t$showTitle\n"
    printf "$line\t$showTitle\n" >>"$CACHE_LIST"
done <"$TCONST_LIST"

# Save the list of tconst IDs and show titles we cached
sort -fd -t$'\t' --key=2 "$CACHE_LIST" | rg -v '&quot;' >"$TMPFILE"
saveHistory "$TMPFILE"

# Tell how many cache files we updated
num_tconsts=$(sed -n '$=' "$TMPFILE")
printf "\n==> Refreshed %d files in .xref_cache\n" "$num_tconsts"

# Save durations and exit
terminate