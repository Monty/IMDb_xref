#!/usr/bin/env bash

# Expand initial tconst IDs in a .tconst file. Add the IMDb Primary Title,
# Original Title, and Date. Sort by Primary Title
#
# Preserve all non-tconst lines, place in the header

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
augment_tconstFiles.sh -- Add Type, Primary Title, Original Title, Date. Sort by Primary Title.

      A matching .xlate file, if present, translates the Primary Title --
      Netflix.tconst pairs with Netflix.xlate. The Original Title from IMDb is
      preserved, so a translated row shows both.

      For example, expand:
          tt1606375
          tt1399664
          tt3582458

      To:
          tt3582458   tvSeries      Acquitted           Frikjent            2014
          tt1606375   tvSeries      Downton Abbey       Downton Abbey       2010
          tt1399664   tvMiniSeries  The Night Manager   The Night Manager   2016

USAGE:
    ./augment_tconstFiles.sh [OPTIONS] FILE [FILE...]

OPTIONS:
    -h      Print this message.
    -a      Allow tvEpisodes -- normally they are filtered out
    -i      In place -- overwrite original file, asking first
    -y      Yes -- overwrite in place without asking. Implies -i.
    -r      Reload -- discard the augmented cache and re-read every title from
            title.basics.tsv.gz. Done automatically when that file is newer
            than the cache.

EXAMPLES:
    ./augment_tconstFiles.sh Contrib/OPB.tconst
    ./augment_tconstFiles.sh -i Contrib/*.tconst
    ./augment_tconstFiles.sh -y Contrib/*.tconst
    ./augment_tconstFiles.sh -ry Contrib/*.tconst
EOF
}

# Don't leave tempfiles around
trap terminate EXIT
#
function terminate() {
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: %s\n" "$(basename "$0")" >&2
        printf "Not removing:\n" >&2
        cat <<EOT >&2
RESULT $RESULT
COMMENTS $COMMENTS
CACHE_LIST $CACHE_LIST
SEARCH_LIST $SEARCH_LIST
TCONST_LIST $TCONST_LIST
EOT
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

while getopts ":hairy" opt; do
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
    r)
        RELOAD="yes"
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
if [[ $# -eq 0 ]]; then
    printf "==> [${RED}Error${NO_COLOR}] Please supply a tconst filename on the command line.\n\n" >&2
    exit 1
fi

# Apply the .xlate translations, if this file has any, to $RESULT on its way
# out. Column 1 of a .xlate is the IMDb title, column 2 the English/service
# title -- so a match replaces the Primary Title and the real Original Title is
# kept alongside it.
#
# Applied here rather than to $RESULT itself because $RESULT is appended to the
# shared augmented cache at the end of each iteration. Translating in place
# would store one file's translations in a cache every other file reads.
#
# Deliberately NOT the same rule live-fetch uses. There, "$3 in xlate1 { $4 =
# $3; ... }" overwrites the Original Title unconditionally, which is harmless
# because its scraped original_title is usually empty anyway. Here it would
# throw away real title.basics data: Ørnen's Original Title is "Ørnen: En
# krimi-odyssé", and that rule would leave plain "Ørnen". So column 4 is only
# filled from column 3 when it holds nothing better.
function applyXlate() {
    if [[ -z $XLATE ]]; then
        cat "$RESULT"
        return
    fi
    awk -F'\t' -v OFS='\t' '
        NR == FNR { xlate1[$1] = $2; xlate2[$2] = $1; next }
        $3 in xlate1 {
            if ($4 == "" || $4 == $3) $4 = $3
            $3 = xlate1[$3]
        }
        $4 == "" && $3 in xlate2 { $4 = xlate2[$3] }
        { print }
    ' "$XLATE" "$RESULT"
}

function copyResults() {
    # Preserve comments at top
    cat "$COMMENTS"
    # Then add the sorted tconst lines. Sorting after translation, so the order
    # follows the titles actually written -- matching live-fetch, where the
    # same file sorts "The Eagle" rather than "Ørnen".
    if [[ -n $ALLOW_EPISODES ]]; then
        applyXlate | sort -f -t$'\t' --key=3,3
    else
        applyXlate | sort -f -t$'\t' --key=3,3 | rg -wNv "tvEpisode"
    fi
}

cacheFile="$cacheDirectory/augmented"

# Every row in the cache is derived from title.basics.tsv.gz, so a row older
# than that file is strictly worse than re-reading it -- there is no fetch cost
# here to justify serving stale data. This matters because a cached tconst is
# never looked up again: when IMDb revises a title (an Original Title changing
# is the usual one) the stale row would otherwise win permanently.
#
# Same gz-is-newer test generateXrefData.sh uses to decide RELOAD, and -r
# forces it. The whole cache is discarded rather than individual rows, since
# they all came from the same dataset. [[ -nt ]] follows symlinks, so the
# WhatsStreamingToday indirection is compared correctly, and a missing cache
# file counts as newer, which creates it.
#
# Checked before the touch below -- touching first would set the cache's mtime
# to now and make the comparison always false.
if [[ -n $RELOAD ]] || [[ title.basics.tsv.gz -nt $cacheFile ]]; then
    if [[ -s $cacheFile ]]; then
        printf "==> Refreshing augmented cache from title.basics.tsv.gz.\n"
        true >"$cacheFile"
    fi
fi

touch "$cacheFile"

for file in "$@"; do
    [[ -z $INPLACE ]] && printf "==> %s\n" "$file"

    # Make sure there is no carryover
    true >"$RESULT"

    # A matching .xlate beside the .tconst supplies title translations --
    # Netflix.tconst pairs with Netflix.xlate. Same convention as live-fetch,
    # and the same file generateXrefData.sh reads.
    XLATE=""
    base="${file%.tconst}"
    [[ -f "${base}.xlate" ]] && XLATE="${base}.xlate"

    # Gather and preserve all non-tconst lines
    rg -Nv "^tt" "$file" >"$COMMENTS"

    # Gather all the lines with tconsts in column 1
    rg -N "^tt" "$file" | cut -f 1 | sort -u >"$SEARCH_LIST"

    # Which tconsts are cached? Rebuilt per file, not once before the loop:
    # each iteration appends its results to the cache, so a list built up front
    # goes stale the moment the first file is processed. A tconst shared by two
    # files then satisfied the cache lookup below *and* still appeared in
    # TCONST_LIST, so it was written twice -- Happy Valley in both Acorn.tconst
    # and BBox.tconst. Only visible when the tconst was not already cached, so
    # -r and first runs on a fresh clone showed it while ordinary runs did not.
    rg -N "^tt" "$cacheFile" | cut -f 1 | sort >"$CACHE_LIST"

    # Figure out which tconst IDs are cached and which aren't
    comm -13 "$CACHE_LIST" "$SEARCH_LIST" >"$TCONST_LIST"

    # Grab the ones already cached
    rg -wNz -f "$SEARCH_LIST" "$cacheFile" >"$RESULT"

    # If everything is cached, skip searching entirely
    if [[ -n "$(rg -c ^tt "$TCONST_LIST")" ]]; then
        # Look the ones up that weren't cached, get fields 1-4,6
        rg -wNz -f "$TCONST_LIST" title.basics.tsv.gz | cut -f 1-4,6 |
            perl -p -e 's+\\N++g;' >>"$RESULT"
    fi

    # Either overwrite or print on stdout
    if [[ -z $INPLACE ]]; then
        copyResults
        printf "\n"
    else
        if [[ -z $DONT_ASK ]]; then
            waitUntil "$YN_PREF" -N "OK to overwrite $file?" && copyResults \
                >"$file"
        else
            copyResults >"$file"
        fi
    fi
    cat "$cacheFile" >>"$RESULT"
    sort -u "$RESULT" >"$cacheFile"
done
