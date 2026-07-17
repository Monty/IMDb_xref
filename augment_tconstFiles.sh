#!/usr/bin/env bash

# Expand initial tconst IDs in a .tconst file. Add Type, Primary Title,
# Original Title, and Date. Sort by Primary Title.
# Uses the scraper instead of .gz database files.

DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
augment_tconstFiles.sh -- Add Type, Primary Title, Original Title, Date.

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
    -i      In place -- overwrite original file
    -y      Yes -- overwrite without asking
    -f      Fetch -- scrape IMDb for any missing titles

EXAMPLES:
    ./augment_tconstFiles.sh Contrib/Acorn.tconst
    ./augment_tconstFiles.sh -i Contrib/*.tconst
    ./augment_tconstFiles.sh -fy favorites.tconst
EOF
}

trap terminate EXIT
RESULT=""
COMMENTS=""
SEARCH_LIST=""
TCONST_LIST=""

function terminate() {
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: %s\n" "$(basename "$0")" >&2
    else
        rm -f "$RESULT" "$COMMENTS" "$SEARCH_LIST" "$TCONST_LIST"
    fi
}

trap cleanup INT
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

_scraper() {
    uv run --directory scraper python cli.py "$@"
}

while getopts ":haiyf" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    a) ALLOW_EPISODES="yes" ;;
    i) INPLACE="yes" ;;
    y)
        INPLACE="yes"
        DONT_ASK="yes"
        ;;
    f) FETCH_MISSING="yes" ;;
    \?) printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2 ;;
    esac
done
shift $((OPTIND - 1))

RESULT=$(mktemp)
COMMENTS=$(mktemp)
SEARCH_LIST=$(mktemp)
TCONST_LIST=$(mktemp)

if [[ $# -eq 0 ]]; then
    printf "==> [${RED}Error${NO_COLOR}] Please supply a tconst filename.\n\n" >&2
    exit 1
fi

# Ensure index exists
_scraper rebuild-index >/dev/null 2>&1

function copyResults() {
    cat "$COMMENTS"
    if [[ -n $ALLOW_EPISODES ]]; then
        sort -f -t$'\t' --key=3,3 "$RESULT"
    else
        sort -f -t$'\t' --key=3,3 "$RESULT" | rg -wNv "tvEpisode"
    fi
}

for file in "$@"; do
    [[ -z $INPLACE ]] && printf "==> %s\n" "$file"

    true >"$RESULT"

    # Preserve comments
    rg -Nv "^tt" "$file" >"$COMMENTS"

    # Get unique tconst IDs
    rg -N "^tt" "$file" | cut -f1 | sort -u >"$SEARCH_LIST"

    # Check which are in the index
    indexed=$(_scraper list-titles 2>/dev/null | jq -r '.[].tconst')
    comm -23 "$SEARCH_LIST" <(echo "$indexed" | sort) >"$TCONST_LIST" 2>/dev/null || true

    # Process each tconst
    while IFS= read -r tconst; do
        [[ -z $tconst ]] && continue

        # Try index first
        info=$(_scraper title-info "$tconst" 2>/dev/null)
        if [[ -n $info ]] && [[ $info != *"not found"* ]]; then
            title=$(jq -r '.title // ""' <<<"$info")
            year=$(jq -r '.year // ""' <<<"$info")
            types=$(jq -r '(.types // []) | join(",")' <<<"$info")
            printf "%s\t%s\t%s\t\t%s\n" "$tconst" "$types" "$title" "$year" >>"$RESULT"
            continue
        fi

        # Fetch from IMDb if requested
        if [[ -n $FETCH_MISSING ]]; then
            printf "  Fetching: %s\n" "$tconst"
            _scraper --delay 1 full-credits "$tconst" >/dev/null 2>&1
            _scraper rebuild-index >/dev/null 2>&1
            info=$(_scraper title-info "$tconst" 2>/dev/null)
            if [[ -n $info ]] && [[ $info != *"not found"* ]]; then
                title=$(jq -r '.title // ""' <<<"$info")
                year=$(jq -r '.year // ""' <<<"$info")
                types=$(jq -r '(.types // []) | join(",")' <<<"$info")
                printf "%s\t%s\t%s\t\t%s\n" "$tconst" "$types" "$title" "$year" >>"$RESULT"
            fi
        fi
    done <"$SEARCH_LIST"

    if [[ -z $INPLACE ]]; then
        copyResults
        printf "\n"
    else
        if [[ -z $DONT_ASK ]]; then
            waitUntil "$YN_PREF" -N "OK to overwrite $file?" && copyResults >"$file"
        else
            copyResults >"$file"
        fi
    fi
done
