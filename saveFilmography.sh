#!/usr/bin/env bash
#
# Save a filmography for a named person in IMDb

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
saveFilmography.sh -- Save a filmography for a named person in IMDb.

Search IMDb titles for person names or nconst IDs. An nconst ID should be
unique, but a person name can have several or even many matches. Allow user to
select one match or skip if there are too many.

Filmographies are created in subdirectories so they will not overload the
primary directory. You'll have the opportunity to review results before
committing.

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

# Don't leave tempfiles around
trap terminate EXIT
#
function terminate() {
    if [ -n "$DEBUG" ]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
        printf "Not removing:\n" >&2
        cat <<EOT >&2
ALL_TERMS $ALL_TERMS
NCONST_TERMS $NCONST_TERMS
PERSON_TERMS $PERSON_TERMS
POSSIBLE_MATCHES $POSSIBLE_MATCHES
MATCH_COUNTS $MATCH_COUNTS
PERSON_RESULTS $PERSON_RESULTS
JOB_RESULTS $JOB_RESULTS
FINAL_RESULTS $FINAL_RESULTS
TMPFILE $TMPFILE
EOT
    else
        rm -f "$ALL_TERMS" "$NCONST_TERMS" "$PERSON_TERMS" "$POSSIBLE_MATCHES"
        rm -f "$MATCH_COUNTS" "$PERSON_RESULTS" "$JOB_RESULTS" "$FINAL_RESULTS"
        rm -f "$TMPFILE"
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
    if waitUntil "$YN_PREF" -N \
        "\n==> Would you like to do another search?"; then
        printf "\n"
        terminate
        exec ./saveFilmography.sh
    else
        printf "Quitting...\n"
        exit
    fi
}

while getopts ":hm:" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    m)
        maxMenuSize="$OPTARG"
        ;;
    \?)
        printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2
        ;;
    :)
        printf "Option -$OPTARG requires a 'maximum menu size' argument'.\n" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

# Make sure prerequisites are satisfied
ensurePrerequisites

# Need some tempfiles
ALL_TERMS=$(mktemp)
NCONST_TERMS=$(mktemp)
PERSON_TERMS=$(mktemp)
POSSIBLE_MATCHES=$(mktemp)
MATCH_COUNTS=$(mktemp)
PERSON_RESULTS=$(mktemp)
JOB_RESULTS=$(mktemp)
FINAL_RESULTS=$(mktemp)
TMPFILE=$(mktemp)

# Make sure a search term is supplied
if [ $# -eq 0 ]; then
    cat <<EOF
==> I can generate a filmography based on person names or nconst IDs,
    such as nm0000123 -- which is the nconst for George Clooney.

Only one search term per line. Enter a blank line to finish.
EOF
    while read -r -p "Enter a person name or nconst ID: " searchTerm; do
        [ -z "$searchTerm" ] && break
        tr -ds '"' '[:space:]' <<<"$searchTerm" >>"$ALL_TERMS"
    done </dev/tty
    if [ ! -s "$ALL_TERMS" ]; then
        if waitUntil "$YN_PREF" -N \
            "Would you like me to add the George Clooney nconst for you?"; then
            printf "nm0000123\n" >>"$ALL_TERMS"
        else
            loopOrExitP
        fi
    fi
    printf "\n"
fi

# Do the work of adding the matches to the TCONST_FILE
function addToFileP() {
    if waitUntil "$YN_PREF" -Y "==> Shall I add them?"; then
        printf "OK. Adding...\n"
        mkdir -p "$filmographyDir"
        rg -N "^tt" "$FINAL_RESULTS" >>"$TCONST_FILE"
        waitUntil "$YN_PREF" -Y \
            "\n==> Shall I generate ${BLUE}$(basename "$filmographyDB")${NO_COLOR}?" &&
            ./generateXrefData.sh -q -f "$filmographyDB" -d "$filmographyDir" "$filmographyFile"
    else
        printf "Skipping....\n"
    fi
}

# Get gz file size - which should already exist but make sure...
numRecords="$(rg -N name.basics.tsv.gz "$numRecordsFile" 2>/dev/null | cut -f 2)"
[ -z "$numRecords" ] && numRecords="$(rg -cz "^n" name.basics.tsv.gz)"

# Setup ALL_TERMS with one search term per line
for param in "$@"; do
    printf "$param\n" >>"$ALL_TERMS"
done
# Split into two groups so we can process them differently
rg -wN "^nm[0-9]{7,8}" "$ALL_TERMS" | sort -fu >"$NCONST_TERMS"
rg -wNv "nm[0-9]{7,8}" "$ALL_TERMS" | sort -fu >"$PERSON_TERMS"
printf "==> Searching $numRecords records for:\n"
cat "$NCONST_TERMS" "$PERSON_TERMS"

# Reconstitute ALL_TERMS with column guards
perl -p -e 's/^/^/; s/$/\\t/;' "$NCONST_TERMS" >"$ALL_TERMS"
perl -p -e 's/^/\\t/; s/$/\\t/;' "$PERSON_TERMS" >>"$ALL_TERMS"

# Get all possible matches at once
rg -NzSI -f "$ALL_TERMS" name.basics.tsv.gz | rg -wN "tt[0-9]{7,8}" | cut -f 1-5 |
    sort -f -t$'\t' --key=2 >"$POSSIBLE_MATCHES"
perl -pi -e 's+\\N++g; s+,+, +g; s+,  +, +g;' "$POSSIBLE_MATCHES"

# Figure how many matches for each possible match
cut -f 2 "$POSSIBLE_MATCHES" | frequency -s >"$MATCH_COUNTS"

# Add possible matches one at a time, preceded by URL
while read -r line; do
    count=$(cut -f 1 <<<"$line")
    match=$(cut -f 2 <<<"$line")
    if [ "$count" -eq 1 ]; then
        rg --color always "$match" "$POSSIBLE_MATCHES" |
            sed 's+^+imdb.com/name/+' >>"$PERSON_RESULTS"
        continue
    fi
    if [ -z "$alreadyPrintedP" ]; then
        cat <<EOF

Some person names occur more than once on IMDb, e.g. John Wayne or John Lennon.
You can determine which one to select using the provided links to imdb.com.
EOF
        alreadyPrintedP="yes"
    fi

    printf "\nI found $count persons named \"$match\"\n"
    if [ "$count" -ge "${maxMenuSize:-10}" ]; then
        waitUntil "$YN_PREF" -Y "Should I skip trying to select one?" && continue
    fi

    # Create parallel tabbed array
    rg --color always "$match" "$POSSIBLE_MATCHES" |
        sort -f -t$'\t' --key=3,3r --key=5 | sed 's+^+imdb.com/name/+' >"$TMPFILE"
    #
    tabbedOptions=()
    while IFS='' read -r line; do tabbedOptions+=("$line"); done <"$TMPFILE"

    # Create tsvPrinted select array
    rg --color always "$match" "$POSSIBLE_MATCHES" |
        sort -f -t$'\t' --key=3,3r --key=5 | sed 's+^+imdb.com/name/+' >"$TMPFILE"
    #
    pickOptions=()
    while IFS='' read -r line; do pickOptions+=("$line"); done < <(tsvPrint "$TMPFILE")
    pickOptions+=("Skip \"$match\"" "Quit")

    PS3="Select a number from 1-${#pickOptions[@]}: "
    COLUMNS=40
    select pickMenu in "${pickOptions[@]}"; do
        if [ "$REPLY" -ge 1 ] 2>/dev/null &&
            [ "$REPLY" -le "${#pickOptions[@]}" ]; then
            case "$pickMenu" in
            Skip*)
                break
                ;;
            Quit)
                printf "Quitting...\n"
                exit
                ;;
            *)
                printf "${tabbedOptions[REPLY - 1]}\n" >>"$PERSON_RESULTS"
                break
                ;;
            esac
            break
        else
            printf "Your selection must be a number from 1-${#pickOptions[@]}\n"
        fi
    done </dev/tty
done <"$MATCH_COUNTS"

# Didn't find any results
if [ ! -s "$PERSON_RESULTS" ]; then
    printf "==> I didn't find ${RED}any${NO_COLOR} matching persons.\n"
    printf "    Check the \"Searching $numRecords records for:\" section above.\n"
    loopOrExitP
fi

# Found results, check with user before adding
printf "\nThese are the results I can process:\n"
tsvPrint "$PERSON_RESULTS"

# Get rid of the URL preface we added and any colorization escape sequences
sed -i '' $'s+\x1b\\[[0-3;]*[a-zA-Z]++g;s+imdb.com/name/++;' "$PERSON_RESULTS"

if ! waitUntil "$YN_PREF" -Y; then
    loopOrExitP
fi

cut -f 1 "$PERSON_RESULTS" >"$NCONST_TERMS"
rg -Nz -f "$NCONST_TERMS" title.principals.tsv.gz |
    cut -f 1,3,4 >"$POSSIBLE_MATCHES"
perl -pi -e 's+\\N++g; tr+[]++d; s+,+, +g; s+,  +, +g; s+", "+; +g; tr+"++d;' \
    "$POSSIBLE_MATCHES"

while read -r line; do
    true >"$FINAL_RESULTS"
    nconstID="$line"
    nconstName="$(rg -N "$line" "$PERSON_RESULTS" | cut -f 2)"
    rg -Nw "$nconstID" "$POSSIBLE_MATCHES" | cut -f 3 | frequency -t >"$MATCH_COUNTS"
        if [ ! -s "$MATCH_COUNTS" ]; then
        printf "\n==> I didn't find any principal cast member records for "
        printf "${RED}$nconstName${NO_COLOR}.\n"
        printf "    Check ${RED}imdb.com/name/$nconstID${NO_COLOR} to get more details.\n"
        continue
    fi
    noSpaceName="${nconstName//[[:space:]]/_}"
    filmographyDir="$noSpaceName-Filmography"
    printf "\n==> Any files generated for $nconstName will be saved in ${BLUE}$filmographyDir${NO_COLOR}\n"
    filmographyFile="$filmographyDir/$noSpaceName"
    while read -r job; do
        count=$(cut -f 1 <<<"$job")
        match=$(cut -f 2 <<<"$job")
        printf "\n"
        rg -Nw "$nconstID\t$match" "$POSSIBLE_MATCHES" >"$JOB_RESULTS"
        ./augment_tconstFiles.sh -y "$JOB_RESULTS"
        cut -f 2,3,5 "$JOB_RESULTS" |
            sort -f -t$'\t' --key=1,1 --key=3,3r --key=2,2 >"$TMPFILE"
        numResults=$(sed -n '$=' "$JOB_RESULTS")
        if [[ $numResults -gt 0 ]]; then
            printf "I found $numResults titles listing $nconstName as: $match\n"
            if waitUntil "$YN_PREF" -Y \
                "==> Do you want to review them before adding them?"; then
                tsvPrint "$TMPFILE"
            fi
            if waitUntil "$YN_PREF" -Y "==> Shall I add them?"; then
                filmographyFile+="-$match"
                cat "$JOB_RESULTS" >>"$FINAL_RESULTS"
            fi
        fi
    done <"$MATCH_COUNTS"
    filmographyDB="$filmographyFile.csv"
    filmographyFile+=".tconst"
    TCONST_FILE="$filmographyFile"
    if [ -s "$FINAL_RESULTS" ]; then
        numlines=$(sed -n '$=' "$FINAL_RESULTS")
        printf "\nI can add $numlines titles to ${BLUE}$(basename $TCONST_FILE)${NO_COLOR}\n"
        addToFileP
    else
        printf "\n==> There aren't ${RED}any${NO_COLOR} $nconstName titles to add.\n"
    fi
done <"$NCONST_TERMS"

# Do we really want to quit?
loopOrExitP
