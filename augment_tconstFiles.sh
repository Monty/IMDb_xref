#!/usr/bin/env bash

# Expand initial tconst IDs in a .tconst file. Add the IMDb Primary Title,
# Original Title, and Date. Sort by Primary Title
#
# Preserve all non-tconst lines, place in the header

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
augment_tconstFiles.sh -- Modify .tconst files. Add Type, Primary Title, Original Title, Date

      For example, expand:
          tt1606375
          tt1399664
          tt3351208

      To:
          tt1606375   tvSeries      Downton Abbey       Downton Abbey       2010
          tt1399664   tvMiniSeries  The Night Manager   The Night Manager   2016
          tt3582458   tvSeries      Acquitted           Frikjent            2014

USAGE:
    ./augment_tconstFiles.sh [OPTIONS] FILE [FILE...]

OPTIONS:
    -h      Print this message.
    -a      Allow tvEpisodes -- normally they are filtered out
    -i      In place -- overwrite original file
    -y      Yes -- overwrite without asking "OK to overwrite...

EXAMPLES:
    ./augment_tconstFiles.sh Contrib/OPB.tconst
    ./augment_tconstFiles.sh -i Contrib/*.tconst
    ./augment_tconstFiles.sh -iy Contrib/*.tconst
EOF
}

# Don't leave tempfiles around
trap terminate EXIT
#
function terminate() {
    if [ -n "$DEBUG" ]; then
        printf "\nTerminating: %s\n" "$(basename "$0")" >&2
        printf "Not removing:\n" >&2
        printf "%s\n" "$RESULT" "$COMMENTS" "$CACHE_LIST" "$SEARCH_LIST" \
            "$TCONST_LIST" >&2
    else
        rm -rf "$RESULT" "$COMMENTS" "$CACHE_LIST" "$SEARCH_LIST" "$TCONST_LIST"
    fi
}

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

while getopts ":haiy" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    a)
        ALLOW_EPISODES="yes"
        ;;
    i)
        INPLACE="yes"
        ;;
    y)
        INPLACE="yes"
        DONT_ASK="yes"
        ;;
    \?)
        printf "==> Ignoring invalid option: -%s\n\n" "$OPTARG" >&2
        ;;
    esac
done
shift $((OPTIND - 1))

# Make sure prerequisites are satisfied
ensurePrerequisites

# Need some tempfiles
RESULT=$(mktemp)
COMMENTS=$(mktemp)
CACHE_LIST=$(mktemp)
SEARCH_LIST=$(mktemp)
TCONST_LIST=$(mktemp)

# Make sure a file was supplied
if [ $# -eq 0 ]; then
    printf "==> [${RED}Error${NO_COLOR}] Please supply a tconst filename on the command line.\n\n" >&2
    exit 1
fi

function copyResults() {
    # Preserve comments at top
    cat "$COMMENTS"
    # Then add the sorted tconst lines
    if [ -n "$ALLOW_EPISODES" ]; then
        sort -f -t$'\t' --key=3,3 "$RESULT"
    else
        sort -f -t$'\t' --key=3,3 "$RESULT" | rg -wNv "tvEpisode"
    fi
}

cacheFile="$cacheDirectory/augmented"
touch $cacheFile
rg -N "^tt" "$cacheFile" | cut -f 1 | sort >"$CACHE_LIST"

for file in "$@"; do
    [ -z "$INPLACE" ] && printf "==> %s\n" "$file"

    # Make sure there is no carryover
    true >"$RESULT"

    # Gather and preserve all non-tconst lines
    rg -Nv "^tt" "$file" >"$COMMENTS"

    # Gather all the lines with tconsts in column 1
    rg -N "^tt" "$file" | cut -f 1 | sort -u >"$SEARCH_LIST"

    # Figure out which tconst IDs are cached and which aren't
    comm -13 "$CACHE_LIST" "$SEARCH_LIST" >"$TCONST_LIST"

    # Grab the ones already cached
    rg -wNz -f "$SEARCH_LIST" "$cacheFile" >"$RESULT"

    # If everthing is cached, skip searching entirely
    if [ "$(rg -c ^tt "$TCONST_LIST")" ]; then
        # Look the ones up that weren't cached, get fields 1-4,6
        rg -wNz -f "$TCONST_LIST" title.basics.tsv.gz | cut -f 1-4,6 |
            perl -p -e 's+\\N++g;' >>"$RESULT"
    fi

    # Either overwrite or print on stdout
    if [ -z "$INPLACE" ]; then
        copyResults
        printf "\n"
    else
        if [ -z "$DONT_ASK" ]; then
            waitUntil "$YN_PREF" -N "OK to overwrite $file?" && copyResults \
                >"$file"
        else
            copyResults >"$file"
        fi
    fi
    cat $cacheFile >>"$RESULT"
    sort -u "$RESULT" >$cacheFile
done
