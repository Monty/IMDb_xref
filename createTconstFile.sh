#!/usr/bin/env bash
#
# Add a tconst to a file

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME"
export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
createTconstFile.sh -- Add a tconst ID for any show to a file.

Search IMDb titles for a match to a tconst or a show name. A tconst should be unique,
but a show name can have several or even many matches. Allow user to select one match
or skip if there are too many.

USAGE:
    ./createTconstFile.sh [-f TCONST_FILE] TCONST or SHOW TITLE [TCONST...] [SHOW TITLE...]

OPTIONS:
    -h      Print this message.
    -m      Maximum matches for a show title allowed in menu - defaults to 25
    -f      File -- Add to specific file rather than the default $USER.tconst

EXAMPLES:
    ./createTconstFile.sh tt1606375
    ./createTconstFile.sh tt1606375 tt1399664 "Broadchurch"
    ./createTconstFile.sh "The Crown"
    ./createTconstFile.sh -f Dramas.tconst tt1606375
EOF
}

# Don't leave tempfiles around
# trap "rm -f $ALL_TERMS $TCONST_TERMS $SHOWS_TERMS $POSSIBLE_MATCHES $MATCH_COUNTS $FINAL_RESULTS" EXIT

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

while getopts ":f:hm:" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    f)
        TCONST_FILE="$OPTARG"
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
TCONST_TERMS=$WORK/TCONST_TERMS.txt
SHOWS_TERMS=$WORK/SHOWS_TERMS.txt
POSSIBLE_MATCHES=$WORK/POSSIBLE_MATCHES.txt
MATCH_COUNTS=$WORK/MATCH_COUNTS.txt
FINAL_RESULTS=$WORK/FINAL_RESULTS.txt

rm -f $ALL_TERMS $TCONST_TERMS $SHOWS_TERMS $POSSIBLE_MATCHES $MATCH_COUNTS $FINAL_RESULTS
touch $ALL_TERMS $TCONST_TERMS $SHOWS_TERMS $POSSIBLE_MATCHES $MATCH_COUNTS $FINAL_RESULTS

# Make sure a tconst was supplied
if [ $# -eq 0 ]; then
    printf "==> [${RED}Error${NO_COLOR}] Please supply one or more show names or tconst IDs,\n"
    printf "    such as tt1606375 -- which is the tconst for 'Downton Abbey'.\n\n"
    if waitUntil -N "Would you like me to add the Downton Abbey tconst for you?"; then
        printf "tt1606375\n" >>$ALL_TERMS
    else
        exit 1
    fi
fi

# Make sure we have the gz file to search
if [ ! -e "title.basics.tsv.gz" ]; then
    printf "==> Missing title.basics.tsv.gz. Run downloadIMDbFiles.sh to fix this problem.\n"
    if waitUntil -N "Would you like me to do this for you?"; then
        printf "OK. Downloading...\n"
        ./downloadIMDbFiles.sh 2>/dev/null
    else
        printf "Skipping download. Try again after running downloadIMDbFiles.sh.\n"
        exit
    fi
fi

function addToFileP() {
    if waitUntil -Y "\n==> Add them to $TCONST_FILE?"; then
        printf "OK. Adding...\n"
        rg -Ne "^tt" $FINAL_RESULTS >>$TCONST_FILE
        waitUntil -Y "\n==> Shall I sort $TCONST_FILE by title?" && ./augment_tconstFiles.sh -iy $TCONST_FILE
        waitUntil -Y "\n==> Shall I update your data files?" && ./generateXrefData.sh -q
    else
        printf "Skipping....\n"
    fi
}

# Get a TCONST_FILE
[ -z "$TCONST_FILE" ] && TCONST_FILE="$USER.tconst"
#
printf "==> Adding tconst IDs to: ${BLUE}$TCONST_FILE${NO_COLOR}\n\n"

# Setup ALL_TERMS with one search term per line
numRecords="$(rg -N title.basics.tsv.gz $numRecordsFile 2>/dev/null | cut -f 2)"
[ -z "$numRecords" ] && numRecords="$(rg -cz "^t" title.basics.tsv.gz)"
for param in "$@"; do
    printf "$param\n" >>$ALL_TERMS
done
# Split into two groups so we can process them differently
rg -wN "^tt[0-9]{7,8}" $ALL_TERMS | sort -fu >$TCONST_TERMS
rg -wNv "^tt[0-9]{7,8}" $ALL_TERMS | sort -fu >$SHOWS_TERMS
printf "==> Searching $numRecords records for:\n"
cat $TCONST_TERMS $SHOWS_TERMS

# Reconstitute ALL_TERMS with column guards
perl -p -e 's/^/^/; s/$/\\t/;' $TCONST_TERMS >$ALL_TERMS
perl -p -e 's/^/\\t/; s/$/\\t/;' $SHOWS_TERMS >>$ALL_TERMS

# Get all possible matches at once
rg -NzSI -f $ALL_TERMS title.basics.tsv.gz | rg -v "tvEpisode" | cut -f 1-4 |
    sort -f --field-separator=$'\t' --key=3 >$POSSIBLE_MATCHES

cut -f 3 $POSSIBLE_MATCHES | frequency -t >$MATCH_COUNTS

while read -r line; do
    count=$(cut -f 1 <<<"$line")
    match=$(cut -f 2 <<<"$line")
    if [ "$count" -eq 1 ]; then
        rg "\t$match\t" $POSSIBLE_MATCHES >>$FINAL_RESULTS
        continue
    fi
    printf "\n"
    printf "Some titles on IMDb occur more than once, e.g. as both a movie and TV show.\n"
    printf "You can track down the correct one by searching for it's tconst ID on IMDb.com.\n"
    printf "\n"

    printf "I found $count shows titled \"$match\"\n"
    if [ "$count" -ge "${maxMenuSize:-25}" ]; then
        if waitUntil -Y "Should I skip trying to select one?"; then
            continue
        fi
    fi
    # rg --color always "\t$match\t" $POSSIBLE_MATCHES | xsv table -d "\t"
    pickOptions=()
    IFS=$'\n' pickOptions=($(rg -N "\t$match\t" $POSSIBLE_MATCHES |
        sort -f --field-separator=$'\t' --key=2))
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
                printf "$pickMenu\n" >>$FINAL_RESULTS
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
if [ ! -s $FINAL_RESULTS ]; then
    printf "==> Didn't find ${RED}any${NO_COLOR} matching shows.\n"
    printf "    Check the \"Searching $numRecords records for:\" section above.\n\n"
    exit
fi

printf "These are the matches I can add:\n"
if checkForExecutable -q xsv; then
    xsv table -d "\t" $FINAL_RESULTS
else
    cat $FINAL_RESULTS
fi

addToFileP
