#!/usr/bin/env bash
#
# List all people found in a named show on IMDb
# Uses the Playwright-based scraper instead of .gz database files.

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
findCastOf.sh -- List principal cast & crew members of shows on IMDb.

Search IMDb titles for show names or tconst IDs. A tconst ID should be unique,
but a show name can have several or even many matches. Allow user to select one
match or skip if there are too many.

List principal cast & crew members and any characters portrayed. If you search for
multiple shows, also list cast & crew members who are found in more than one.
Includes episode counts for ranking cast members.

If you don't enter a parameter on the command line, you'll be prompted for
input.

USAGE:
    ./findCastOf.sh [TCONST...] [SHOW TITLE...]

OPTIONS:
    -h      Print this message.
    -d      Duplicates -- Only list cast & crew members found in more than one show.
    -l      Use $PAGER to list results a page at a time.
    -m      Maximum matches for a show title allowed in menu - defaults to 25.
    -f      File -- Add to specific file rather than the default $favoritesFile.
    -s      Short - don't list details, just ask about adding to favorites.tconst.
    -e NNN  Minimum episodes -- Only show cast members with at least NNN episodes.
            Default 0 (show all). Use -e 10 to show only series regulars.

EXAMPLES:
    ./findCastOf.sh
    ./findCastOf.sh -d
    ./findCastOf.sh "The Crown"
    ./findCastOf.sh tt1606375
    ./findCastOf.sh tt1606375 tt1399664 "Broadchurch"
    ./findCastOf.sh -d "The Night Manager" "The Crown" "The Durrells"
    ./findCastOf.sh -e 10 "The Crown"
EOF
}

# Don't leave tempfiles around
trap terminate EXIT
#
TMPFILE=""
ALL_TERMS=""
ALL_MATCHES=""
CAST_CSV=""
SEARCH_LIST=""
NEW_LIST=""
SCRAPER_ERR=""

function terminate() {
    trimHistory -m 20 "$favoritesFile"
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
    else
        rm -f "$ALL_TERMS" "$ALL_MATCHES" "$CAST_CSV" "$SEARCH_LIST" "$NEW_LIST" "$SCRAPER_ERR"
        rm -f "${CAST_CSV}.header"
    fi
}

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

function loopOrExitP() {
    printf "\n"
    terminate
    [[ -n $NO_MENUS ]] && exit
    exec ./start.command
}

# Short helper: run the scraper CLI from the scraper directory
_scraper() {
    uv run --directory scraper python cli.py "$@"
}

while getopts ":hf:dlme:s" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    f) favoritesFile="$OPTARG" ;;
    d) MULTIPLE_NAMES_ONLY="yes" ;;
    l) usePager=1 ;;
    m) maxMenuSize="$OPTARG" ;;
    e) minEpisodes="$OPTARG" ;;
    s) SHORT="yes" ;;
    \?) printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2 ;;
    :)
        printf "Option -$OPTARG requires an argument.\n" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

# Need some tempfiles
ALL_TERMS=$(mktemp)
ALL_MATCHES=$(mktemp)
CAST_CSV=$(mktemp)
SEARCH_LIST=$(mktemp)
NEW_LIST=$(mktemp)
TMPFILE=$(mktemp)
SCRAPER_ERR=$(mktemp)

# Make sure a search term is supplied
if [[ $# -eq 0 ]]; then
    cat <<EOF

==> I can find principal cast & crew members based on show names or tconst IDs,
    such as tt1606375 -- which is the tconst for Downton Abbey:
    https://www.imdb.com/title/tt1606375/

Only one search term per line. Enter a blank line to finish. Enter two or
more shows to see any principal cast & crew members they have in common.
EOF
    while read -r -p "Enter a show name or tconst ID: " searchTerm; do
        [[ -z $searchTerm ]] && break
        tr -ds '"' '[:space:]' <<<"$searchTerm" >>"$ALL_TERMS"
    done </dev/tty
    if [[ ! -s $ALL_TERMS ]]; then
        if waitUntil "$YN_PREF" -N \
            "Would you like to see the principal cast & crew of Downton Abbey as an example?"; then
            printf "tt1606375\n" >>"$ALL_TERMS"
        else
            loopOrExitP
        fi
    fi
    printf "\n"
fi

# Let user know what favorites file we're using.
printf "==> Any favorites you save will be added to: ${BLUE}$favoritesFile\n${NO_COLOR}\n"

# Collect search terms from command line
for param in "$@"; do
    printf "%s\n" "$param" >>"$ALL_TERMS"
done

printf "==> Searching for:\n"
cat "$ALL_TERMS"
printf "\n"

# Ensure index exists and is up to date
_scraper rebuild-index >/dev/null 2>&1

# Process each search term
allNames=()
while IFS= read -r searchTerm; do
    [[ -z $searchTerm ]] && continue

    if [[ $searchTerm =~ ^tt[0-9]{7,8}$ ]]; then
        tconst="$searchTerm"
    else
        # Search for the title on IMDb
        printf "==> Searching IMDb for \"%s\"...\n" "$searchTerm"
        # Capture stderr so a scraper failure (e.g. a WAF challenge) is
        # reported instead of being silently reinterpreted as "no matches".
        if ! searchResults=$(_scraper --delay 1 search-title "$searchTerm" 2>"$SCRAPER_ERR"); then
            printf "==> Couldn't search IMDb for \"%s\":\n" "$searchTerm"
            tail -n 2 "$SCRAPER_ERR" | sed 's/^/    /'
            continue
        fi
        matchCount=$(jq 'length' <<<"$searchResults" 2>/dev/null)
        matchCount=${matchCount:-0}

        if [[ $matchCount -eq 0 ]]; then
            printf "==> No matches found for \"%s\"\n" "$searchTerm"
            continue
        fi

        if [[ $matchCount -ge 2 ]]; then
            if [[ $matchCount -ge ${maxMenuSize:-25} ]]; then
                if waitUntil "$YN_PREF" -Y "Found $matchCount matches. Skip?"; then
                    continue
                fi
            fi
            printf "\nI found %s matches for \"%s\"\n" "$matchCount" "$searchTerm"

            # Build menu from search results
            jq -r '.[] | "\(.tconst)\t\(.title)\t\(.year // "n/a")\t\(.types | join(", "))"' <<<"$searchResults" >"$TMPFILE"
            pickOptions=()
            tabbedOptions=()
            while IFS= read -r line; do
                pickOptions+=("$line")
            done < <(tsvPrint "$TMPFILE")
            pickOptions+=("Skip \"$searchTerm\"" "Quit")

            while IFS= read -r line; do
                tabbedOptions+=("$line")
            done < <(jq -r '.[] | "\(.tconst)\t\(.title)\t\(.year // "n/a")\t\(.types | join(", "))"' <<<"$searchResults")

            PS3="Select a number from 1-${#pickOptions[@]}, or type 'q(uit)': "
            COLUMNS=40
            select pickMenu in "${pickOptions[@]}"; do
                if [[ $REPLY -ge 1 ]] 2>/dev/null && [[ $REPLY -le ${#pickOptions[@]} ]]; then
                    case "$pickMenu" in
                    Skip*) break ;;
                    Quit) loopOrExitP ;;
                    *)
                        tconst=$(cut -f1 <<<"${tabbedOptions[REPLY - 1]}")
                        break
                        ;;
                    esac
                else
                    case "$REPLY" in [Qq]*) loopOrExitP ;; esac
                fi
            done </dev/tty
            [[ -z $tconst ]] && continue
        else
            tconst=$(jq -r '.[0].tconst' <<<"$searchResults")
        fi
    fi

    # Ensure we have full credits cached; scrape if needed
    # Check both title info AND cast data — title-basics populates the index
    # without cast, so we need to verify cast exists too
    castCheck=$(_scraper cast-for-show "$tconst" 2>/dev/null)
    titleInfo=$(_scraper title-info "$tconst" 2>/dev/null)
    if [[ -z $titleInfo ]] || [[ $titleInfo == *"not found"* ]] || [[ -z $castCheck ]] || [[ $castCheck == "[]" ]]; then
        printf "==> Fetching full credits from IMDb...\n"
        scrapeResult=$(_scraper --delay 1 full-credits "$tconst" 2>&1)
        scrapeRC=$?
        if [[ $scrapeRC -ne 0 ]] || ! echo "$scrapeResult" | jq . >/dev/null 2>&1; then
            printf "==> [${RED}Error${NO_COLOR}] Scraper failed. Make sure Playwright is installed:\n"
            printf "    playwright install chromium\n"
            loopOrExitP
        fi
        _scraper rebuild-index >/dev/null 2>&1
    fi

    showName=$(jq -r '.title' <<<"$(_scraper title-info "$tconst" 2>/dev/null)")
    printf "%s\t%s\n" "$tconst" "$showName" >>"$ALL_MATCHES"
    allNames+=("$showName")

    # Get cast data
    castArgs=("cast-for-show" "$tconst")
    [[ -n $minEpisodes ]] && castArgs+=("--min-episodes" "$minEpisodes")
    # FULLCAST: if numeric, limit displayed cast members
    if [[ -n $FULLCAST ]] && [[ $FULLCAST -eq $FULLCAST ]] 2>/dev/null; then
        castArgs+=("--limit" "$FULLCAST")
    fi
    castData=$(_scraper "${castArgs[@]}" 2>/dev/null)

    # Display cast if not in duplicates-only or short mode
    if [[ -z $MULTIPLE_NAMES_ONLY ]] && [[ -z $SHORT ]]; then
        epLabel=""
        [[ -n $minEpisodes ]] && epLabel=" (minimum ${minEpisodes} episodes)"
        [[ -n $FULLCAST ]] && [[ $FULLCAST -eq $FULLCAST ]] 2>/dev/null && epLabel="$epLabel (top $FULLCAST)"
        printf "==> Cast & crew for \"%s\"%s (Name|Job|Role|Episodes):\n" "$showName" "$epLabel"
        jq -r 'sort_by(-.episodes, .rank) | .[] | "\(.name)\t\(.job)\t\(.character)\t\(.episodes) episodes"' <<<"$castData" >"$TMPFILE"
        if [[ -n $usePager ]]; then
            tsvPrint "$TMPFILE" | ${PAGER:-less}
        else
            tsvPrint "$TMPFILE"
        fi
        waitUntil -k
    fi

    # Accumulate cast TSV for duplicates check across shows
    jq -r '.[] | "\(.name)\t\(.title)\t\t\(.rank | tostring | if length < 2 then ("0" + .) else . end)\t\(.job)\t\(.character)"' <<<"$castData" >>"$CAST_CSV"

done <"$ALL_TERMS"

# Didn't find any results
if [[ ! -s $ALL_MATCHES ]]; then
    printf "\n==> I didn't find ${RED}any${NO_COLOR} matching shows.\n"
    loopOrExitP
fi

# Check for duplicates across multiple shows
if [[ -z $SHORT ]]; then
    numMatches=$(sed -n '$=' "$ALL_MATCHES")
    if [[ $numMatches -ne 1 ]] || [[ -n $MULTIPLE_NAMES_ONLY ]]; then
        # Remove header lines from CAST_CSV before passing to xrefCast
        rg -v "^Person\tShow Title" "$CAST_CSV" >"$TMPFILE" 2>/dev/null || true
        if [[ -s $TMPFILE ]]; then
            if [[ -n $usePager ]]; then
                ./xrefCast.sh -f "$TMPFILE" -dn "${allNames[@]}" | ${PAGER:-less}
            else
                ./xrefCast.sh -f "$TMPFILE" -dn "${allNames[@]}"
            fi
        fi
    else
        printf "\n"
    fi
fi

# Offer to save to favorites
touch "$favoritesFile"

# Save search in case we want to redo or add to favorites
printHistory "$favoritesFile" >"$TMPFILE" 2>/dev/null || true
[[ -n "$(diff "$TMPFILE" "$ALL_MATCHES" 2>/dev/null)" ]] &&
    saveHistory "$ALL_MATCHES" "$favoritesFile"

cut -f1 "$ALL_MATCHES" | sort -u >"$SEARCH_LIST"
rg -IN "^tt" "$favoritesFile" 2>/dev/null | cut -f1 | sort -u >"$TMPFILE" || true
comm -23 "$SEARCH_LIST" "$TMPFILE" >"$NEW_LIST" 2>/dev/null || true

if [[ -s $NEW_LIST ]]; then
    numNew=$(sed -n '$=' "$NEW_LIST")
    _vb="is"
    _pron="it"
    [[ $numNew -gt 1 ]] && plural="s" && _vb="are" && _pron="them"
    printf "==> I found %s show%s that %s not in $favoritesFile\n" "$numNew" "$plural" "$_vb"
    rg -f "$NEW_LIST" "$ALL_MATCHES" >"$TMPFILE" 2>/dev/null || true
    tsvPrint "$TMPFILE"
    if waitUntil "$YN_PREF" -Y "\n==> Shall I add $_pron to $favoritesFile?"; then
        # SC2094 is a false positive: printHistory reads from $histDirectory,
        # not from its argument, so this does not read and write the same file.
        # NOTE: printHistory expects an appendName (a basename suffix), but gets
        # a path here -- worth revisiting whether this appends what's intended.
        # shellcheck disable=SC2094
        printHistory "$favoritesFile" >>"$favoritesFile" 2>/dev/null || true
        ./augment_tconstFiles.sh -ay "$favoritesFile" 2>/dev/null || true
        printf "\n"
    fi
else
    printf "==> All shows are already in $favoritesFile\n"
fi

loopOrExitP
