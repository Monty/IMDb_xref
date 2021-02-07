#!/usr/bin/env bash
#
# Add a tconst to a file

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
createTconstFile.sh -- Add a tconst ID for any show to a file.

Search IMDb titles for a match to a tconst or a show name. A tconst should be
unique, but a show name can have several or even many matches. Allow user to
select one match or skip if there are too many.

If you don't enter a parameter on the command line, you'll be prompted for
input.

USAGE:
    ./createTconstFile.sh [-f TCONST_FILE] [TCONST...] [SHOW TITLE...]

OPTIONS:
    -h      Print this message.
    -m      Maximum matches for a show title allowed in menu - defaults to 25
    -f      File -- Add to specific file rather than the default $USER.tconst

EXAMPLES:
    ./createTconstFile.sh
    ./createTconstFile.sh tt1606375
    ./createTconstFile.sh tt1606375 tt1399664 "Broadchurch"
    ./createTconstFile.sh "The Crown"
    ./createTconstFile.sh -f Dramas.tconst tt1606375
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
TCONST_TERMS $TCONST_TERMS
SHOWS_TERMS $SHOWS_TERMS
POSSIBLE_MATCHES $POSSIBLE_MATCHES
MATCH_COUNTS $MATCH_COUNTS
FINAL_RESULTS $FINAL_RESULTS
EOT
    else
        rm -f "$ALL_TERMS" "$TCONST_TERMS" "$SHOWS_TERMS" "$POSSIBLE_MATCHES"
        rm -f "$MATCH_COUNTS" "$FINAL_RESULTS"
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
    if waitUntil "$YN_PREF" -N "\n==> Would you like to search for another show?"; then
        printf "\n"
        terminate
        [ -n "$TCONST_FILE" ] && exec ./createTconstFile.sh -f "$TCONST_FILE"
        exec ./createTconstFile.sh
    else
        printf "Quitting...\n"
        exit
    fi
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
        printf "==> Option -$OPTARG requires a 'maximum menu size' argument'.\n" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

# Make sure prerequisites are satisfied
ensurePrerequisites

# Need some tempfiles
ALL_TERMS=$(mktemp)
TCONST_TERMS=$(mktemp)
SHOWS_TERMS=$(mktemp)
POSSIBLE_MATCHES=$(mktemp)
MATCH_COUNTS=$(mktemp)
FINAL_RESULTS=$(mktemp)

# Make sure a search term is supplied
if [ $# -eq 0 ]; then
    cat <<EOF
==> I can create data files based on show names or tconst IDs,
    such as tt1606375 -- which is the tconst for Downton Abbey.

Only one search term per line. Enter a blank line to finish.
EOF
    while read -r -p "Enter a show name or tconst ID: " searchTerm; do
        [ -z "$searchTerm" ] && break
        tr -ds '"' '[:space:]' <<<"$searchTerm" >>"$ALL_TERMS"
    done </dev/tty
    if [ ! -s "$ALL_TERMS" ]; then
        if waitUntil "$YN_PREF" -N \
            "Would you like me to add the Downton Abbey tconst for you?"; then
            printf "tt1606375\n" >>"$ALL_TERMS"
        else
            loopOrExitP
        fi
    fi
    printf "\n"
fi

# Do the work of adding the matches to the TCONST_FILE
function addToFileP() {
    if waitUntil "$YN_PREF" -Y "\nShall I add them to $TCONST_FILE?"; then
        printf "OK. Adding...\n"
        rg -N "^tt" "$FINAL_RESULTS" >>"$TCONST_FILE"
        waitUntil "$YN_PREF" -Y "\nShall I sort $TCONST_FILE by title?" &&
            ./augment_tconstFiles.sh -y "$TCONST_FILE"
        waitUntil "$YN_PREF" -Y "\nShall I update your data files?" &&
            ./generateXrefData.sh -q
    else
        printf "Skipping....\n"
    fi
}

# Get a TCONST_FILE
[ -z "$TCONST_FILE" ] && TCONST_FILE="$USER.tconst"
#
printf "==> Adding tconst IDs to: ${BLUE}$TCONST_FILE${NO_COLOR}\n\n"

# Get gz file size - which should already exist but make sure...
numRecords="$(rg -N title.basics.tsv.gz "$numRecordsFile" 2>/dev/null | cut -f 2)"
[ -z "$numRecords" ] && numRecords="$(rg -cz "^t" title.basics.tsv.gz)"

# Setup ALL_TERMS with one search term per line
for param in "$@"; do
    printf "$param\n" >>"$ALL_TERMS"
done
# Split into two groups so we can process them differently
rg -wN "^tt[0-9]{7,8}" "$ALL_TERMS" | sort -fu >"$TCONST_TERMS"
rg -wNv "^tt[0-9]{7,8}" "$ALL_TERMS" | sort -fu >"$SHOWS_TERMS"
printf "==> Searching $numRecords records for:\n"
cat "$TCONST_TERMS" "$SHOWS_TERMS"

# Reconstitute ALL_TERMS with column guards
perl -p -e 's/^/^/; s/$/\\t/;' "$TCONST_TERMS" >"$ALL_TERMS"
perl -p -e 's/^/\\t/; s/$/\\t/;' "$SHOWS_TERMS" >>"$ALL_TERMS"

# Get all possible matches at once
rg -NzSI -f "$ALL_TERMS" title.basics.tsv.gz | rg -v "tvEpisode" | cut -f 1-4,6 |
    perl -p -e 's+\\N++g;' | sort -f -t$'\t' --key=3 >"$POSSIBLE_MATCHES"

# Figure how many matches for each possible match
cut -f 3 "$POSSIBLE_MATCHES" | frequency -s >"$MATCH_COUNTS"

# Add possible matches one at a time
while read -r line; do
    count=$(cut -f 1 <<<"$line")
    match=$(cut -f 2 <<<"$line")
    if [ "$count" -eq 1 ]; then
        rg "\t$match\t" "$POSSIBLE_MATCHES" | sed 's+^+imdb.com/title/+' \
            >>"$FINAL_RESULTS"
        continue
    fi
    cat <<EOF

Some titles on IMDb occur more than once, e.g. as both a movie and TV show.
You can track down the correct one by searching for it's tconst ID on IMDb.com.

EOF

    printf "I found $count shows titled \"$match\"\n"
    if [ "$count" -ge "${maxMenuSize:-25}" ]; then
        waitUntil "$YN_PREF" -Y "Should I skip trying to select one?" && continue
    fi
    # rg --color always -N "\t$match\t" "$POSSIBLE_MATCHES" | xsv table -d "\t"
    pickOptions=()
    while IFS=$'\n' read -r line; do
        pickOptions+=("imdb.com/title/$line")
    done < <(rg -N "\t$match\t" "$POSSIBLE_MATCHES" |
        sort -f -t$'\t' --key=2,2 --key=5,5r)
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
                printf "$pickMenu\n" >>"$FINAL_RESULTS"
                break
                ;;
            esac
            break
        else
            printf "Your selection must be a number from 1-${#pickOptions[@]}\n"
        fi
    done </dev/tty
done <"$MATCH_COUNTS"
printf "\n"

# Didn't find any results
if [ ! -s "$FINAL_RESULTS" ]; then
    printf "==> Didn't find ${RED}any${NO_COLOR} matching shows.\n"
    printf "    Check the \"Searching $numRecords records for:\" section above.\n\n"
    loopOrExitP
fi

# Found results, check with user before adding to local data
printf "These are the matches I can add:\n"
if checkForExecutable -q xsv; then
    xsv table -d "\t" "$FINAL_RESULTS"
else
    cat "$FINAL_RESULTS"
fi

# Get rid of the URL preface we added
sed -i '' 's+imdb.com/title/++' "$FINAL_RESULTS"

# Do we want  to add it?
addToFileP

# Do we really want to quit?
loopOrExitP
