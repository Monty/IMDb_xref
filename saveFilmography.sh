#!/usr/bin/env bash
#
# Save a filmography for a named person in IMDb
# Uses the Playwright-based scraper.

DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
saveFilmography.sh -- Save a filmography for a named person in IMDb.

Search IMDb for person names or nconst IDs. An nconst ID should be unique,
but a person name can have several or even many matches. Allow user to
select one match or skip if there are too many.

Filmographies are saved as JSON in secondary/filmographies/. You'll have the
opportunity to review results before committing.

If you don't enter a parameter on the command line, you'll be prompted for
input.

USAGE:
    ./saveFilmography.sh [NCONST...] [PERSON NAME...]

OPTIONS:
    -h      Print this message.
    -m      Maximum matches for a person name allowed in menu - defaults to 10

EXAMPLES:
    ./saveFilmography.sh
    ./saveFilmography.sh "George Clooney"
    ./saveFilmography.sh nm0000123
    ./saveFilmography.sh nm0000123 "Quentin Tarantino"
EOF
}

trap terminate EXIT
ALL_TERMS=""
PERSON_RESULTS=""
NCONST_TERMS=""
TMPFILE=""
FILMOGRAPHY_JSON=""

function terminate() {
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
    else
        rm -f "$ALL_TERMS" "$PERSON_RESULTS" "$NCONST_TERMS" "$TMPFILE" "$FILMOGRAPHY_JSON"
    fi
}

trap cleanup INT
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

_scraper() {
    uv run --directory scraper python cli.py "$@"
}

while getopts ":hm:" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    m) maxMenuSize="$OPTARG" ;;
    \?) printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2 ;;
    :)
        printf "==> Option -$OPTARG requires an argument.\n" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

ALL_TERMS=$(mktemp)
PERSON_RESULTS=$(mktemp)
NCONST_TERMS=$(mktemp)
TMPFILE=$(mktemp)
FILMOGRAPHY_JSON=$(mktemp)

# Make sure a search term is supplied
if [[ $# -eq 0 ]]; then
    cat <<EOF
==> I can generate a filmography based on a person's name or nconst ID,
    such as nm0000123 for George Clooney:
    https://www.imdb.com/name/nm0000123/

Only one search term per line. Enter a blank line to finish.
EOF
    while read -r -p "Enter a person name or nconst ID: " searchTerm; do
        [[ -z $searchTerm ]] && break
        tr -ds '"' '[:space:]' <<<"$searchTerm" >>"$ALL_TERMS"
    done </dev/tty
    if [[ ! -s $ALL_TERMS ]]; then
        if waitUntil "$YN_PREF" -N \
            "Would you like me to generate a George Clooney filmography as an example?"; then
            printf "nm0000123\n" >>"$ALL_TERMS"
        else
            loopOrExitP
        fi
    fi
    printf "\n"
fi

for param in "$@"; do
    printf "%s\n" "$param" >>"$ALL_TERMS"
done

printf "==> Searching for:\n"
cat "$ALL_TERMS"
printf "\n"

# Process each search term
while IFS= read -r searchTerm; do
    [[ -z $searchTerm ]] && continue

    if [[ $searchTerm =~ ^nm[0-9]{7,8}$ ]]; then
        nconst="$searchTerm"
        personInfo=$(_scraper person-info "$nconst" 2>/dev/null)
        if [[ -n $personInfo ]] && [[ $personInfo != *"not found"* ]]; then
            nconstName=$(jq -r '.name // empty' <<<"$personInfo")
            printf "%s\t%s\n" "$nconst" "$nconstName" >>"$PERSON_RESULTS"
        fi
    else
        # Search for the person on IMDb
        printf "==> Searching IMDb for \"%s\"...\n" "$searchTerm"
        searchResults=$(_scraper --delay 1 search-person "$searchTerm" 2>/dev/null)
        matchCount=$(jq 'length' <<<"$searchResults")

        if [[ $matchCount -eq 0 ]]; then
            printf "==> No matches found for \"%s\"\n" "$searchTerm"
            continue
        fi

        if [[ $matchCount -ge 2 ]]; then
            if [[ $matchCount -ge ${maxMenuSize:-10} ]]; then
                if waitUntil "$YN_PREF" -Y "Found $matchCount matches. Skip?"; then
                    continue
                fi
            fi
            printf "\nI found %s people named \"%s\"\n" "$matchCount" "$searchTerm"

            jq -r '.[] | "\(.nconst)\t\(.name)"' <<<"$searchResults" >"$TMPFILE"
            pickOptions=()
            tabbedOptions=()
            while IFS= read -r line; do
                pickOptions+=("$line")
            done < <(tsvPrint "$TMPFILE")
            pickOptions+=("Skip \"$searchTerm\"" "Quit")

            while IFS= read -r line; do
                tabbedOptions+=("$line")
            done < <(jq -r '.[] | "\(.nconst)\t\(.name)"' <<<"$searchResults")

            PS3="Select (1-${#pickOptions[@]}): "
            COLUMNS=40
            select pickMenu in "${pickOptions[@]}"; do
                if [[ $REPLY -ge 1 ]] 2>/dev/null && [[ $REPLY -le ${#pickOptions[@]} ]]; then
                    case "$pickMenu" in
                    Skip*) break ;;
                    Quit) loopOrExitP ;;
                    *)
                        nconst=$(cut -f1 <<<"${tabbedOptions[REPLY - 1]}")
                        nconstName=$(cut -f2 <<<"${tabbedOptions[REPLY - 1]}")
                        break
                        ;;
                    esac
                else
                    case "$REPLY" in [Qq]*) loopOrExitP ;; esac
                fi
            done </dev/tty
            [[ -z $nconst ]] && continue
            printf "%s\t%s\n" "$nconst" "$nconstName" >>"$PERSON_RESULTS"
        else
            nconst=$(jq -r '.[0].nconst' <<<"$searchResults")
            nconstName=$(jq -r '.[0].name' <<<"$searchResults")
            printf "%s\t%s\n" "$nconst" "$nconstName" >>"$PERSON_RESULTS"
        fi
    fi

    # Fetch filmography if not cached
    fgData=$(_scraper filmography "$nconst" 2>/dev/null)
    roleCount=$(jq '.roles | length' <<<"$fgData")

    if [[ $roleCount -eq 0 ]]; then
        printf "==> Fetching filmography from IMDb...\n"
        _scraper --delay 1 filmography "$nconst" >/dev/null 2>&1
        fgData=$(_scraper filmography "$nconst" 2>/dev/null)
        roleCount=$(jq '.roles | length' <<<"$fgData")
    fi

    if [[ $roleCount -eq 0 ]]; then
        printf "\n==> No filmography found for %s.\n" "$nconstName"
        continue
    fi

    # Display summary
    noSpaceName="${nconstName//[[:space:]]/_}"
    filmographyDir="secondary/filmographies"
    mkdir -p "$filmographyDir"

    printf "\n==> Filmography for %s (%s roles)\n" "$nconstName" "$roleCount"

    # Group by job
    jobs=$(jq -r '[.[].job] | unique | .[]' <<<"$fgData")
    while IFS= read -r job; do
        [[ -z $job ]] && continue
        jobCount=$(jq --arg j "$job" '[.roles[] | select(.job == $j)] | length' <<<"$fgData")
        [[ $jobCount -eq 0 ]] && continue
        printf "  %-20s %s titles\n" "$job:" "$jobCount"
    done <<<"$jobs"

    # Offer to save
    filmographyFile="$filmographyDir/${noSpaceName}-${nconst}.json"
    printf "\n==> Save to ${BLUE}$filmographyFile${NO_COLOR}?\n"
    if waitUntil "$YN_PREF" -Y "==> Save filmography?"; then
        echo "$fgData" >"$filmographyFile"
        printf "==> Saved.\n"
    fi

    # Offer to add titles to tconst file
    tconsts=$(jq -r '[.roles[].tconst] | unique | .[]' <<<"$fgData")
    tconstCount=$(echo "$tconsts" | rg -c "^tt")
    printf "\n==> This filmography includes %s unique titles.\n" "$tconstCount"

done <"$ALL_TERMS"

loopOrExitP
