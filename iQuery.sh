#!/usr/bin/env bash
#
# Interactively generate and run queries for xrefCast
#
# Type characters incrementally to generate and run queries

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
iQuery.sh -- Cross-reference saved data using prompts and minimal keystrokes.

The files uniqTitles.txt, uniqPersons.txt, and uniqCharacters.txt contain all
the entities that are in your saved data files. Type characters incrementally
to select one entity to use as a search term for xrefCast.

Once there is only one possible match, or a low enough number of matches to
select one by number; ask user to select possible actions -- including adding
the match as an xrefCast search parameter. If there are no possible matches,
let the user know.

Minimizes the number of keystrokes required to obtain a search term with a
guaranteed match, e.g. 'Hi' returns 'Tom Hiddleston' to use when when searching
for people in the default data files.

USAGE:
    iQuery.sh [OPTIONS...]

OPTIONS:
    -h      Print this message.
    -u      Union -- Also include shows that are in the cross-reference cache but
            in none of your .tconst lists. Those contribute only each show's ~10
            series principals, with no episode credits, so the search lists grow
            wider without growing deeper. See ./xrefCast.sh -h.
    -l      Use 'less' to list shows a page at a time rather than all at once.
            Type space bar for next page, 'b' for previous page, 'h' for help,
            '/' to search, 'q' to quit.
    -m      Maximum items to be shown in the search menu. Continue typing until
            there will be fewer items. Larger numbers will require less typing,
            but have longer menus. (defaults to 15)

EXAMPLES:
    iQuery.sh
    iQuery.sh -m 30
    iQuery.sh -u
EOF
}

# Don't leave tempfiles around
trap terminate EXIT
#
function terminate() {
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
        printf "Not removing:\n" >&2
        cat <<EOT >&2
TITLES $TITLES
PERSONS $PERSONS
CHARACTERS $CHARACTERS
CREDITS $CREDITS
CACHED $CACHED
FRINGE $FRINGE
EOT
    else
        rm -f "$TITLES" "$PERSONS" "$CHARACTERS" "$CREDITS" "$CACHED" "$FRINGE"
    fi
}

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

while getopts ":hulm:" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    u)
        USE_UNION="yes"
        ;;
    l)
        USE_LESS="yes"
        ;;
    m)
        maxHits="$OPTARG"
        ;;
    \?)
        printf "==> Ignoring invalid option: -%s\n\n" "$OPTARG" >&2
        ;;
    :)
        printf "==> Option -%s requires an argument.\n\n" "$OPTARG" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

# Make sure prerequisites are satisfied
ensurePrerequisites

# Need some tempfiles
TITLES=$(mktemp)
PERSONS=$(mktemp)
CHARACTERS=$(mktemp)
CREDITS=$(mktemp)
CACHED=$(mktemp)
FRINGE=$(mktemp)

# Setup default search files and corresponding categories
creditsFile="Credits-Person.csv"
uniqFiles=('uniqTitles.txt' 'uniqPersons.txt' 'uniqCharacters.txt')
categories=('show' 'person' 'character')

# Make sure creditsFile exists
[[ ! -e $creditsFile ]] && ensureDataFiles

# What to hand xrefCast.sh. By default, the same file we built our lists from.
xrefArgs=(-f "$creditsFile")

# -u widens the search lists to include shows that are cached but in none of the
# .tconst lists, matching xrefCast.sh -u. Union, not a corpus swap: curated shows
# keep their episode-level rows and the uncurated ones are appended at
# principals-only depth. The predecessor -c replaced the corpus outright, and
# before that the FULLCAST environment variable did the same under a name that
# promised the opposite.
#
# In union mode we pass -u rather than -f: xrefCast.sh builds the identical
# union itself, and -f would suppress not just that but the footer naming which
# shows came from the cache -- the whole point of marking mixed-depth results.
if [[ -n $USE_UNION ]]; then
    if [[ -n "$(ls -1 "$cacheDirectory" 2>/dev/null | rg "^tt")" ]]; then
        cat "$cacheDirectory"/tt* | rg -v '^Person\tShow Title\t' | rg -v '^$' |
            sort -fu >"$CACHED"
        awk -F "\t" 'NR==FNR {curated[$8]=1; next} !($8 in curated)' \
            "$creditsFile" "$CACHED" >"$FRINGE"
        cat "$creditsFile" "$FRINGE" >"$CREDITS"
        cut -f 2 "$CREDITS" | sort -fu >"$TITLES"
        cut -f 1 "$CREDITS" | sort -fu >"$PERSONS"
        cut -f 6 "$CREDITS" | sort -fu >"$CHARACTERS"
        #
        uniqFiles=("$TITLES" "$PERSONS" "$CHARACTERS")
        xrefArgs=(-u)
    else
        printf "==> [${YELLOW}Warning${NO_COLOR}] The cross-reference cache is empty. " >&2
        printf "Using the generated data files alone.\n\n" >&2
    fi
fi

# Check uniq* files exist
foundSizes=()
foundCategories=()
missingCategories=()
categoryOptions=()
idx=0
for file in "${uniqFiles[@]}"; do
    if [[ -e $file ]]; then
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
if [[ ${#missingCategories[@]} -gt 0 ]]; then
    ensureDataFiles
    rm -f "$TITLES" "$PERSONS" "$CHARACTERS" "$CREDITS" "$CACHED" "$FRINGE"
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
after executing the search, or switch from a full search to a 'duplicates only'
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
    [[ $searchArraySize -eq 1 ]] && actionOptions+=("Remove search term")
    [[ $searchArraySize -gt 1 ]] &&
        actionOptions+=("Remove one search term" "Delete all search terms")
    [[ $searchArraySize -gt 0 ]] &&
        actionOptions+=("Run full search" "Run 'duplicates only' search")
    actionOptions+=("List all shows" "Quit")

    printf "What would you like to do?\n"
    PS3="Select a number from 1-${#actionOptions[@]}, or type 'q(uit)': "
    COLUMNS=80
    select actionMenu in "${actionOptions[@]}"; do
        printf "\n"
        # Be cautious about ordering case statements e.g. List* and *show*
        case "$actionMenu" in
        List*)
            if [[ -n $USE_LESS ]]; then
                sort -df "${uniqFiles[0]}" | less -EX
            else
                sort -df "${uniqFiles[0]}"
            fi
            continue 2
            ;;
        *show*)
            searchFile="${uniqFiles[0]}"
            action="Start typing to search for show titles: "
            break
            ;;
        *person*)
            searchFile="${uniqFiles[1]}"
            action="Start typing to search for persons: "
            break
            ;;
        *character*)
            searchFile="${uniqFiles[2]}"
            action="Start typing to search for characters: "
            break
            ;;
        *one*)
            # Remove one of the search term
            PS3="Select a number from 1-$searchArraySize, or enter '0' to skip: "
            select deleteMenu in "${searchArray[@]}"; do
                if [[ $REPLY -ge 1 ]] 2>/dev/null &&
                    [[ $REPLY -le ${#searchArray[@]} ]]; then
                    printf "Removing: \"$deleteMenu\"\n"
                    # Arrays are zero based
                    ((REPLY--)) || true
                    tempArray=("${searchArray[@]}")
                    searchArray=()
                    searchString=""
                    for i in "${!tempArray[@]}"; do
                        # printf "i = $i, REPLY = $REPLY\n"
                        if [[ $i -ne $REPLY ]]; then
                            searchArray+=("${tempArray[$i]}")
                            searchString+="\"${RED}${tempArray[$i]}${NO_COLOR}\" "
                        fi
                    done
                    break
                else
                    case "$REPLY" in
                    0)
                        break
                        ;;
                    esac
                fi
            done
            printf "\nSearch terms: $searchString\n"
            continue 2
            ;;
        Remove*)
            # Remove the only search term
            printf "Removing $searchString\n"
            searchArray=()
            searchString=""
            continue 2
            ;;
        Delete*)
            # printf "Removing $searchString\n"
            printf "Deleting all search terms...\n"
            searchArray=()
            searchString=""
            continue 2
            ;;
        *full*)
            NO_MENUS="yes" ./xrefCast.sh "${xrefArgs[@]}" "${searchArray[@]}"
            continue 2
            ;;
        *duplicates*)
            NO_MENUS="yes" ./xrefCast.sh -d "${xrefArgs[@]}" "${searchArray[@]}"
            continue 2
            ;;
        Quit)
            [[ -n $NO_MENUS ]] && exit
            rm -f "$TITLES" "$PERSONS" "$CHARACTERS" "$CREDITS"
            exec ./start.command
            ;;
        esac
        case "$REPLY" in
        [Qq]*)
            [[ -n $NO_MENUS ]] && exit
            rm -f "$TITLES" "$PERSONS" "$CHARACTERS" "$CREDITS"
            exec ./start.command
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
        hitCount="$(rg -N -c "$searchFor" "$searchFile")"
        if [[ $hitCount == "" ]]; then
            printf "\nNo matches found.\n"
            break
        elif [[ $hitCount -eq 1 ]]; then
            # printf "\nOnly one match found\n"
            result="$(rg -N "$searchFor" "$searchFile")"
            for term in "${searchArray[@]}"; do
                [[ $result == "$term" ]] && break 2
            done
            searchString+="\"${RED}${result}${NO_COLOR}\" "
            searchArray+=("$result")
            break
        elif [[ $hitCount -le ${maxHits:-15} ]]; then
            # printf "\n$hitCount matches found\n"
            pickOptions=()
            while IFS=$'\n' read -r line; do
                pickOptions+=("$line")
            done < <(rg -N "$searchFor" "$searchFile")
            printf "\n"
            PS3="Select a number from 1-${#pickOptions[@]}, or enter '0' to skip: "
            COLUMNS=40
            select pickMenu in "${pickOptions[@]}"; do
                if [[ 1 -le $REPLY ]] 2>/dev/null &&
                    [[ $REPLY -le ${#pickOptions[@]} ]]; then
                    # printf "You picked $pickMenu ($REPLY)\n"
                    for term in "${searchArray[@]}"; do
                        [[ $pickMenu == "$term" ]] && break 2
                    done
                    searchString+="\"${RED}${pickMenu}${NO_COLOR}\" "
                    searchArray+=("$pickMenu")
                    break
                else
                    case "$REPLY" in
                    0)
                        break
                        ;;
                    esac
                fi
            done
            break
        fi
    done

    searchArraySize="${#searchArray[@]}"
    [[ $searchArraySize -ne 0 ]] && printf "\nSearch terms: $searchString\n"
done
