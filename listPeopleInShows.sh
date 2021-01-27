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
listPeopleInShows.sh -- List people in a show on IMDb.

Search IMDb titles for a match to a tconst or a show name. A tconst should be
unique, but a show name can have several or even many matches. Allow user to
select one match or skip if there are too many.

Then list all the people from that show.

If you don't enter a parameter on the command line, you'll be prompted for input.

USAGE:
    ./listPeopleInShows.sh [TCONST...] [SHOW TITLE...]

OPTIONS:
    -h      Print this message.
    -m      Maximum matches for a show title allowed in menu - defaults to 25

EXAMPLES:
    ./listPeopleInShows.sh
    ./listPeopleInShows.sh tt1606375
    ./listPeopleInShows.sh tt1606375 tt1399664 "Broadchurch"
    ./listPeopleInShows.sh "The Crown"
EOF
}

# Don't leave tempfiles around
trap terminate EXIT
#
function terminate() {
    if [ -n "$DEBUG" ]; then
        printf "\nTerminating: $(basename $0)\n" >&2
        printf "Not removing:\n" >&2
        printf "$ALL_TERMS $TCONST_LIST $TCONST_TERMS $SHOWS_TERMS\n" >&2
        printf "$POSSIBLE_MATCHES $MATCH_COUNTS $FINAL_RESULTS\n" >&2
    else
        rm -f $ALL_TERMS $TCONST_LIST $TCONST_TERMS $SHOWS_TERMS
        rm -f $POSSIBLE_MATCHES $MATCH_COUNTS $FINAL_RESULTS
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
    if waitUntil $ynPref -N \
        "\n==> Would you like to search for another show?"; then
        printf "\n"
        terminate
        exec ./listPeopleInShows.sh
    else
        printf "Quitting...\n"
        exit
    fi
}

while getopts ":hm:y" opt; do
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

# Make sure prerequisites are satisfied
ensurePrerequisites

# Need some tempfiles
ALL_TERMS=$(mktemp)
TCONST_LIST=$(mktemp)
TCONST_TERMS=$(mktemp)
SHOW_NAMES=$(mktemp)
SHOWS_TERMS=$(mktemp)
POSSIBLE_MATCHES=$(mktemp)
MATCH_COUNTS=$(mktemp)
FINAL_RESULTS=$(mktemp)

# Required subdirectories
WORK="secondary"
mkdir -p $WORK

# ALL_TERMS="$WORK/ALL_TERMS.txt"
# TCONST_LIST="$WORK/TCONST_LIST.txt"
# TCONST_TERMS="$WORK/TCONST_TERMS.txt"
# SHOWS_TERMS="$WORK/SHOWS_TERMS.txt"
# POSSIBLE_MATCHES="$WORK/POSSIBLE_MATCHES.txt"
# MATCH_COUNTS="$WORK/MATCH_COUNTS.txt"
# FINAL_RESULTS="$WORK/FINAL_RESULTS.txt"

CREDITS_PERSON="$WORK/Credits-Person.csv"
# SHOW_NAMES="$WORK/show_names.txt"

TEMP_AWK="$WORK/conflicts.awk"
EPISODES_LIST="$WORK/tconst-episodes.txt"
NCONST_LIST="$WORK/nconst.txt"
TEMP_SHOWS="$WORK/temp_shows.csv"
UNSORTED_CREDITS="$WORK/unsorted_credits.csv"
UNSORTED_EPISODES="$WORK/unsorted_episodes.csv"

TCONST_SHOWS_PL="$WORK/tconst-shows-pl.txt"
TCONST_EPISODES_PL="$WORK/tconst-episodes-pl.txt"
TCONST_EPISODE_NAMES_PL="$WORK/tconst-episode_names-pl.txt"
NCONST_PL="$WORK/nconst-pl.txt"

ALL_CSV="$UNSORTED_EPISODES $UNSORTED_CREDITS"
ALL_OTHERS="$CREDITS_PERSON $SHOW_NAMES $TEMP_AWK $TCONST_LIST "
ALL_OTHERS+="$EPISODES_LIST $NCONST_LIST $TEMP_SHOWS"

rm -f $ALL_CSV $ALL_OTHERS

# Make sure a search term is supplied
if [ $# -eq 0 ]; then
    cat <<EOF
==> I can create data files based on show names or tconst IDs,
    such as tt1606375 -- which is the tconst for Downton Abbey.

Only one search term per line. Enter a blank line to finish.
EOF
    while read -r -p "Enter a show name or tconst ID: " searchTerm; do
        [ -z "$searchTerm" ] && break
        tr -ds '"' '[[:space:]]' <<<"$searchTerm" >>$ALL_TERMS
    done </dev/tty
    if [ ! -s "$ALL_TERMS" ]; then
        if waitUntil $ynPref -N \
            "Would you like to see the cast of Downton Abbey?"; then
            printf "tt1606375\n" >>$ALL_TERMS
        else
            loopOrExitP
        fi
    fi
    printf "\n"
fi

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

# Figure how many matches for each possible match
cut -f 3 $POSSIBLE_MATCHES | frequency -t >$MATCH_COUNTS

# Add possible matches one at a time
while read -r line; do
    count=$(cut -f 1 <<<"$line")
    match=$(cut -f 2 <<<"$line")
    if [ "$count" -eq 1 ]; then
        rg "\t$match\t" $POSSIBLE_MATCHES >>$FINAL_RESULTS
        continue
    fi
    cat <<EOF

Some titles on IMDb occur more than once, e.g. as both a movie and TV show.
You can track down the correct one by searching for it's tconst ID on IMDb.com.

EOF

    printf "I found $count shows titled \"$match\"\n"
    if [ "$count" -ge "${maxMenuSize:-25}" ]; then
        waitUntil $ynPref -Y "Should I skip trying to select one?" && continue
    fi
    # rg --color always "\t$match\t" $POSSIBLE_MATCHES | xsv table -d "\t"
    pickOptions=()
    IFS=$'\n' pickOptions=($(rg -N "\t$match\t" $POSSIBLE_MATCHES))
    pickOptions+=("Skip \"$match\"" "Quit")

    PS3="Select a number from 1-${#pickOptions[@]}: "
    COLUMNS=40
    select pickMenu in "${pickOptions[@]}"; do
        if [ "$REPLY" -ge 1 ] 2>/dev/null &&
            [ "$REPLY" -le "${#pickOptions[@]}" ]; then
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
if [ ! -s "$FINAL_RESULTS" ]; then
    printf "==> Didn't find ${RED}any${NO_COLOR} matching shows.\n"
    printf "    Check the \"Searching $numRecords records for:\" section above.\n\n"
    loopOrExitP
fi

# Found results, check with user before adding to local data
printf "These are the matches I found:\n"
if checkForExecutable -q xsv; then
    sort -f --field-separator=$'\t' --key=3 $FINAL_RESULTS | xsv table -d "\t"
else
    sort -f --field-separator=$'\t' --key=3 $FINAL_RESULTS
fi
! waitUntil $ynPref -Y && loopOrExitP
printf "\n"

# Build the lists we need
rg -N "^tt" $FINAL_RESULTS | cut -f 1 >$TCONST_LIST
rg -N "^tt" $FINAL_RESULTS | cut -f 3 | sort -f >$SHOW_NAMES

# Create a perl script to GLOBALLY convert a show tconst to a show title
rg -wNz -f $TCONST_LIST title.basics.tsv.gz |
    perl -F"\t" -lane 'print "s{\\b@F[0]\\b}\{@F[2]}g;";' >$TCONST_SHOWS_PL

### Use the tconst list to lookup episode IDs and generate an EPISODE TCONST file
rg -wNz -f $TCONST_LIST title.episode.tsv.gz |
    tee $UNSORTED_EPISODES | cut -f 1 >$EPISODES_LIST
# Create a perl script to convert an episode tconst to its parent show title
perl -F"\t" -lane 'print "s{\\b@F[0]\\b}\{@F[1]};";' $UNSORTED_EPISODES |
    perl -p -f $TCONST_SHOWS_PL >$TCONST_EPISODES_PL

# Create a perl script to convert an episode tconst to its episode title
rg -wNz -f $EPISODES_LIST title.basics.tsv.gz |
    perl -F"\t" -lane 'print "s{\\b@F[0]\\b}\{@F[3]};";' \
        >$TCONST_EPISODE_NAMES_PL

# Use tconst list to lookup principal titles & generate tconst/nconst credits csv
# Fix bogus nconst nm0745728, it should be nm0745694. Rearrange fields
# Leave the episode title field blank!
rg -wNz -f $TCONST_LIST title.principals.tsv.gz |
    rg -w -e actor -e actress -e writer -e director -e producer |
    perl -p -e 's+nm0745728+nm0745694+' |
    perl -F"\t" -lane 'printf "%s\t%s\t\t%02d\t%s\t%s\n", @F[2,0,1,3,5]' |
    tee $UNSORTED_CREDITS | cut -f 1 | sort -u >$NCONST_LIST

# Use episodes list to lookup principal titles & add to tconst/nconst credits csv
# Copy field 1 to the episode title field!
rg -wNz -f $EPISODES_LIST title.principals.tsv.gz |
    rg -w -e actor -e actress -e writer -e director -e producer |
    perl -F"\t" -lane 'printf "%s\t%s\t%s\t%02d\t%s\t%s\n", @F[2,0,0,1,3,5]' |
    tee -a $UNSORTED_CREDITS | cut -f 1 | sort -u |
    rg -v -f $NCONST_LIST >>$NCONST_LIST

# Create a perl script to convert an nconst to a name
rg -wNz -f $NCONST_LIST name.basics.tsv.gz |
    perl -F"\t" -lane 'print "s{^@F[0]\\b}\{@F[1]};";' >$NCONST_PL

# Get rid of ugly \N fields, and unneeded characters. Make sure commas are
# followed by spaces. Separate multiple characters portrayed with semicolons,
# remove quotes
perl -pi -e 's+\\N++g; tr+[]++d; s+,+, +g; s+,  +, +g; s+", "+; +g; tr+"++d;' $UNSORTED_CREDITS

# Translate tconst and nconst into titles and names
perl -pi -f $TCONST_SHOWS_PL $UNSORTED_CREDITS
perl -pi -f $TCONST_EPISODES_PL $UNSORTED_CREDITS
perl -pi -f $TCONST_EPISODE_NAMES_PL $UNSORTED_CREDITS
perl -pi -f $NCONST_PL $UNSORTED_CREDITS

# Create the sorted CREDITS spreadsheets
printf "Person\tShow Title\tEpisode Title\tRank\tJob\tCharacter Name\n" \
    >$CREDITS_PERSON
# Sort by Person (1), Show Title (2), Rank (4), Episode Title (3)
sort -f --field-separator=$'\t' --key=1,2 --key=4,4 --key=3,3 $UNSORTED_CREDITS \
    >>$CREDITS_PERSON

[ -n "$DEBUG" ] && set -v
while read -r line; do
    showName="$line"
    ./xrefCast.sh -f $CREDITS_PERSON -an "$line"
    waitUntil -k
done <$SHOW_NAMES

# Do we really want to quit?
loopOrExitP
