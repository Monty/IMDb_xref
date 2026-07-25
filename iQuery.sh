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
Type a search string and press Enter to find shows, persons, or characters.

When multiple matches are found, select from the menu. Add multiple search
terms and run a full or duplicates-only cross-reference.

USAGE:
    iQuery.sh [OPTIONS...]

OPTIONS:
    -h      Print this message.
    -l      Use $PAGER to list results a page at a time.
    -m      Maximum items to be shown in the search menu. (defaults to 15)

EXAMPLES:
    iQuery.sh
    iQuery.sh -l
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

while getopts ":hlm:" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    m) maxMenuSize="$OPTARG" ;;
    l) usePager=1 ;;
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
charFile=".xref_index/characters.jsonl"
charCount=0
[[ -f $charFile ]] && charCount=$(rg -c '.' "$charFile" 2>/dev/null || echo 0)

if [[ $titleCount -eq 0 ]] && [[ $personCount -eq 0 ]]; then
    printf "\n==> No cached data found. Search for some shows first:\n"
    printf "    ./findCastOf.sh \"The Crown\"\n\n"
    loopOrExitP
fi

printf "==> Cached data: %s titles, %s persons, %s characters\n\n" "$titleCount" "$personCount" "$charCount"

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

            # Build display format based on index type
            local jqFormat dedupData="$data"
            if [[ $indexFile == *characters* ]]; then
                # Deduplicate: keep first occurrence of each unique character
                dedupData=$(jq '[group_by(.character) | .[] | .[0]]' <<<"$data")
                jqFormat='\(.character)'
            else
                jqFormat='\(.tconst // .nconst)\t\(.title // .name)'
            fi

            jq -r ".[] | \"$jqFormat\"" <<<"$dedupData" >"$TMPFILE"

            local pickOptions=()
            local tabbedOptions=()
            while IFS= read -r line; do
                pickOptions+=("$line")
            done < <(tsvPrint "$TMPFILE")
            pickOptions+=("Keep typing")

            while IFS= read -r line; do
                tabbedOptions+=("$line")
            done < <(jq -r ".[] | \"$jqFormat\"" <<<"$dedupData")

            PS3="Select (1-${#pickOptions[@]}): "
            # pickMenu is unused: this select matches on $REPLY against the
            # parallel tabbedOptions array, not on the chosen label.
            # shellcheck disable=SC2034
            select pickMenu in "${pickOptions[@]}"; do
                if [[ $REPLY -ge 1 ]] 2>/dev/null && [[ $REPLY -le ${#pickOptions[@]} ]]; then
                    if [[ $REPLY -le ${#tabbedOptions[@]} ]]; then
                        local id name
                        name=$(cut -f1 <<<"${tabbedOptions[REPLY - 1]}")
                        id="$name"
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
searchNames=() # parallel array of display names
searchString=""

# Intro text
cat <<EOF

"Add a show" to list every person in a show. "Add a person" to see every show
they were in. "Add a character" to see everyone who portrayed that character.
Add multiple people to see all the shows they were in together. Add multiple
shows to see if any people were in more than one. You can add more search terms
after executing the search, or switch from a full search to a 'duplicates only'
search.

EOF

# Main loop
while true; do
    printf "\n==> What would you like to do?\n"

    searchType=""
    actionOptions=("Add a show to search for" "Add a person to search for" "Add a character to search for")

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
        List*)
            if [[ -n $usePager ]]; then
                _scraper list-titles 2>/dev/null | jq -r '.[].title' | sort -df | ${PAGER:-less}
            else
                _scraper list-titles 2>/dev/null | jq -r '.[].title' | sort -df
            fi
            break
            ;;
        *show*)
            searchType="titles.jsonl"
            break
            ;;
        *person*)
            searchType="persons.jsonl"
            break
            ;;
        *character*)
            searchType="characters.jsonl"
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
            if [[ -n $usePager ]]; then
                ./xrefCast.sh -n "${searchArray[@]}" | ${PAGER:-less}
            else
                ./xrefCast.sh -n "${searchArray[@]}"
            fi
            continue 2
            ;;
        *duplicates*)
            printf "\n==> Running duplicates-only search for:\n"
            printf "%s\n" "${searchArray[@]}"
            printf "\n"
            if [[ -n $usePager ]]; then
                ./xrefCast.sh -dn "${searchArray[@]}" | ${PAGER:-less}
            else
                ./xrefCast.sh -dn "${searchArray[@]}"
            fi
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

    [[ -z $searchType ]] && continue

    result=$(_incremental_search "$searchType" "$searchType")
    rc=$?
    if [[ $rc -eq 2 ]]; then
        loopOrExitP
    fi

    selectedId=$(jq -r '.id // empty' <<<"$result" 2>/dev/null)
    selectedName=$(jq -r '.name // empty' <<<"$result" 2>/dev/null)

    # If result is a JSON array (single match), parse differently
    if [[ -z $selectedId ]]; then
        if [[ $searchType == *characters* ]]; then
            selectedId=$(jq -r '.[0].character // empty' <<<"$result" 2>/dev/null)
            selectedName="$selectedId"
        else
            selectedId=$(jq -r '.[0].tconst // .[0].nconst // empty' <<<"$result" 2>/dev/null)
            selectedName=$(jq -r '.[0].title // .[0].name // empty' <<<"$result" 2>/dev/null)
        fi
    fi

    if [[ -n $selectedId ]]; then
        # Check not already in array
        alreadyIn=0
        for existingId in "${searchArray[@]}"; do
            [[ $existingId == "$selectedId" ]] && alreadyIn=1 && break
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
