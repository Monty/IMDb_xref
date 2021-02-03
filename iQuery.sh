#!/usr/bin/env bash
#
# Interactively generate and run queries for xrefCast
#
# Type characters incrementally to generate and run queries

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
iQuery.sh -- Cross-reference known data using prompts and minimal keystrokes.

The files uniqTitles.txt, uniqPersons.txt, and uniqCharacters.txt contain all
known entities that are already in your database. Type characters incrementally
to select one entity to use as a search term for xrefCast.

Once there are no possible matches, only one possible match, or a low enough
number of matches to select one by number; ask user to select possible actions
-- including adding the match as an xrefCast search parameter.

Minimizes the number of keystrokes required to obtain a search term with a
guaranteed match, e.g. 'Hi' returns 'Tom Hiddleston' to use when when searching
for people in the initial database.

USAGE:
    iQuery.sh [OPTIONS...]

OPTIONS:
    -h      Print this message.
    -m      Maximum hits allowed in the selection menu. Continue typing until
            there are fewer hits. (defaults to 10)

EXAMPLES:
    iQuery.sh
    iQuery.sh -m 30
EOF
}

# Don't leave tempfiles around
trap terminate EXIT
#
function terminate() {
    if [ -n "$DEBUG" ]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
    fi
}

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

while getopts ":hm:" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    m)
        maxHits="$OPTARG"
        ;;
    \?)
        printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2
        ;;
    :)
        printf "==> Option -$OPTARG requires a 'maximim hits' argument.'\n\n" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

# Make sure prerequisites are satisfied
ensurePrerequisites

# Setup search files and corresponding categories
uniqFiles=('uniqTitles.txt' 'uniqPersons.txt' 'uniqCharacters.txt')
categories=('show' 'person' 'character')

[ ! -e "Credits-Person.csv" ] && ensureDataFiles

# Check for uniq* files
foundSizes=()
foundCategories=()
missingCategories=()
categoryOptions=()
idx=0
for file in "${uniqFiles[@]}"; do
    if [ -e "$file" ]; then
        numFound="$(sed -n '$=' "$file")"
        foundSizes+=("$numFound" "${categories[$idx]}s,")
        foundCategories+=("${categories[$idx]}")
        categoryOptions+=("Add a ${categories[$idx]} to search for")
    else
        missingCategories+=("${categories[$idx]}")
    fi
    ((idx++)) || true
done

# If we don't have any data...
if [ "${#missingCategories[@]}" -gt 0 ]; then
    ensureDataFiles
    exec ./iQuery.sh
fi

# Let user know how much data we're dealing with
sizeStr="${foundSizes[*]}"
cat <<EOF
==> I can generate searches based on ${sizeStr/%,/.}

"Add a show" to list every person in a show. "Add a person" to see every show
they were in. "Add a character" to see everyone who portrayed that character.
Add multiple people to see all the shows they were in together. Add multiple
shows to see if any people were in more than one. You can add more search terms
after executing the search, or switch from a full search to a 'multiples only'
search.

As soon as you type enough characters, a proposed search term will appear. Experiment!
EOF

# Select what action to take
searchArray=()
searchString=""
while true; do
    actionOptions=("${categoryOptions[@]}")
    printf "\n"

    searchArraySize="${#searchArray[@]}"
    [ "$searchArraySize" -eq 1 ] && actionOptions+=("Remove search term")
    [ "$searchArraySize" -gt 1 ] &&
        actionOptions+=("Remove one search term" "Delete all search terms")
    [ "$searchArraySize" -gt 0 ] &&
        actionOptions+=("Run full search" "Run 'multiples only' search")
    actionOptions+=("Quit")

    printf "What would you like to do?\n"
    PS3="Select a number from 1-${#actionOptions[@]}: "
    COLUMNS=80
    select actionMenu in "${actionOptions[@]}"; do
        printf "\n"
        case "$actionMenu" in
        *show*)
            searchFile="uniqTitles.txt"
            action="Start typing to search for show titles: "
            break
            ;;
        *person*)
            searchFile="uniqPersons.txt"
            action="Start typing to search for persons: "
            break
            ;;
        *character*)
            searchFile="uniqCharacters.txt"
            action="Start typing to search for characters: "
            break
            ;;
        *one*)
            # Remove one of the search term
            PS3="Select a number from 1-$searchArraySize: "
            select deleteMenu in "${searchArray[@]}"; do
                printf "Removing: \"$deleteMenu\"\n"
                # Arrays are zero based
                ((REPLY--)) || true
                tempArray=("${searchArray[@]}")
                searchArray=()
                searchString=""
                for i in "${!tempArray[@]}"; do
                    # printf "i = $i, REPLY = $REPLY\n"
                    if [ "$i" -ne "$REPLY" ]; then
                        searchArray+=("${tempArray[$i]}")
                        searchString+="\"${tempArray[$i]}\" "
                    fi
                done
                printf "\nSearch terms: $searchString\n"
                break
            done
            continue 2
            ;;
        Remove*)
            # Remove the only search term
            printf "Removing $searchString\n"
            searchArray=()
            searchString=""
            continue 2
            ;;
        *all*)
            # printf "Removing $searchString\n"
            printf "Deleting all search terms...\n"
            searchArray=()
            searchString=""
            continue 2
            ;;
        *full*)
            ./xrefCast.sh -n "${searchArray[@]}"
            continue 2
            ;;
        *multiples*)
            ./xrefCast.sh '-mn' "${searchArray[@]}"
            continue 2
            ;;
        Quit)
            printf "Quitting...\n"
            exit
            ;;
        *)
            printf "Your selection must be a number from 1-${#actionOptions[@]}\n"
            ;;
        esac
    done

    printf "$action"

    # Do the minimal typing search in a specific category
    searchFor=""
    while true; do
        read -r -n 1 -s
        printf "$REPLY"
        searchFor+="$REPLY"
        hitCount="$(rg -NzSI -c "$searchFor" $searchFile)"
        if [ "$hitCount" == "" ]; then
            printf "\nNo matches found.\n"
            break
        elif [ "$hitCount" -eq 1 ]; then
            # printf "\nOnly one match found\n"
            # rg -NzSI $searchFor $searchFile
            result="$(rg -NzSI "$searchFor" $searchFile)"
            for term in "${searchArray[@]}"; do
                [ "$result" == "$term" ] && break 2
            done
            searchString+="\"$result\" "
            searchArray+=("$result")
            break
        elif [ "$hitCount" -le "${maxHits:-10}" ]; then
            # printf "\n$hitCount matches found\n"
            # printf "\n"
            IFS=$'\n' pickOptions=($(rg -NzSI "$searchFor" "$searchFile"))
            printf "\n"
            PS3="Select a number from 1-${#pickOptions[@]}: "
            COLUMNS=40
            select pickMenu in "${pickOptions[@]}"; do
                if [ 1 -le "$REPLY" ] 2>/dev/null &&
                    [ "$REPLY" -le "${#pickOptions[@]}" ]; then
                    # printf "You picked $pickMenu ($REPLY)\n"
                    # rg -NzSI $pickMenu "$searchFile"
                    for term in "${searchArray[@]}"; do
                        [ "$pickMenu" == "$term" ] && break 2
                    done
                    searchString+="\"$pickMenu\" "
                    searchArray+=("$pickMenu")
                    break
                else
                    printf "Your selection must be a number from 1-${#pickOptions[@]}\n"
                fi
            done
            break
        fi
    done

    searchArraySize="${#searchArray[@]}"
    [ "$searchArraySize" -ne 0 ] && printf "\nSearch terms: $searchString\n"
done
