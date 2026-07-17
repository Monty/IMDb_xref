#!/usr/bin/env bash
#
# Cross-reference saved data using prompts and minimal keystrokes.
# Uses the scraper index instead of .gz-based uniq files.

DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
iQuery.sh -- Cross-reference cached data using prompts and minimal keystrokes.

The index contains all the entities in your cached data files.
Type characters incrementally to select one entity to use as a search term.

Once there is only one possible match, or a low enough number of matches to
select one by number, you can pick it and add it as a search parameter.

USAGE:
    iQuery.sh [OPTIONS...]

OPTIONS:
    -h      Print this message.
    -m      Maximum items to be shown in the search menu. (defaults to 15)

EXAMPLES:
    iQuery.sh
    iQuery.sh -m 30
EOF
}

trap terminate EXIT
TMPFILE=""
SEARCH_TERMS=""

function terminate() {
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
    else
        rm -f "$TMPFILE" "$SEARCH_TERMS"
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
    h) help; exit ;;
    m) maxMenuSize="$OPTARG" ;;
    \?) printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2 ;;
    :) printf "Option -$OPTARG requires an argument.\n" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

maxMenuSize="${maxMenuSize:-15}"

TMPFILE=$(mktemp)
SEARCH_TERMS=$(mktemp)

# Ensure index exists
_scraper rebuild-index >/dev/null 2>&1

# Check if index has data
titleCount=$(_scraper list-titles 2>/dev/null | jq 'length')
personCount=$(_scraper list-persons-index 2>/dev/null | jq 'length')

if [[ "$titleCount" -eq 0 ]] && [[ "$personCount" -eq 0 ]]; then
    printf "\n==> No cached data found. Search for some shows first:\n"
    printf "    ./findCastOf.sh \"The Crown\"\n\n"
    loopOrExitP
fi

printf "==> Cached data: %s titles, %s persons\n\n" "$titleCount" "$personCount"

# Function to do incremental search on an index file
_incremental_search() {
    local indexFile="$1"
    local label="$2"

    while true; do
        read -r -p "Type to search ($label): " input
        [[ -z $input ]] && continue

        _scraper query "$input" --index-file "$indexFile" 2>/dev/null >"$TMPFILE"
        local data
        data=$(cat "$TMPFILE")
        local matchCount
        matchCount=$(jq 'length' <<<"$data")

        if [[ "$matchCount" -eq 0 ]]; then
            printf "  No matches for \"%s\"\n" "$input"
            continue
        fi

        if [[ "$matchCount" -eq 1 ]]; then
            echo "$data"
            return 0
        fi

        if [[ "$matchCount" -le $maxMenuSize ]]; then
            printf "  Found %s matches:\n" "$matchCount"
            jq -r '.[] | "    \(.tconst // .nconst)\t\(.title // .name)"' <<<"$data" | tsvPrint

            local pickOptions=()
            local tabbedOptions=()
            while IFS= read -r line; do
                pickOptions+=("$line")
            done < <(jq -r '.[] | "\(.tconst // .nconst)\t\(.title // .name)"' <<<"$data" | tsvPrint)
            pickOptions+=("Keep typing" "Quit")

            while IFS= read -r line; do
                tabbedOptions+=("$line")
            done < <(jq -r '.[] | "\(.tconst // .nconst)\t\(.title // .name)"' <<<"$data")

            PS3="Select (1-${#pickOptions[@]}): "
            select pickMenu in "${pickOptions[@]}"; do
                if [[ $REPLY -ge 1 ]] 2>/dev/null && [[ $REPLY -le ${#pickOptions[@]} ]]; then
                    case "$pickMenu" in
                    "Keep typing") break ;;
                    "Quit") return 2 ;;
                    *)
                        local id name
                        id=$(cut -f1 <<<"${tabbedOptions[REPLY - 1]}")
                        name=$(cut -f2 <<<"${tabbedOptions[REPLY - 1]}")
                        printf '{"id":"%s","name":"%s"}' "$id" "$name"
                        return 0
                        ;;
                    esac
                else
                    case "$REPLY" in [Qq]*) return 2 ;; esac
                fi
            done </dev/tty
        else
            printf "  %s matches — keep typing\n" "$matchCount"
        fi
    done
}

# Main loop
while true; do
    printf "\n==> Search for a:\n"
    pickOptions=("Show title" "Person name" "Done searching")
    PS3="Select (1-${#pickOptions[@]}): "
    select pickMenu in "${pickOptions[@]}"; do
        case "$pickMenu" in
        "Show title") searchType="titles.jsonl"; break ;;
        "Person name") searchType="persons.jsonl"; break ;;
        "Done searching") searchType="done"; break ;;
        *) continue ;;
        esac
    done </dev/tty

    [[ "$searchType" == "done" ]] && break

    result=$(_incremental_search "$searchType" "$searchType")
    rc=$?
    if [[ $rc -eq 2 ]]; then
        loopOrExitP
    fi

    selectedId=$(jq -r '.id // empty' <<<"$result" 2>/dev/null)
    selectedName=$(jq -r '.name // empty' <<<"$result" 2>/dev/null)

    # If result is a JSON array (single match), parse differently
    if [[ -z $selectedId ]]; then
        selectedId=$(jq -r '.[0].tconst // .[0].nconst // empty' <<<"$result" 2>/dev/null)
        selectedName=$(jq -r '.[0].title // .[0].name // empty' <<<"$result" 2>/dev/null)
    fi

    if [[ -n $selectedId ]]; then
        printf "  Selected: %s (%s)\n" "$selectedName" "$selectedId"
        printf "%s\n" "$selectedId" >>"$SEARCH_TERMS"
    fi
done

# Run the cross-reference
if [[ ! -s $SEARCH_TERMS ]]; then
    printf "\n==> No search terms selected.\n"
    loopOrExitP
fi

printf "\n==> Running cross-reference for:\n"
cat "$SEARCH_TERMS"
printf "\n"

./xrefCast.sh -n $(cat "$SEARCH_TERMS")

loopOrExitP
