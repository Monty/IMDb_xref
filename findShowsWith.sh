#!/usr/bin/env bash
#
# List all shows found for a named person in IMDb.
# Uses the Playwright-based scraper instead of .gz database files.

DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
findShowsWith.sh -- List shows found for a named person in IMDb.

Search IMDb for person names or nconst IDs. An nconst ID should be unique,
but a person name can have several or even many matches. Allow user to
select one match or skip if there are too many.

If you don't enter a parameter on the command line, you'll be prompted for input.

USAGE:
    ./findShowsWith.sh [NCONST...] [PERSON NAME...]

OPTIONS:
    -h      Print this message.
    -m      Maximum matches for a person name allowed in menu - defaults to 10
    -y      Yes -- assume the answer to job category prompts is "Y".

EXAMPLES:
    ./findShowsWith.sh
    ./findShowsWith.sh -y "Tom Hanks"
    ./findShowsWith.sh "George Clooney"
    ./findShowsWith.sh nm0000123
    ./findShowsWith.sh nm0000123 "Quentin Tarantino"
EOF
}

# Don't leave tempfiles around
trap terminate EXIT
TMPFILE=""
ALL_TERMS=""
PERSON_RESULTS=""
NCONST_TERMS=""

function terminate() {
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
    else
        rm -f "$ALL_TERMS" "$PERSON_RESULTS" "$NCONST_TERMS" "$TMPFILE"
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

while getopts ":hm:y" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    m) maxMenuSize="$OPTARG" ;;
    y) skipPrompts="yes" ;;
    \?) printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2 ;;
    :)
        printf "Option -$OPTARG requires an argument.\n" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

ALL_TERMS=$(mktemp)
PERSON_RESULTS=$(mktemp)
NCONST_TERMS=$(mktemp)
TMPFILE=$(mktemp)

# Make sure a search term is supplied
if [[ $# -eq 0 ]]; then
    cat <<EOF
==> I can find all shows listing a person as principal cast or crew
    based on their name or nconst ID, such as nm0000123 -- which is
    George Clooney from: https://www.imdb.com/name/nm0000123/

Only one search term per line. Enter a blank line to finish.
EOF
    while read -r -p "Enter a person's name or nconst ID: " searchTerm; do
        [[ -z $searchTerm ]] && break
        tr -ds '"' '[:space:]' <<<"$searchTerm" >>"$ALL_TERMS"
    done </dev/tty
    if [[ ! -s $ALL_TERMS ]]; then
        if waitUntil "$YN_PREF" -N \
            "Would you like to see all shows listing George Clooney as an example?"; then
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
        # Get name from index
        personInfo=$(_scraper person-info "$nconst" 2>/dev/null)
        if [[ -z $personInfo ]] || [[ $personInfo == *"not found"* ]]; then
            # Scrape filmography
            _scraper --delay 1 filmography "$nconst" >/dev/null 2>&1
            _scraper rebuild-index >/dev/null 2>&1
            personInfo=$(_scraper person-info "$nconst" 2>/dev/null)
        fi
        nconstName=$(jq -r '.name // empty' <<<"$personInfo")
        [[ -n $nconstName ]] && printf "%s\t%s\n" "$nconst" "$nconstName" >>"$PERSON_RESULTS"
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

            pickOptions=()
            tabbedOptions=()
            while IFS= read -r line; do
                pickOptions+=("$line")
            done < <(jq -r '.[] | "  \(.nconst)\t\(.name)"' <<<"$searchResults" | tsvPrint)
            pickOptions+=("Skip \"$searchTerm\"" "Quit")

            while IFS= read -r line; do
                tabbedOptions+=("$line")
            done < <(jq -r '.[] | "\(.nconst)\t\(.name)"' <<<"$searchResults")

            PS3="Select a number from 1-${#pickOptions[@]}, or type 'q(uit)': "
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

done <"$ALL_TERMS"

# Didn't find any results
if [[ ! -s $PERSON_RESULTS ]]; then
    printf "\n==> I didn't find ${RED}any${NO_COLOR} matching persons.\n"
    loopOrExitP
fi

# Found results, show them
printf "\nFound:\n"
tsvPrint "$PERSON_RESULTS"
printf "\n"

# For each person, get their filmography
while IFS=$'\t' read -r nconst nconstName; do
    [[ -z $nconst ]] && continue

    # Get shows from index (cached filmography)
    showsData=$(_scraper shows-for-person "$nconst" 2>/dev/null)
    showCount=$(jq 'length' <<<"$showsData")

    if [[ $showCount -eq 0 ]]; then
        # Try scraping filmography
        printf "==> Fetching filmography for %s...\n" "$nconstName"
        _scraper --delay 1 filmography "$nconst" >/dev/null 2>&1
        _scraper rebuild-index >/dev/null 2>&1
        showsData=$(_scraper shows-for-person "$nconst" 2>/dev/null)
        showCount=$(jq 'length' <<<"$showsData")
    fi

    if [[ $showCount -eq 0 ]]; then
        printf "\n==> No shows found for %s.\n" "$nconstName"
        continue
    fi

    # Group by job and display
    jobs=$(jq -r '[.[].job] | unique | .[]' <<<"$showsData")
    while IFS= read -r job; do
        [[ -z $job ]] && continue
        jobData=$(jq --arg j "$job" '[.[] | select(.job == $j)]' <<<"$showsData")
        jobCount=$(jq 'length' <<<"$jobData")
        if [[ $jobCount -eq 0 ]]; then
            continue
        fi

        _title="title"
        _pron="it"
        [[ $jobCount -gt 1 ]] && _title="titles" && _pron="them"
        printf "\n==> I found %s %s listing %s as: %s\n" "$jobCount" "$_title" "$nconstName" "$job"

        if [[ -n $skipPrompts ]] || waitUntil "$YN_PREF" -Y "==> Shall I list $_pron?"; then
            jq -r 'sort_by(-.episodes, .title) | .[] | "\(.title)\t\(.episodes | if . > 0 then ("\(.episodes) episodes") else "" end)\t\(.character // "")"' <<<"$jobData" |
                tsvPrint
        fi
    done <<<"$jobs"

done <"$PERSON_RESULTS"

loopOrExitP
