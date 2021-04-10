#!/usr/bin/env bash
#
# List other shows all principal cast members are in

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
findOtherShows.sh -- List other shows that principal cast members are found in.

Search IMDb titles for one show name or tconst ID. List principal cast members
who appear in more than one saved show. Use -n to limit number of results.

USAGE:
    ./findOtherShows.sh [TCONST] [SHOW TITLE]

OPTIONS:
    -h      Print this message.
    -m      Maximum matches for a show title allowed in menu, defaults to 25.
    -n      Number of principal cast members to process, 0 = all, defaults to 15.
    -r      Maximum rank of cast members in other shows to list, 0 = all, defaults to 50

EXAMPLES:
    ./findOtherShows.sh
    ./findOtherShows.sh "The Crown"
    ./findOtherShows.sh tt1399664
    ./findOtherShows.sh -n 10 Broadchurch
    ./findOtherShows.sh -n 50 -r 100 Broadchurch
EOF
}

# Don't leave tempfiles around
trap terminate EXIT
#
function terminate() {
    trimHistory -m 20 "$favoritesFile"
    if [ -n "$DEBUG" ]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
        printf "Not removing:\n" >&2
        cat <<EOT >&2
ALL_TERMS $ALL_TERMS
TCONST_TERMS $TCONST_TERMS
SHOWS_TERMS $SHOWS_TERMS
POSSIBLE_MATCHES $POSSIBLE_MATCHES
MATCH_COUNTS $MATCH_COUNTS
ALL_MATCHES $ALL_MATCHES

TCONST_LIST $TCONST_LIST
SHOW_NAMES $SHOW_NAMES
NCONST_LIST $NCONST_LIST

CREDITS_CSV $CREDITS_CSV
OTHERS_CSV $OTHERS_CSV
CAST_CSV $CAST_CSV

TMPFILE $TMPFILE
EOT
    else
        rm -f "$ALL_TERMS" "$TCONST_TERMS" "$SHOWS_TERMS" "$POSSIBLE_MATCHES"
        rm -f "$MATCH_COUNTS" "$ALL_MATCHES"
        rm -f "$TCONST_LIST" "$SHOW_NAMES" "$NCONST_LIST"
        rm -f "$CREDITS_CSV" "$OTHERS_CSV" "$CAST_CSV" "$TMPFILE"
    fi
}

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

while getopts ":hm:n:r:" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    m)
        maxMenuSize="$OPTARG"
        ;;
    n)
        maxCast="$OPTARG"
        ;;
    r)
        maxRank="$OPTARG"
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

maxCast="${maxCast:-15}"
maxRank="${maxRank:-50}"

# Make sure prerequisites are satisfied
ensurePrerequisites

# Need some tempfiles
ALL_TERMS=$(mktemp)
TCONST_TERMS=$(mktemp)
SHOWS_TERMS=$(mktemp)
POSSIBLE_MATCHES=$(mktemp)
MATCH_COUNTS=$(mktemp)
ALL_MATCHES=$(mktemp)
#
TCONST_LIST=$(mktemp)
SHOW_NAMES=$(mktemp)
NCONST_LIST=$(mktemp)
#
CREDITS_CSV=$(mktemp)
OTHERS_CSV=$(mktemp)
CAST_CSV=$(mktemp)
#
TMPFILE=$(mktemp)

# Make sure a search term is supplied
if [ $# -eq 0 ]; then
    read -r -p "Enter a show name or tconst ID: " searchTerm </dev/tty
    tr -ds '"' '[:space:]' <<<"$searchTerm" >"$ALL_TERMS"
    if [ ! -s "$ALL_TERMS" ]; then
        exit
    fi
    printf "\n"
else
    printf "$1" >"$ALL_TERMS"
fi

# Get title.basics.tsv.gz file size - should already exist but make sure...
num_TB="$(rg -N title.basics.tsv.gz "$numRecordsFile" 2>/dev/null | cut -f 2)"
[ -z "$num_TB" ] && num_TB="$(rg -cz "^t" title.basics.tsv.gz)"

# Split into two groups so we can process them differently
rg -wN "^tt[0-9]{7,8}" "$ALL_TERMS" | sort -fu >"$TCONST_TERMS"
rg -wNv "^tt[0-9]{7,8}" "$ALL_TERMS" | sort -fu >"$SHOWS_TERMS"
printf "==> Searching $num_TB records for:\n"
cat "$TCONST_TERMS" "$SHOWS_TERMS"

# Reconstitute ALL_TERMS with column guards
perl -p -e 's/^/^/; s/$/\\t/;' "$TCONST_TERMS" >"$ALL_TERMS"
perl -p -e 's/^/\\t/; s/$/\\t/;' "$SHOWS_TERMS" | sed 's+[()?]+\\&+g' >>"$ALL_TERMS"
numTerms="$(sed -n '$=' "$ALL_TERMS")"

# Get all possible matches at once
rg -NzSI -f "$ALL_TERMS" title.basics.tsv.gz | rg -v "tvEpisode" | cut -f 1-4,6 |
    perl -p -e 's+\\N++g;' | sort -f -t$'\t' --key=3 >"$POSSIBLE_MATCHES"

# Figure how many matches for each possible match
cut -f 3 "$POSSIBLE_MATCHES" | frequency -s >"$MATCH_COUNTS"

# Add possible matches one at a time, preceded by URL
while read -r line; do
    count=$(cut -f 1 <<<"$line")
    rawmatch=$(cut -f 2 <<<"$line")
    match=$(sed 's+[()?]+\\&+g' <<<"$rawmatch")
    if [ "$count" -eq 1 ]; then
        rg "\t$match\t" "$POSSIBLE_MATCHES" |
            sed 's+^+imdb.com/title/+' >>"$ALL_MATCHES"
        continue
    fi
    if [ -z "$alreadyPrintedP" ]; then
        cat <<EOF

Some titles on IMDb occur more than once, e.g. as both a movie and TV show.
You can determine which one to select using the provided links to imdb.com.
EOF
        alreadyPrintedP="yes"
    fi

    printf "\nI found $count shows titled \"$match\"\n"
    if [ "$count" -ge "${maxMenuSize:-25}" ]; then
        waitUntil "$YN_PREF" -Y "Should I skip trying to select one?" && continue
    fi

    # Create parallel tabbed array
    rg "\t$match\t" "$POSSIBLE_MATCHES" | sort -f -t$'\t' --key=2,2 --key=5,5r |
        sed 's+^+imdb.com/title/+' >"$TMPFILE"
    #
    tabbedOptions=()
    while IFS='' read -r line; do tabbedOptions+=("$line"); done <"$TMPFILE"

    # Create tsvPrinted select array
    rg "\t$match\t" "$POSSIBLE_MATCHES" | sort -f -t$'\t' --key=2,2 --key=5,5r |
        sed 's+^+imdb.com/title/+' >"$TMPFILE"
    #
    pickOptions=()
    while IFS='' read -r line; do
        pickOptions+=("$line")
    done < <(tsvPrint "$TMPFILE")
    pickOptions+=("Skip \"$match\"" "Quit")

    PS3="Select a number from 1-${#pickOptions[@]}, or type 'q(uit)': "
    COLUMNS=40
    select pickMenu in "${pickOptions[@]}"; do
        if [ "$REPLY" -ge 1 ] 2>/dev/null &&
            [ "$REPLY" -le "${#pickOptions[@]}" ]; then
            case "$pickMenu" in
            Skip*)
                break
                ;;
            Quit)
                exit
                ;;
            *)
                printf "${tabbedOptions[REPLY - 1]}\n" >>"$ALL_MATCHES"
                break
                ;;
            esac
        else
            case "$REPLY" in
            [Qq]*)
                exit
                ;;
            esac
        fi
    done </dev/tty
done <"$MATCH_COUNTS"

# Didn't find any results
if [ ! -s "$ALL_MATCHES" ]; then
    printf "\n==> I didn't find ${RED}any${NO_COLOR} matching shows.\n"
    printf "    Check the \"Searching $num_TB records for:\" section above.\n"
    exit
fi

# Remove any duplicates
sort -f "$ALL_MATCHES" | uniq -d >"$TMPFILE"
if [ -s "$TMPFILE" ]; then
    sort -fu "$ALL_MATCHES" >"$TMPFILE"
    sort -f -t$'\t' --key=2,2 --key=5,5r "$TMPFILE" >"$ALL_MATCHES"
fi

# Remember how many matches there were
numMatches=$(sed -n '$=' "$ALL_MATCHES")

# Did we find more than requested?
while [ "$numMatches" -gt "$numTerms" ]; do
    printf "\n==> I found more results than expected. What would you like to do?\n"

    # Create parallel tabbed array
    tabbedOptions=()
    while IFS='' read -r line; do tabbedOptions+=("$line"); done <"$ALL_MATCHES"

    # Create tsvPrinted select array
    pickOptions=()
    while IFS='' read -r line; do
        pickOptions+=("Remove $line")
    done < <(tsvPrint "$ALL_MATCHES")
    pickOptions+=("Keep all" "Quit")
    #
    PS3="Select a number from 1-${#pickOptions[@]}, or type 'q(uit)': "
    COLUMNS=40
    select pickMenu in "${pickOptions[@]}"; do
        if [ "$REPLY" -ge 1 ] 2>/dev/null &&
            [ "$REPLY" -le "${#pickOptions[@]}" ]; then
            case "$pickMenu" in
            Keep*)
                numMatches="$numTerms"
                break
                ;;
            Quit)
                exit
                ;;
            *)
                removeItem="${tabbedOptions[REPLY - 1]}"
                rg -v -F "$removeItem" "$ALL_MATCHES" >"$TMPFILE"
                cp "$TMPFILE" "$ALL_MATCHES"
                numMatches=$(sed -n '$=' "$ALL_MATCHES")
                break
                ;;
            esac
        else
            case "$REPLY" in
            [Qq]*)
                exit
                ;;
            esac
        fi
    done </dev/tty
done

# Found results, check with user before adding to local data
printf "\nThese are the results I can process:\n"
tsvPrint "$ALL_MATCHES"
! waitUntil "$YN_PREF" -Y && exit

# Remember how many matches there were
numMatches=$(sed -n '$=' "$ALL_MATCHES")

# Get rid of the URL we added
cp "$ALL_MATCHES" "$TMPFILE"
sed 's+imdb.com/title/++' "$TMPFILE" >"$ALL_MATCHES"
# Build the lists we need, sort alphabetically
cut -f 1,3 "$ALL_MATCHES" | sort -f -t$'\t' --key=2 >"$SHOW_NAMES"
cut -f 1 "$SHOW_NAMES" | sort >"$TCONST_LIST"

# Cache the TCONST_LIST from the "Full Cast & Crew" page
while IFS='' read -r line; do
    printf "Person\tShow Title\tEpisode Title\tRank\tJob\tCharacter Name\tnconst ID\ttconst ID\n" \
        >"$cacheDirectory/$line"
    source="https://www.imdb.com/title/$line/fullcredits?ref_=tt_ql_1"
    curl -s "$source" -o "$TMPFILE"
    awk -f getFullcredits.awk "$TMPFILE" |
        sort -f -t$'\t' --key=5,5 --key=4,4n --key=1,1 \
            >>"$cacheDirectory/$line"
    if [ "$maxCast" -gt 0 ]; then
        cut -f 7 "$cacheDirectory/$line" | rg "^nm" | head -"$maxCast" \
            >>"$NCONST_LIST"
    else
        # Save the nconst IDs
        cut -f 7 "$cacheDirectory/$line" | rg "^nm" >>"$NCONST_LIST"
    fi
done <"$TCONST_LIST"
printf "\n"

cp "$NCONST_LIST" "$TMPFILE"
sort -fu "$TMPFILE" >"$NCONST_LIST"

PTAB='%s\t%s\t%s\t%s\t%s\t%s\t%s\n'
rg -NI -f "$NCONST_LIST" "$cacheDirectory"/tt* |
    awk -F "\t" -v PF="$PTAB" '{printf(PF,$1,$5,$2,$4,$6,$7,$8)}' |
    sort | awk -F "\t" -v PF="$PTAB" \
    '{if($1==f[1]&&$3!=f[3]) {printf(PF,f[1],f[2],f[3],f[4],f[5],f[6],f[7]);
    printf(PF,$1,$2,$3,$4,$5,$6,$7)} split($0,f)}' | rg 'actor' | sort -fu |
    sort -f -t$'\t' --key=4,4n >"$CAST_CSV"

while IFS='' read -r line; do
    PTAB='%s\t%s\t%s\t%s\t%s\timdb.com/name/%s\n'
    rg "$line" "$CAST_CSV" | awk -F "\t" -v PF="$PTAB" \
        '{printf(PF,$1,$2,$3,$4,$5,$6)}' >"$CREDITS_CSV"
    PTAB='%s\t%s\t%s\t%s\t%s\timdb.com/title/%s\n'
    rg -v "$line" "$CAST_CSV" | awk -F "\t" -v PF="$PTAB" \
        '{printf(PF,$1,$2,$3,$4,$5,$7)}' >"$OTHERS_CSV"
done < <(cut -f 2 "$SHOW_NAMES")

true >"$CAST_CSV"
while IFS='' read -r line; do
    printf "$line\n" >"$TMPFILE"
    actor=$(cut -f 1 <<<"$line")
    if [ "$maxRank" -gt 0 ]; then
        rg "$actor" "$OTHERS_CSV" | sort -f -t$'\t' --key=4,4n --key=3,3 |
            awk -F "\t" -v rmax="$maxRank" '{if ($4 <= rmax) print}' >>"$TMPFILE"
    else
        rg "$actor" "$OTHERS_CSV" | sort -f -t$'\t' --key=4,4n --key=3,3 >>"$TMPFILE"
    fi
    numLines="$(sed -n '$=' "$TMPFILE")"
    if [ "$numLines" -gt 1 ]; then
        cat "$TMPFILE" >>"$CAST_CSV"
        printf " ---\t\t\t\t\t\n" >>"$CAST_CSV"
    fi
done <"$CREDITS_CSV"

# Save a full copy to use in spreadsheets
printf "Person\tJob\tShow Title\tRank\tCharacter Name\tLink\n" >"CAST_LIST.csv"
cat "$CAST_CSV" >>"CAST_LIST.csv"

printf "==> Principal cast members that appear in other shows (Name|Job|Show|Rank|Role|Link):\n"
tsvPrint -c 1 "$CAST_CSV"
