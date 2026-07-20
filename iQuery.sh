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

function terminate() {
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
    else
        rm -f "$TMPFILE"
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
        printf "Option -$OPTARG requires an argument.\n" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

maxMenuSize="${maxMenuSize:-15}"

TMPFILE=$(mktemp)

# Ensure index exists
_scraper rebuild-index >/dev/null 2>&1

# Check if index has data
titleCount=$(_scraper list-titles 2>/dev/null | jq 'length')
personCount=$(_scraper list-persons-index 2>/dev/null | jq 'length')

if [[ $titleCount -eq 0 ]] && [[ $personCount -eq 0 ]]; then
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

        if [[ $matchCount -eq 0 ]]; then
            printf "  No matches for \"%s\"\n" "$input" >&2
            continue
        fi

        if [[ $matchCount -eq 1 ]]; then
            echo "$data"
            return 0
        fi

        if [[ $matchCount -le $maxMenuSize ]]; then
            printf "  Found %s matches:\n" "$matchCount" >&2
            jq -r '.[] | "\(.tconst // .nconst)\t\(.title // .name)"' <<<"$data" >"$TMPFILE"

            local pickOptions=()
            local tabbedOptions=()
            while IFS= read -r line; do
                pickOptions+=("$line")
            done < <(tsvPrint "$TMPFILE")
            pickOptions+=("Keep typing")

            while IFS= read -r line; do
                tabbedOptions+=("$line")
            done < <(jq -r '.[] | "\(.tconst // .nconst)\t\(.title // .name)"' <<<"$data")

            PS3="Select (1-${#pickOptions[@]}): "
            select pickMenu in "${pickOptions[@]}"; do
                if [[ $REPLY -ge 1 ]] 2>/dev/null && [[ $REPLY -le ${#pickOptions[@]} ]]; then
                    if [[ $REPLY -le ${#tabbedOptions[@]} ]]; then
                        local id name
                        id=$(cut -f1 <<<"${tabbedOptions[REPLY - 1]}")
                        name=$(cut -f2 <<<"${tabbedOptions[REPLY - 1]}")
                        printf '{"id":"%s","name":"%s"}' "$id" "$name"
                        return 0
                    else
                        # "Keep typing"
                        break
                    fi
                else
                    case "$REPLY" in [Qq]*) return 2 ;; esac
                fi
            done </dev/tty
        else
            printf "  %s matches — keep typing\n" "$matchCount"
        fi
    done
}

# Build search arrays
searchArray=()
searchNames=()  # parallel array of display names
searchString=""

# Intro text
cat <<EOF

"Add a show" to list every person in a show. "Add a person" to see every show
they were in. Add multiple people to see all the shows they were in together.
Add multiple shows to see if any people were in more than one. You can add more
search terms after executing the search, or switch from a full search to a
'duplicates only' search.

EOF

# Main loop
while true; do
    printf "\n==> What would you like to do?\n"

    actionOptions=("Add a show to search for" "Add a person to search for")

    searchArraySize="${#searchArray[@]}"
    [[ $searchArraySize -eq 1 ]] && actionOptions+=("Remove search term")
    [[ $searchArraySize -gt 1 ]] &&
        actionOptions+=("Remove one search term" "Delete all search terms")
    [[ $searchArraySize -gt 0 ]] &&
        actionOptions+=("Run full search" "Run 'duplicates only' search")
    actionOptions+=("List all shows" "Quit")

    PS3="Select (1-${#actionOptions[@]}), or type 'q(uit)': "
    COLUMNS=80
    select actionMenu in "${actionOptions[@]}"; do
        printf "\n"
        case "$actionMenu" in
        *show*)
            searchType="titles.jsonl"
            break
            ;;
        *person*)
            searchType="persons.jsonl"
            break
            ;;
        *one*)
            # Remove one search term
            PS3="Select (1-$searchArraySize), or enter '0' to skip: "
            select deleteMenu in "${searchNames[@]}"; do
                if [[ $REPLY -ge 1 ]] 2>/dev/null && [[ $REPLY -le ${#searchNames[@]} ]]; then
                    printf "Removing: \"%s\"\n" "$deleteMenu"
                    ((REPLY--)) || true
                    tempIds=("${searchArray[@]}")
                    tempNames=("${searchNames[@]}")
                    searchArray=()
                    searchNames=()
                    searchString=""
                    for i in "${!tempIds[@]}"; do
                        if [[ $i -ne $REPLY ]]; then
                            searchArray+=("${tempIds[$i]}")
                            searchNames+=("${tempNames[$i]}")
                            searchString+="\"${tempNames[$i]}\" "
                        fi
                    done
                    break
                else
                    case "$REPLY" in 0) break ;; esac
                fi
            done </dev/tty
            [[ -n $searchString ]] && printf "\nSearch terms: %s\n" "$searchString"
            continue 2
            ;;
        Remove*)
            # Remove the only search term
            printf "Removing %s\n" "$searchString"
            searchArray=()
            searchNames=()
            searchString=""
            continue 2
            ;;
        Delete*)
            printf "Deleting all search terms...\n"
            searchArray=()
            searchNames=()
            searchString=""
            continue 2
            ;;
        *full*)
            printf "\n==> Running cross-reference for:\n"
            printf "%s\n" "${searchArray[@]}"
            printf "\n"
            ./xrefCast.sh -n "${searchArray[@]}"
            continue 2
            ;;
        *duplicates*)
            printf "\n==> Running duplicates-only search for:\n"
            printf "%s\n" "${searchArray[@]}"
            printf "\n"
            ./xrefCast.sh -dn "${searchArray[@]}"
            continue 2
            ;;
        List*)
            _scraper list-titles 2>/dev/null | jq -r '.[]' | sort -df
            continue 2
            ;;
        Quit)
            loopOrExitP
            ;;
        "")
            case "$REPLY" in [Qq]*) loopOrExitP ;; esac
            continue
            ;;
        esac
    done </dev/tty

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
        # Check not already in array
        alreadyIn=0
        for existingId in "${searchArray[@]}"; do
            [[ "$existingId" == "$selectedId" ]] && alreadyIn=1 && break
        done

        if [[ $alreadyIn -eq 0 ]]; then
            searchArray+=("$selectedId")
            searchNames+=("$selectedName")
            searchString+="\"${selectedName}\" "
            printf "\n  Selected: %s (%s)\n" "$selectedName" "$selectedId"
        else
            printf "\n  Already in search: %s (%s)\n" "$selectedName" "$selectedId"
        fi
        [[ -n $searchString ]] && printf "Search terms: %s\n" "$searchString"
    fi
done
