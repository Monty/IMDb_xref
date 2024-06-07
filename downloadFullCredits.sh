#!/usr/bin/env bash
#
# Download full credits for a tconst - useful in debugging data errors

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

# Make sure we can execute curl. If not, quit.
checkForExecutable curl

printf "==> Downloading fullcredits files.\n"

# https://www.imdb.com/title/tt5017060/fullcredits?ref_=tt_ql_1
# https://www.imdb.com/title/tt4786824/fullcredits?ref_=tt_ql_1
# https://www.imdb.com/title/tt2249364/fullcredits?ref_=tt_ql_1

for file in "$@"; do
    source="https://www.imdb.com/title/$file/fullcredits?ref_=tt_ql_1"
    outfile="$file-fullCredits.txt"
    shortfile="$file-cache.csv"
    printf "Person\tShow Title\tEpisode Title\tRank\tJob\tCharacter Name\tnconstID\ttconstID\n" \
        >"$shortfile"
    printf "Writing %s\t" "$shortfile"
    curl -s "$source" -o "$outfile"
    #
    # awk -f getFullcredits.awk "$outfile" | sort -fu >"$shortfile"
    awk -f getFullcredits.awk "$outfile" |
        sort -f -t$'\t' --key=5,5 --key=4,4n --key=1,1 \
            >>"$shortfile"
    tail -1 "$shortfile" | cut -f 2
done
