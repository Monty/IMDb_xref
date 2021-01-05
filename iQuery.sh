#!/usr/bin/env bash
#
# Interactively generate and run queries for xrefCast
#
# Type characters incrementally to generate and run queries

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd $DIRNAME
export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
The files uniqTitles.txt, uniqPersons.txt, and uniqCharacters.txt contain all known
entities in the database. Type characters incrementally to select one entity to use
as a search term for xrefCast.

Once there are no possible matches, only one possible match, or a low enough number of
matches to select one by number; ask user to select possible actions -- including adding
the match as an xrefCast search parameter.

Minimizes the number of keystrokes required to obtain a search term with a guaranteed
match, e.g. 'Hi' returns 'Tom Hiddleston' to use when when searching for people in the
initial database.

USAGE:
    iQuery.sh [OPTIONS...]

OPTIONS:
    -h      Print this message.
    -m      Maximum hits allowed in the selection menu. Continue typing until there are
            fewer hits. (defaults to 10)

EXAMPLES:
    iQuery.sh
    iQuery.sh -m 30
EOF
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
        printf "==> [${YELLOW}Warning${NO_COLOR}] Ignoring invalid " >&2
        printf "${YELLOW}-$OPTARG${NO_COLOR} option in: ${YELLOW}$0${NO_COLOR}\n\n" >&2
        ;;
    :)
        printf "==> [${RED}Error${NO_COLOR}] Option ${RED}-$OPTARG${NO_COLOR} " >&2
        printf "in: ${RED}$0${NO_COLOR} requires an argument.'\n\n" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

# Setup search files and corresponding categories
uniqFiles=('uniqTitles.txt' 'uniqPersons.txt' 'uniqCharacters.txt')
categories=('show' 'person' 'character')

# Check for uniq* files
foundSizes=()
foundCategories=()
missingCategories=()
actionOptions=()
idx=0
for file in "${uniqFiles[@]}"; do
    if [ -e "$file" ]; then
        numFound="$(sed -n '$=' $file)"
        foundSizes+=("$numFound" "${categories[$idx]}s,")
        foundCategories+=("${categories[$idx]}")
        actionOptions+=("Add a ${categories[$idx]} to the search string")
    else
        missingCategories+=("${categories[$idx]}")
    fi
    let idx++
done

# If we don't have any data...
numCategories="${#foundCategories[@]}"
if [ "$numCategories" -eq 0 ]; then
    printf "==> I didn't find the data files normally generated by generateXrefData.sh\n"
    if waitUntil -lY "    Shall I generate those data files now?"; then
        printf "==> Generating ${uniqFiles[*]}\n"
        ./generateXrefData.sh -q | rg --color never '==> Previously,'
        exec ./iQuery.sh
    else
        printf "==> [${RED}Error${NO_COLOR}] Missing required data files.\n" >&2
        printf "    Run ./generateXrefData.sh then re-run this script.\n\n" >&2
        exit
    fi
fi

# Let user know how much data we're dealing with
sizeStr="${foundSizes[*]}"
printf "==> I can generate search strings based on ${sizeStr/%,/.}\n\n"

# Select what action to take
actionOptions+=("Clear the search string" "Full search" "Summary search" "Quit")
searchString=""
searchArray=()
while true; do
    printf "What would you like to do?\n"

    PS3="Select a number from 1-${#actionOptions[@]}: "
    select actionMenu in "${actionOptions[@]}"; do
        case "$actionMenu" in
        *show*)
            searchFile="uniqTitles.txt"
            action="\nType to search show titles: "
            break
            ;;
        *person*)
            searchFile="uniqPersons.txt"
            action="\nType to search persons: "
            break
            ;;
        *character*)
            searchFile="uniqCharacters.txt"
            action="\nType to search characters: "
            break
            ;;
        Clear*)
            printf "Clearing search string...\n"
            printf "\n"
            searchString=""
            searchArray=()
            continue 2
            ;;
        Full*)
            printf "\n"
            ./xrefCast.sh "${searchArray[@]}"
            printf "\n"
            continue 2
            ;;
        Summary*)
            printf "\n"
            ./xrefCast.sh '-s' "${searchArray[@]}"
            printf "\n"
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

    # Should never happen!
    if [ ! "$searchFile" ]; then
        printf "==> [${RED}Error${NO_COLOR}] Missing search file for ${RED}$actionMenu${NO_COLOR}.\n" >&2
        printf "    Run ./generateXrefData.sh then re-run this script.\n\n" >&2
        exit 1
    fi

    # Do the minimal typing search in a specific category
    nchars=0
    searchFor=""
    while true; do
        read -n 1 -s
        printf "$REPLY"
        searchFor+="$REPLY"
        hitCount="$(rg -NzSI -c $searchFor $searchFile)"
        if [ "$hitCount" == "" ]; then
            printf "\nNo matches found\n"
            break
        elif [ "$hitCount" -eq 1 ]; then
            # printf "\nOnly one match found\n"
            # rg -NzSI $searchFor $searchFile
            result="$(rg -NzSI $searchFor $searchFile)"
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
                if [ 1 -le "$REPLY" ] 2>/dev/null && [ "$REPLY" -le "${#pickOptions[@]}" ]; then
                    # printf "You picked $pickMenu ($REPLY)\n"
                    # rg -NzSI $pickMenu "$searchFile"
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

    printf "\nsearchString = $searchString\n\n"
done
