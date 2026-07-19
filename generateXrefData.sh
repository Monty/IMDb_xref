#!/usr/bin/env bash
#
# Generate show and cast data from IMDb via web scraping.
# Reads tconst files, scrapes full credits for each, builds index.

DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

# Keep track of elapsed time
SECONDS=0

function help() {
    cat <<EOF
generateXrefData.sh -- Fetch cast data for shows listed in .tconst files.

Reads all .tconst files (or specified ones), scrapes IMDb for full credits,
and rebuilds the local index for cross-referencing.

USAGE:
    ./generateXrefData.sh [TCONST_FILE ...]

OPTIONS:
    -h      Print this message.
    -q      Quiet -- Minimize output.
    -r      Reload -- Re-scrape all shows, ignoring cache.
    -t      Test mode -- Use tconst.example.

EXAMPLES:
    ./generateXrefData.sh
    ./generateXrefData.sh Contrib/Acorn.tconst
    ./generateXrefData.sh -r
    ./generateXrefData.sh -qt
EOF
}

trap terminate EXIT
TMPFILE=""
TCONST_LIST=""
EVERY_TCONST=""

function terminate() {
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
    else
        rm -f "$TMPFILE" "$TCONST_LIST" "$EVERY_TCONST"
    fi
}

_scraper() {
    uv run --directory scraper python cli.py "$@"
}

function processDurations() {
    # If we're not in the primary directory or bypassing, don't record times
    ([[ -n $OUTPUT_DIR ]] || [[ -n $BYPASS_PROCESSING ]]) && exit
    saveDurations "$SECONDS"
    # Only keep 10 duration lines for this script
    trimDurations -m 10
    # Save the contents of every tconst to use for manual comparison next time
    [[ -n $useEveryTconst ]] && saveHistory "$EVERY_TCONST"
    # Keep 20 history files for this script
    trimHistory -m 20
    exit
}

while getopts ":hqrt" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    q) QUIET="yes" ;;
    r) REFRESH="yes" ;;
    t)
        TEST_MODE="yes"
        TCONST_FILES=("tconst.example")
        ;;
    \?) printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2 ;;
    :)
        printf "==> Option -$OPTARG requires an argument.\n\n" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

TMPFILE=$(mktemp)
TCONST_LIST=$(mktemp)
EVERY_TCONST=$(mktemp)

# Pick tconst file(s)
if [[ -z ${TCONST_FILES[*]} ]]; then
    if [[ $# -eq 0 ]]; then
        TCONST_FILES=(*.tconst)
        [[ -z $QUIET ]] && printf "\n==> Searching all .tconst files for IMDb title IDs.\n"
        # Cache is only enabled if *.tconst is used, which is the usual mode.
        useEveryTconst="yes"
        # The history file should contain the contents of every tconst file used
        head -9999 -- *.tconst | rg -v "^$|#" >"$EVERY_TCONST"
    else
        TCONST_FILES=("$@")
        [[ -z $QUIET ]] && printf "\n==> Searching %s for IMDb title IDs.\n" "${TCONST_FILES[*]}"
    fi
fi

# Extract all tconst IDs
rg -IN "^tt" "${TCONST_FILES[@]}" | cut -f1 | sort -u >"$TCONST_LIST"
total=$(sed -n '$=' "$TCONST_LIST")
[[ -z $total ]] && total=0

if [[ $total -eq 0 ]]; then
    printf "\n==> No tconst IDs found.\n"
    terminate
    exit 0
fi

[[ -z $QUIET ]] && printf "==> Processing %s shows...\n\n" "$total"

# Process each tconst
processed=0
skipped=0
fetched=0

while IFS= read -r tconst; do
    [[ -z $tconst ]] && continue

    if [[ -n $REFRESH ]]; then
        # Force re-scrape
        rm -f ".xref_cache/${tconst}.json"
    fi

    # Check if already cached with cast data
    # title-basics populates the index without cast, so check cast too
    titleInfo=$(_scraper title-info "$tconst" 2>/dev/null)
    castCheck=$(_scraper cast-for-show "$tconst" 2>/dev/null)
    if [[ -n $titleInfo ]] && [[ $titleInfo != *"not found"* ]] && [[ -n $castCheck ]] && [[ $castCheck != "[]" ]]; then
        skipped=$((skipped + 1))
        continue
    fi

    # Scrape full credits
    [[ -z $QUIET ]] && printf "  Fetching: %s\n" "$tconst"
    result=$(_scraper --delay 1 full-credits "$tconst" 2>/dev/null)
    if [[ -n $result ]] && [[ $result != "[]" ]]; then
        fetched=$((fetched + 1))
    fi
    processed=$((processed + 1))
done <"$TCONST_LIST"

# Rebuild index
[[ -z $QUIET ]] && printf "\n==> Rebuilding index...\n"
_scraper rebuild-index >/dev/null 2>&1

# Print stats
stats=$(_scraper index-stats 2>/dev/null)
[[ -z $QUIET ]] && cat <<EOF

==> Done.
    Processed: $processed shows
    Fetched:   $fetched new
    Skipped:   $skipped cached

    Index now contains:
$(echo "$stats" | jq -r 'to_entries[] | "      \(.key): \(.value)"')
EOF

[[ -z $QUIET ]] && printf "\n==> Ready to query. Try:\n"
[[ -z $QUIET ]] && printf "    ./findCastOf.sh \"Show Name\"\n"
[[ -z $QUIET ]] && printf "    ./xrefCast.sh \"Actor Name\"\n"

# Save durations and history, then exit
processDurations
