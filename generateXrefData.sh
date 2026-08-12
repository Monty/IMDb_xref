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
SCRAPER_ERR=""

function terminate() {
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
    else
        rm -f "$TMPFILE" "$TCONST_LIST" "$EVERY_TCONST" "$SCRAPER_ERR"
    fi
}

_scraper() {
    uv run --directory scraper python cli.py "$@"
}

function processDurations() {
    # Takes an optional exit status so callers can end non-zero (e.g. after a
    # failed scrape) while still recording durations/history.
    local rc="${1:-0}"
    # If we're not in the primary directory or bypassing, don't record times
    { [[ -n $OUTPUT_DIR ]] || [[ -n $BYPASS_PROCESSING ]]; } && exit "$rc"
    saveDurations "$SECONDS"
    # Only keep 10 duration lines for this script
    trimDurations -m 10
    # Save the contents of every tconst to use for manual comparison next time
    [[ -n $useEveryTconst ]] && saveHistory "$EVERY_TCONST"
    # Keep 20 history files for this script
    trimHistory -m 20
    exit "$rc"
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
        # Use the small example list. (big_IMDb_xref also diffed output against
        # saved results here; that regression check was not carried over.)
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
SCRAPER_ERR=$(mktemp)

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
failed=0
wafBlocked=""

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

    # Scrape full credits. Capture stderr rather than discarding it: a scraper
    # failure -- above all a WAF CAPTCHA -- must not be silently reinterpreted
    # as "fetched nothing", which used to leave an empty index behind a
    # cheerful "==> Done." and made an unseeded repo look identical to a
    # genuine no-results run.
    [[ -z $QUIET ]] && printf "  Fetching: %s\n" "$tconst"
    result=$(_scraper --delay 1 full-credits "$tconst" 2>"$SCRAPER_ERR")
    scrapeRC=$?
    if [[ $scrapeRC -ne 0 ]] || ! jq . <<<"$result" >/dev/null 2>&1; then
        # Errors print even with -q; a silent failure is the bug being fixed.
        reportSearchError "$tconst" "$SCRAPER_ERR" \
            "==> [${RED}Error${NO_COLOR}] Couldn't fetch credits for \"%s\":"
        failed=$((failed + 1))
        processed=$((processed + 1))
        # A CAPTCHA blocks every later fetch too, and continuing to hammer IMDb
        # is part of what escalates a silent challenge into a CAPTCHA. Stop.
        if isWAFChallenge "$SCRAPER_ERR"; then
            wafBlocked="yes"
            break
        fi
        continue
    fi
    if [[ -n $result ]] && [[ $result != "[]" ]]; then
        fetched=$((fetched + 1))
    fi
    processed=$((processed + 1))
done <"$TCONST_LIST"

if [[ -n $wafBlocked ]]; then
    printf "\n==> [${RED}Stopped${NO_COLOR}] IMDb is blocking automated requests.\n"
    printf "    Remaining shows were not fetched. Solve the challenge, then\n"
    printf "    re-run this script -- already-cached shows will be skipped.\n"
fi

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
    Failed:    $failed

    Index now contains:
$(echo "$stats" | jq -r 'to_entries[] | "      \(.key): \(.value)"')
EOF

# A failure count of zero is the only case that earns the "Ready to query"
# sign-off. Report failures even under -q, and exit non-zero so a caller
# (or demo seeding step) can tell a scrape that half-worked from one that did.
if [[ $failed -gt 0 ]]; then
    printf "\n==> [${YELLOW}Warning${NO_COLOR}] %s show(s) could not be fetched.\n" "$failed"
    printf "    The index below reflects only what was cached successfully.\n"
    processDurations 1
fi

[[ -z $QUIET ]] && printf "\n==> Ready to query. Try:\n"
[[ -z $QUIET ]] && printf "    ./findCastOf.sh \"Show Name\"\n"
[[ -z $QUIET ]] && printf "    ./xrefCast.sh \"Actor Name\"\n"

# Save durations and history, then exit
processDurations
