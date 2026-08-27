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
    -i      In place -- overwrite original file, asking first
    -y      Yes -- overwrite in place without asking. Implies -i.
    -f      Fetch harder -- if a title page yields nothing, also scrape its
            fullcredits page. Missing titles are looked up either way.

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
CACHE_LIST=""

function terminate() {
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: %s\n" "$(basename "$0")" >&2
    else
        rm -f "$RESULT" "$COMMENTS" "$SEARCH_LIST" "$TCONST_LIST" "$CACHE_LIST"
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

# bash getopts (POSIX-style) stops at the first non-option operand, so an
# option placed after a filename -- "file -i" -- is left in "$@" and would be
# treated as a filename. Catch that and point at the fix rather than failing
# obscurely later (e.g. basename choking on "-i").
for arg in "$@"; do
    if [[ $arg == -* ]]; then
        printf "==> [${RED}Error${NO_COLOR}] Option '%s' must come before the filename(s).\n" "$arg" >&2
        printf "    Put options first, or use -- to end option parsing.\n\n" >&2
        exit 1
    fi
done

RESULT=$(mktemp)
COMMENTS=$(mktemp)
SEARCH_LIST=$(mktemp)
TCONST_LIST=$(mktemp)
CACHE_LIST=$(mktemp)

# Persistent cache of all augmented tconst data
AUGMENTED="$cacheDirectory/augmented"
mkdir -p "$cacheDirectory"
touch "$AUGMENTED"

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
    fetchFailed=""

    # Make sure there is no carryover
    true >"$RESULT"

    # Gather and preserve all non-tconst lines
    rg -Nv "^tt" "$file" >"$COMMENTS"

    # Gather all tconst IDs
    rg -N "^tt" "$file" | cut -f1 | sort -u >"$SEARCH_LIST"

    # Build list of cached tconsts
    cut -f1 "$AUGMENTED" | sort >"$CACHE_LIST"

    # Figure out which tconsts need looking up (in SEARCH_LIST but not in CACHE_LIST)
    comm -23 "$SEARCH_LIST" "$CACHE_LIST" >"$TCONST_LIST"

    # Grab the ones already cached using rg batch matching
    if [[ -s $SEARCH_LIST ]]; then
        rg -wNz -f "$SEARCH_LIST" "$AUGMENTED" >"$RESULT" 2>/dev/null || true
    fi

    # Look for corresponding .xlate file to fill/override original titles
    XLATE=""
    base=$(basename "$file" .tconst)
    if [[ -f "${base}.xlate" ]]; then
        XLATE="${base}.xlate"
    fi

    # Process tconsts that weren't cached
    while IFS= read -r tconst; do
        [[ -z $tconst ]] && continue

        # Reset variables for each iteration
        title=""
        orig_title=""
        year=""
        types=""

        printf "  Fetching: %s\n" "$tconst" >&2

        # Try index first (from previous title-basics or full-credits scrapes)
        info=$(_scraper title-info "$tconst" 2>/dev/null)
        if [[ -n $info ]] && [[ $info != *"not found"* ]]; then
            title=$(jq -r '.title // ""' <<<"$info")
            orig_title=$(jq -r '.original_title // ""' <<<"$info")
            year=$(jq -r '.year // ""' <<<"$info")
            types=$(jq -r '(.types // []) | join(",")' <<<"$info")
        fi

        # If not in index, fetch from IMDb via title-basics
        if [[ -z $title ]]; then
            info=$(_scraper --delay 1 title-basics "$tconst" 2>/dev/null)
            if [[ -n $info ]] && [[ $info != *"not found"* ]]; then
                title=$(jq -r '.title // ""' <<<"$info")
                orig_title=$(jq -r '.original_title // ""' <<<"$info")
                year=$(jq -r '.year // ""' <<<"$info")
                types=$(jq -r '(.types // []) | join(",")' <<<"$info")
            fi
        fi

        # If title-basics failed and -f is set, try full-credits
        if [[ -z $title ]] && [[ -n $FETCH_MISSING ]]; then
            _scraper --delay 1 full-credits "$tconst" >/dev/null 2>&1
            _scraper rebuild-index >/dev/null 2>&1
            info=$(_scraper title-info "$tconst" 2>/dev/null)
            if [[ -n $info ]] && [[ $info != *"not found"* ]]; then
                title=$(jq -r '.title // ""' <<<"$info")
                orig_title=$(jq -r '.original_title // ""' <<<"$info")
                year=$(jq -r '.year // ""' <<<"$info")
                types=$(jq -r '(.types // []) | join(",")' <<<"$info")
            fi
        fi

        if [[ -n $title ]]; then
            printf "%s\t%s\t%s\t%s\t%s\n" "$tconst" "$types" "$title" "$orig_title" "$year" >>"$RESULT"
        else
            # Fetch failed (WAF challenge, network error, delisted title).
            # Never drop the tconst: fall back to whatever the input already
            # had for it -- a full row if the file carried one, otherwise the
            # bare tconst -- and warn so the miss is visible rather than
            # silently deleting data on an in-place overwrite.
            original=$(rg -N "^${tconst}\b" "$file" | head -n 1)
            [[ -z $original ]] && original="$tconst"
            printf "%s\n" "$original" >>"$RESULT"
            printf "  ${YELLOW}Warning${NO_COLOR}: couldn't look up %s -- kept existing entry\n" "$tconst" >&2
            fetchFailed="yes"
        fi
    done <"$TCONST_LIST"

    # Post-process: apply xlate transformation to ALL results for display
    # xlate col1 = IMDb/foreign title, col2 = English/Netflix title
    # If primary title matches col1: always show English as primary, IMDb as original
    # If primary title matches col2 and no original title: put col1 as original
    if [[ -n $XLATE ]] && [[ -s $RESULT ]]; then
        tmp=$(mktemp)
        awk -F'\t' -v OFS='\t' '
            NR == FNR { xlate1[$1] = $2; xlate2[$2] = $1; next }
            $3 in xlate1 { $4 = $3; $3 = xlate1[$3] }
            $4 == "" && $3 in xlate2 { $4 = xlate2[$3] }
            { print }
        ' "$XLATE" "$RESULT" >"$tmp"
        mv "$tmp" "$RESULT"
    fi

    # IMDb only reports an original title when it differs from the primary; the
    # bulk dataset (and our .csv files) instead repeat the primary. After any
    # xlate step has had its chance to fill $4 from a foreign title, copy the
    # primary ($3) into any original-title column ($4) that is still empty, so
    # re-augmenting doesn't blank that column on English-language entries.
    # Only touches full (>=4-field) rows, leaving bare-tconst fallbacks alone.
    if [[ -s $RESULT ]]; then
        tmp=$(mktemp)
        awk -F'\t' -v OFS='\t' 'NF >= 4 && $4 == "" { $4 = $3 } { print }' "$RESULT" >"$tmp"
        mv "$tmp" "$RESULT"
    fi

    # Save results to the augmented cache, but only rows that actually have
    # data (a tab-separated title). A bare tconst preserved after a failed
    # fetch must not poison the cache with a title-less entry.
    # Remove old entries first, then append the new complete ones.
    if [[ -s $RESULT ]]; then
        tmp=$(mktemp)
        complete=$(mktemp)
        rg -N '\t' "$RESULT" >"$complete" || true
        if [[ -s $complete ]]; then
            # Match each tconst as an exact first field: anchor with ^ and the
            # trailing tab. Anchoring with ^ alone treats the tconst as a
            # prefix, so re-augmenting tt123 would also evict tt1234.
            grep -v -f <(awk -F'\t' '{printf "^%s\t\n", $1}' "$complete") "$AUGMENTED" >"$tmp" 2>/dev/null || true
            cat "$tmp" "$complete" >"$AUGMENTED"
        fi
        rm -f "$tmp" "$complete"
    fi

    # If any lookup failed, say so once, clearly -- especially important before
    # an in-place overwrite so a WAF challenge or outage is not mistaken for
    # "these titles no longer exist".
    if [[ -n $fetchFailed ]]; then
        printf "\n==> ${YELLOW}Note${NO_COLOR}: some titles couldn't be looked up (kept their existing entries).\n" >&2
        printf "    A WAF challenge is the usual cause -- see scraper/tools/solve_challenge.py -- then rerun.\n" >&2
    fi

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
