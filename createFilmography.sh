#!/usr/bin/env bash
#
# Create a filmography for a named person in IMDb

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME"
export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
createFilmography.sh -- Create a filmography for a named person in IMDb

Search IMDb titles for a match to a nconst or a person name. A nconst should be unique,
but a person name can have several or even many matches. Allow user to select one match
or skip if there are too many.

Filmographies are created in subdirectories so they will not overload the primary
directory. You'll have the opportunity to review results before committing.

USAGE:
    ./createFilmography.sh [NCONST...] [PERSON NAME...]

OPTIONS:
    -h      Print this message.
    -m      Maximum matches for a person name allowed in menu - defaults to 10

EXAMPLES:
    ./createFilmography.sh
    ./createFilmography.sh nm0000123
    ./createFilmography.sh "George Clooney"
    ./createFilmography.sh nm0000123 "Quentin Tarantino"
EOF
}

# Don't leave tempfiles around
trap terminate EXIT
#
function terminate() {
    if [ -n "$DEBUG" ]; then
        printf "\nTerminating: $(basename $0)\n" >&2
        printf "Not removing:\n" >&2
        printf "$ALL_TERMS $NCONST_TERMS $PERSON_TERMS $POSSIBLE_MATCHES\n" >&2
        printf "$MATCH_COUNTS $PERSON_RESULTS $JOB_RESULTS $FINAL_RESULTS\n" >&2
    else
        rm -f $ALL_TERMS $NCONST_TERMS $PERSON_TERMS $POSSIBLE_MATCHES
        rm -f $MATCH_COUNTS $PERSON_RESULTS $JOB_RESULTS $FINAL_RESULTS
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
        maxMenuSize="$OPTARG"
        ;;
    \?)
        printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2
        ;;
    :)
        printf "Option -$OPTARG requires a 'translation file' argument'.\n" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

# Make sure we can execute rg.
checkForExecutable rg

# Required subdirectories
WORK="secondary"
mkdir -p $WORK

# Need some tempfiles
ALL_TERMS=$WORK/ALL_TERMS.txt
NCONST_TERMS=$WORK/NCONST_TERMS.txt
PERSON_TERMS=$WORK/PERSON_TERMS.txt
POSSIBLE_MATCHES=$WORK/POSSIBLE_MATCHES.csv
MATCH_COUNTS=$WORK/MATCH_COUNTS.txt
PERSON_RESULTS=$WORK/PERSON_RESULTS.csv
JOB_RESULTS=$WORK/JOB_RESULTS.csv
FINAL_RESULTS=$WORK/FINAL_RESULTS.csv

rm -f $ALL_TERMS $NCONST_TERMS $PERSON_TERMS $POSSIBLE_MATCHES $MATCH_COUNTS \
    $PERSON_RESULTS $JOB_RESULTS $FINAL_RESULTS
touch $ALL_TERMS $NCONST_TERMS $PERSON_TERMS $POSSIBLE_MATCHES $MATCH_COUNTS \
    $PERSON_RESULTS $JOB_RESULTS $FINAL_RESULTS

# Make sure a nconst was supplied
if [ $# -eq 0 ]; then
    printf "==> I can generate a filmography based on a person name or nconst ID,\n"
    printf "    such as nm0000123 -- which is the nconst for 'George Clooney'.\n\n"
    read -p "Enter an (unquoted) person name or nconst ID: " line </dev/tty
    printf "$line\n" >>$ALL_TERMS
    printf "\n"
fi

# Make sure we have the gz file to search
if [ ! -e "name.basics.tsv.gz" ]; then
    printf "==> Missing name.basics.tsv.gz. Run downloadIMDbFiles.sh to fix this problem.\n"
    if waitUntil -N "Would you like me to do this for you?"; then
        printf "OK. Downloading...\n"
        ./downloadIMDbFiles.sh 2>/dev/null
    else
        printf "Skipping download. Try again after running downloadIMDbFiles.sh.\n"
        exit
    fi
fi

# Do the work of adding the matches to the TCONST_FILE
function addToFileP() {
    if waitUntil -Y "==> Shall I add them?"; then
        printf "OK. Adding...\n"
        mkdir -p $filmographyDir
        rg -Ne "^tt" $FINAL_RESULTS >>$TCONST_FILE
        waitUntil -Y "\n==> Shall I generate ${BLUE}$(basename $filmographyDB)${NO_COLOR}?" &&
            ./generateXrefData.sh -q -o $filmographyDB -d $filmographyDir $filmographyFile
    else
        printf "Skipping....\n"
    fi
}

# Setup ALL_TERMS with one search term per line
numRecords="$(rg -N name.basics.tsv.gz $numRecordsFile 2>/dev/null | cut -f 2)"
[ -z "$numRecords" ] && numRecords="$(rg -cz "^n" name.basics.tsv.gz)"
for param in "$@"; do
    printf "$param\n" >>$ALL_TERMS
done
# Split into two groups so we can process them differently
rg -wN "^nm[0-9]{7,8}" $ALL_TERMS | sort -fu >$NCONST_TERMS
rg -wNv "nm[0-9]{7,8}" $ALL_TERMS | sort -fu >$PERSON_TERMS
printf "==> Searching $numRecords records for:\n"
cat $NCONST_TERMS $PERSON_TERMS

# Reconstitute ALL_TERMS with column guards
perl -p -e 's/^/^/; s/$/\\t/;' $NCONST_TERMS >$ALL_TERMS
perl -p -e 's/^/\\t/; s/$/\\t/;' $PERSON_TERMS >>$ALL_TERMS

# Get all possible matches at once
rg -NzSI -f $ALL_TERMS name.basics.tsv.gz | rg -wN "tt[0-9]{7,8}" | cut -f 1-5 |
    sort -f --field-separator=$'\t' --key=2 >$POSSIBLE_MATCHES
# perl -pi -e 's+\\N++g;' $POSSIBLE_MATCHES
# perl -pi -e 's+\\N++g; tr+[]++d; s+,+, +g; s+,  +, +g; s+", "+; +g; tr+"++d;' $POSSIBLE_MATCHES
perl -pi -e 's+\\N++g; s+,+, +g; s+,  +, +g;' $POSSIBLE_MATCHES

# Figure how many matches for each possible match
cut -f 2 $POSSIBLE_MATCHES | frequency -t >$MATCH_COUNTS

# Add possible matches one at a time
while read -r line; do
    count=$(cut -f 1 <<<"$line")
    match=$(cut -f 2 <<<"$line")
    if [ "$count" -eq 1 ]; then
        rg "\t$match\t" $POSSIBLE_MATCHES >>$PERSON_RESULTS
        continue
    fi
    printf "\n"
    printf "Some person names on IMDb occur more than once, e.g. John Wayne or John Lennon.\n"
    printf "You can track down the correct one by searching for it's nconst ID on IMDb.com.\n"
    printf "\n"

    printf "I found $count persons named \"$match\"\n"
    if [ "$count" -ge "${maxMenuSize:-10}" ]; then
        if waitUntil -Y "Should I skip trying to select one?"; then
            continue
        fi
    fi
    pickOptions=()
    IFS=$'\n' pickOptions=($(rg -N "\t$match\t" $POSSIBLE_MATCHES |
        sort -f --field-separator=$'\t' --key=3,3r --key=5))
    pickOptions+=("Skip \"$match\"" "Quit")

    PS3="Select a number from 1-${#pickOptions[@]}: "
    COLUMNS=40
    select pickMenu in "${pickOptions[@]}"; do
        if [ "$REPLY" -ge 1 ] 2>/dev/null && [ "$REPLY" -le "${#pickOptions[@]}" ]; then
            case "$pickMenu" in
            Skip*)
                printf "Skipping...\n"
                break
                ;;
            Quit)
                printf "Quitting...\n"
                exit
                ;;
            *)
                printf "Adding: $pickMenu\n"
                printf "$pickMenu\n" >>$PERSON_RESULTS
                break
                ;;
            esac
            break
        else
            printf "Your selection must be a number from 1-${#pickOptions[@]}\n"
        fi
    done </dev/tty
done <$MATCH_COUNTS
printf "\n"

# Didn't find any results
if [ ! -s "$PERSON_RESULTS" ]; then
    printf "==> Didn't find ${RED}any${NO_COLOR} matching persons.\n"
    printf "    Check the \"Searching $numRecords records for:\" section above.\n\n"
    exit
fi

# Found results, check with user before adding
printf "These are the matches I can process:\n"
if checkForExecutable -q xsv; then
    xsv table -d "\t" $PERSON_RESULTS
else
    cat $PERSON_RESULTS
fi

if ! waitUntil -Y; then
    printf "Quitting...\n"
    exit
fi

cut -f 1 $PERSON_RESULTS >$NCONST_TERMS
rg -Nz -f $NCONST_TERMS title.principals.tsv.gz |
    rg -w -e actor -e actress -e writer -e director -e producer | cut -f 1,3,4 >$POSSIBLE_MATCHES
perl -pi -e 's+\\N++g; tr+[]++d; s+,+, +g; s+,  +, +g; s+", "+; +g; tr+"++d;' $POSSIBLE_MATCHES

while read -r line; do
    >$FINAL_RESULTS
    nconstID="$line"
    nconstName="$(rg -N $line $PERSON_RESULTS | cut -f 2)"
    noSpaceName="${nconstName//[[:space:]]/_}"
    filmographyDir="$noSpaceName-Filmography"
    printf "\n==> Any files generated for $nconstName will be saved in ${BLUE}$filmographyDir${NO_COLOR}\n"
    filmographyFile="$filmographyDir/$noSpaceName"
    rg -Nw "$nconstID" $POSSIBLE_MATCHES | cut -f 3 | frequency -t >$MATCH_COUNTS
    while read -r job; do
        count=$(cut -f 1 <<<"$job")
        match=$(cut -f 2 <<<"$job")
        printf "\n"
        rg -Nw -e "$nconstID\t$match" $POSSIBLE_MATCHES >$JOB_RESULTS
        ./augment_tconstFiles.sh -y $JOB_RESULTS
        numResults=$(sed -n '$=' $JOB_RESULTS)
        printf "I found $numResults titles listing $nconstName as: $match\n"
        if waitUntil -Y "==> Do you want to review them before adding them?"; then
            if checkForExecutable -q xsv; then
                cut -f 2,3 $JOB_RESULTS | sort -fu | xsv table -d "\t"
            else
                cut -f 2,3 $JOB_RESULTS | sort -fu
            fi
        fi
        if waitUntil -Y "==> Shall I add them?"; then
            filmographyFile+="-$match"
            # printf "filmographyFile = $filmographyFile\n"
            cat $JOB_RESULTS >>$FINAL_RESULTS
        fi
    done <$MATCH_COUNTS
    filmographyDB="$filmographyFile.csv"
    filmographyFile+=".tconst"
    TCONST_FILE="$filmographyFile"
    if [ -s "$FINAL_RESULTS" ]; then
        numlines=$(sed -n '$=' $FINAL_RESULTS)
        printf "\nI can add $numlines tconst IDs to ${BLUE}$(basename $TCONST_FILE)${NO_COLOR}\n"
        addToFileP
    else
        printf "\n==> There aren't ${RED}any${NO_COLOR} $nconstName titles to add.\n"
    fi
done <$NCONST_TERMS
