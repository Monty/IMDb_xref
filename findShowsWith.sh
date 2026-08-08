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
findShowsWith.sh -- List indexed shows a person appears in.

Searches your local index -- the shows you've already cross-referenced -- for
a person and lists which of them they appear in, grouped by job. This answers
"what else, among the shows I follow, has this person been in?".

Search by nconst ID (unique) or by name (IMDb is queried to resolve the name
to candidates; the show data itself is read only from the local index). A
person not yet in the index produces no results -- run ./findCastOf.sh on a
show they're in to add it, or use ./saveFilmography.sh for their full IMDb
filmography.

If you don't enter a parameter on the command line, you'll be prompted for input.

USAGE:
    ./findShowsWith.sh [NCONST...] [PERSON NAME...]

OPTIONS:
    -h      Print this message.
    -l      Use $PAGER to list results a page at a time.
    -m      Maximum matches for a person name allowed in menu - defaults to 10
    -y      Yes -- assume the answer to job category prompts is "Y".

EXAMPLES:
    ./findShowsWith.sh
    ./findShowsWith.sh -y "Olivia Colman"
    ./findShowsWith.sh "Pedro Alonso"
    ./findShowsWith.sh nm0022261
    ./findShowsWith.sh nm0022261 "Úrsula Corberó"
EOF
}

# Don't leave tempfiles around
trap terminate EXIT
TMPFILE=""
ALL_TERMS=""
PERSON_RESULTS=""
NCONST_TERMS=""
SCRAPER_ERR=""

function terminate() {
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
    else
        rm -f "$ALL_TERMS" "$PERSON_RESULTS" "$NCONST_TERMS" "$TMPFILE" "$SCRAPER_ERR"
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

while getopts ":hlm:y" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    l) usePager=1 ;;
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
SCRAPER_ERR=$(mktemp)

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
        # Local lookup only: resolve the name from the index. A person is
        # indexed if they appear in any cached show (or cached filmography).
        # We deliberately do not scrape a missing person here -- this tool
        # answers "which shows I already have is this person in?". Use
        # saveFilmography.sh for a full IMDb filmography.
        personInfo=$(_scraper person-info "$nconst" 2>/dev/null)
        # person-info prints a plain-text "not found" message (not JSON) when
        # the nconst is absent, so guard jq against parsing it.
        if [[ -n $personInfo ]] && [[ $personInfo != *"not found"* ]]; then
            nconstName=$(jq -r '.name // empty' <<<"$personInfo")
        else
            nconstName=""
        fi
        if [[ -n $nconstName ]]; then
            printf "%s\t%s\n" "$nconst" "$nconstName" >>"$PERSON_RESULTS"
        else
            printf "==> %s isn't in the index. Run ./findCastOf.sh on a show they're in, or use ./saveFilmography.sh %s\n" "$nconst" "$nconst"
        fi
    else
        # Search for the person on IMDb
        printf "==> Searching IMDb for \"%s\"...\n" "$searchTerm"
        # Capture stderr so a scraper failure (e.g. a WAF challenge) is
        # reported instead of being silently reinterpreted as "no matches".
        if ! searchResults=$(_scraper --delay 1 search-person "$searchTerm" 2>"$SCRAPER_ERR"); then
            reportSearchError "$searchTerm" "$SCRAPER_ERR"
            continue
        fi
        matchCount=$(jq 'length' <<<"$searchResults" 2>/dev/null)
        matchCount=${matchCount:-0}

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

# Found results, confirm before processing (mirrors big_IMDb_xref's gate).
printf "\nThese are the results I can process:\n"
tsvPrint "$PERSON_RESULTS"
if ! waitUntil "$YN_PREF" -Y "Does that look correct?"; then
    loopOrExitP
fi
printf "\n"

# For each person, list the indexed shows they appear in
while IFS=$'\t' read -r nconst nconstName; do
    [[ -z $nconst ]] && continue

    # Get shows from the index (built from cached shows and filmographies).
    showsData=$(_scraper shows-for-person "$nconst" 2>/dev/null)
    showCount=$(jq 'length' <<<"$showsData")

    if [[ $showCount -eq 0 ]]; then
        # Local only: don't scrape. The person resolved to a name but has no
        # cross-referenced shows in the index yet.
        printf "\n==> No indexed shows for %s. Run ./findCastOf.sh on a show they're in, or use ./saveFilmography.sh %s\n" "$nconstName" "$nconst"
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
            jq -r 'sort_by(-(.episodes // 0), .title) | .[] | "\(.title)\t\((.episodes // 0) | if . > 0 then "\(.) episodes" else "" end)\t\(.character // "")\t\(.tconst // "")"' <<<"$jobData" >"$TMPFILE"
            if [[ -n $usePager ]]; then
                tsvPrint "$TMPFILE" | ${PAGER:-less}
            else
                tsvPrint "$TMPFILE"
            fi
        fi
    done <<<"$jobs"

done <"$PERSON_RESULTS"

loopOrExitP
