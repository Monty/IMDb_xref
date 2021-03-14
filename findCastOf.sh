#!/usr/bin/env bash
#
# List all people found in a named show on IMDb

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
findCastOf.sh -- List principal cast & crew members of shows on IMDb.

Search IMDb titles for show names or tconst IDs. A tconst ID should be unique,
but a show name can have several or even many matches. Allow user to select one
match or skip if there are too many.

List principal cast & crew members and any characters portrayed. If you search for
multiple shows, also list cast & crew members who are found in more than one.

If you don't enter a parameter on the command line, you'll be prompted for
input.

USAGE:
    ./findCastOf.sh [TCONST...] [SHOW TITLE...]

OPTIONS:
    -h      Print this message.
    -d      Duplicates -- Only list cast & crew members found in more than one show.
    -m      Maximum matches for a show title allowed in menu - defaults to 25.
    -f      File -- Add to specific file rather than the default $favoritesFile.
    -s      Short - don't list details, just ask about adding to $favoritesFile.

EXAMPLES:
    ./findCastOf.sh
    ./findCastOf.sh -d
    ./findCastOf.sh "The Crown"
    ./findCastOf.sh tt1606375
    ./findCastOf.sh tt1606375 tt1399664 "Broadchurch"
    ./findCastOf.sh -s tt1606375 tt1399664 "Broadchurch"
    ./findCastOf.sh -d "The Night Manager" "The Crown" "The Durrells in Corfu"
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
ALL_MATCHES $ALL_MATCHES

CACHE_LIST $CACHE_LIST
SEARCH_LIST $SEARCH_LIST
TCONST_LIST $TCONST_LIST
SHOW_NAMES $SHOW_NAMES
EPISODES_LIST $EPISODES_LIST
NCONST_LIST $NCONST_LIST

SHOWS_PL $SHOWS_PL
EPISODES_PL $EPISODES_PL
EPISODE_NAMES_PL $EPISODE_NAMES_PL
NAMES_PL $NAMES_PL

CREDITS_CSV $CREDITS_CSV
EPISODES_CSV $EPISODES_CSV
CAST_CSV $CAST_CSV

TMPFILE $TMPFILE
EOT
        [ ! -s "$favoritesFile" ] && printf "favoritesFile $favoritesFile\n" >&2
    else
        rm -f "$ALL_TERMS" "$TCONST_TERMS" "$SHOWS_TERMS" "$POSSIBLE_MATCHES"
        rm -f "$MATCH_COUNTS" "$ALL_MATCHES" "$CACHE_LIST" "$SEARCH_LIST"
        rm -f "$TCONST_LIST" "$SHOW_NAMES" "$EPISODES_LIST" "$NCONST_LIST"
        rm -f "$SHOWS_PL" "$EPISODES_PL" "$EPISODE_NAMES_PL" "$NAMES_PL"
        rm -f "$CREDITS_CSV" "$EPISODES_CSV" "$CAST_CSV" "$TMPFILE"
        [ ! -s "$favoritesFile" ] && rm -f "$favoritesFile"
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
    printf "\n"
    terminate
    [ -n "$NO_MENUS" ] && exit
    exec ./start.command
}

while getopts ":hf:dm:s" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    f)
        favoritesFile="$OPTARG"
        ;;
    d)
        MULTIPLE_NAMES_ONLY="yes"
        ;;
    m)
        maxMenuSize="$OPTARG"
        ;;
    s)
        SHORT="yes"
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
TCONST_TERMS=$(mktemp)
SHOWS_TERMS=$(mktemp)
POSSIBLE_MATCHES=$(mktemp)
MATCH_COUNTS=$(mktemp)
ALL_MATCHES=$(mktemp)
#
CACHE_LIST=$(mktemp)
SEARCH_LIST=$(mktemp)
TCONST_LIST=$(mktemp)
SHOW_NAMES=$(mktemp)
EPISODES_LIST=$(mktemp)
NCONST_LIST=$(mktemp)
#
SHOWS_PL=$(mktemp)
EPISODES_PL=$(mktemp)
EPISODE_NAMES_PL=$(mktemp)
NAMES_PL=$(mktemp)
#
CREDITS_CSV=$(mktemp)
EPISODES_CSV=$(mktemp)
CAST_CSV=$(mktemp)
#
TMPFILE=$(mktemp)

# Make sure a search term is supplied
if [ $# -eq 0 ]; then
    cat <<EOF

==> I can find principal cast & crew members based on show names or tconst IDs,
    such as tt1606375 -- which is the tconst for Downton Abbey taken from this URL:
    https://www.imdb.com/title/tt1606375/

Only one search term per line. Enter a blank line to finish. Enter two or
more shows to see any principal cast & crew members they have in common.
EOF
    while read -r -p "Enter a show name or tconst ID: " searchTerm; do
        [ -z "$searchTerm" ] && break
        tr -ds '"' '[:space:]' <<<"$searchTerm" >>"$ALL_TERMS"
    done </dev/tty
    if [ ! -s "$ALL_TERMS" ]; then
        if waitUntil "$YN_PREF" -N \
            "Would you like to see the principal cast & crew of Downton Abbey as an example?"; then
            printf "tt1606375\n" >>"$ALL_TERMS"
        else
            loopOrExitP
        fi
    fi
    printf "\n"
fi

# Let used know what favorites file we're using.
printf "==> Any favorites you save will be added to: ${BLUE}$favoritesFile\n${NO_COLOR}\n"

# Get title.basics.tsv.gz file size - should already exist but make sure...
num_TB="$(rg -N title.basics.tsv.gz "$numRecordsFile" 2>/dev/null | cut -f 2)"
[ -z "$num_TB" ] && num_TB="$(rg -cz "^t" title.basics.tsv.gz)"

# Setup ALL_TERMS with one search term per line
for param in "$@"; do
    printf "$param\n" >>"$ALL_TERMS"
done
# Split into two groups so we can process them differently
rg -wN "^tt[0-9]{7,8}" "$ALL_TERMS" | sort -fu >"$TCONST_TERMS"
rg -wNv "^tt[0-9]{7,8}" "$ALL_TERMS" | sort -fu >"$SHOWS_TERMS"
printf "==> Searching $num_TB records for:\n"
cat "$TCONST_TERMS" "$SHOWS_TERMS"

# Reconstitute ALL_TERMS with column guards
perl -p -e 's/^/^/; s/$/\\t/;' "$TCONST_TERMS" >"$ALL_TERMS"
perl -p -e 's/^/\\t/; s/$/\\t/;' "$SHOWS_TERMS" >>"$ALL_TERMS"
numTerms="$(sed -n '$=' "$ALL_TERMS")"

# Get all possible matches at once
rg -NzSI -f "$ALL_TERMS" title.basics.tsv.gz | rg -v "tvEpisode" | cut -f 1-4,6 |
    perl -p -e 's+\\N++g;' | sort -f -t$'\t' --key=3 >"$POSSIBLE_MATCHES"

# Figure how many matches for each possible match
cut -f 3 "$POSSIBLE_MATCHES" | frequency -s >"$MATCH_COUNTS"

# Add possible matches one at a time, preceded by URL
while read -r line; do
    count=$(cut -f 1 <<<"$line")
    match=$(cut -f 2 <<<"$line")
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
                loopOrExitP
                ;;
            *)
                printf "${tabbedOptions[REPLY - 1]}\n" >>"$ALL_MATCHES"
                break
                ;;
            esac
        else
            case "$REPLY" in
            [Qq]*)
                loopOrExitP
                ;;
            esac
        fi
    done </dev/tty
done <"$MATCH_COUNTS"

# Didn't find any results
if [ ! -s "$ALL_MATCHES" ]; then
    printf "\n==> I didn't find ${RED}any${NO_COLOR} matching shows.\n"
    printf "    Check the \"Searching $num_TB records for:\" section above.\n"
    loopOrExitP
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
                loopOrExitP
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
                loopOrExitP
                ;;
            esac
        fi
    done </dev/tty
done

# Found results, check with user before adding to local data
printf "\nThese are the results I can process:\n"
tsvPrint "$ALL_MATCHES"
! waitUntil "$YN_PREF" -Y && loopOrExitP
printf "\n"

# Remember how many matches there were
numMatches=$(sed -n '$=' "$ALL_MATCHES")

# Get rid of the URL we added
cp "$ALL_MATCHES" "$TMPFILE"
sed 's+imdb.com/title/++' "$TMPFILE" >"$ALL_MATCHES"
# Build the lists we need, sort alphabetically
cut -f 1,3 "$ALL_MATCHES" | sort -f -t$'\t' --key=2 >"$SHOW_NAMES"
cut -f 1 "$SHOW_NAMES" | sort >"$SEARCH_LIST"

# Save search in case we want to redo or add to favorites
printHistory "$favoritesFile" >"$TMPFILE"
[ -n "$(diff "$TMPFILE" "$ALL_MATCHES")" ] &&
    saveHistory "$ALL_MATCHES" "$favoritesFile"

# Figure out which tconst IDs are cached and which aren't
ls -1 "$cacheDirectory" | rg "^tt" >"$CACHE_LIST"
comm -13 "$CACHE_LIST" "$SEARCH_LIST" >"$TCONST_LIST"

# Use maxCast to limit size of result, but only if -ge 10
maxCast=0

if [ -n "$FULLCAST" ]; then
    # Used to debug possibly missing data from the .tsv.gz files

    # Is FULLCAST an integer?
    if [ "$FULLCAST" -eq "$FULLCAST" ] 2>/dev/null; then
        maxCast="$FULLCAST"
    fi

    # Cache the TCONST_LIST from the "Full Cast & Crew" page
    while IFS='' read -r line; do
        printf "Person\tShow Title\tEpisode Title\tRank\tJob\tCharacter Name\n" \
            >"$cacheDirectory/$line"
        source="https://www.imdb.com/title/$line/fullcredits?ref_=tt_ql_1"
        printf "Reading https://www.imdb.com/title/$line\n"
        curl -s "$source" -o "$TMPFILE"
        awk -f getFullcredits.awk "$TMPFILE" |
            sort -f -t$'\t' --key=5,5 --key=4,4n --key=1,1 \
                >>"$cacheDirectory/$line"
    done <"$TCONST_LIST"
    printf "\n"
    # Recompute which tconst IDs are cached and which aren't
    ls -1 "$cacheDirectory" | rg "^tt" >"$CACHE_LIST"
    comm -13 "$CACHE_LIST" "$SEARCH_LIST" >"$TCONST_LIST"
fi

# If everything is cached, skip searching entirely
if [ -n "$(rg -c "^tt" "$TCONST_LIST")" ]; then

    # Create a perl script to GLOBALLY convert a show tconst to a show title
    printf "==> Searching $num_TB records for show titles.\n"
    rg -wNz -f "$TCONST_LIST" title.basics.tsv.gz |
        perl -F"\t" -lane 'print "s{\\b@F[0]\\b}\{@F[2]}g;";' >"$SHOWS_PL"

    # Use tconst list to lookup episode IDs and generate an EPISODE TCONST file
    rg -wNz -f "$TCONST_LIST" title.episode.tsv.gz |
        tee "$EPISODES_CSV" | cut -f 1 >"$EPISODES_LIST"
    # Create a perl script to convert an episode tconst to its parent show title
    perl -F"\t" -lane 'print "s{\\b@F[0]\\b}\{@F[1]};";' "$EPISODES_CSV" |
        perl -p -f "$SHOWS_PL" >"$EPISODES_PL"

    # Create a perl script to convert an episode tconst to its episode title
    rg -wNz -f "$EPISODES_LIST" title.basics.tsv.gz |
        perl -F"\t" -lane 'print "s{\\b@F[0]\\b}\{@F[3]};";' \
            >"$EPISODE_NAMES_PL"

    # Get title.principals.tsv.gz file size - should already exist but make sure...
    num_TP="$(rg -N title.principals.tsv.gz "$numRecordsFile" 2>/dev/null | cut -f 2)"
    [ -z "$num_TP" ] && num_TP="$(rg -cz "^t" title.principals.tsv.gz)"

    # Use tconst list to lookup principal titles and generate credits csv
    # Fix bogus nconst nm0745728, it should be nm0745694. Rearrange fields
    # Leave the episode title field blank!
    printf "==> Searching $num_TP records for principal cast & crew members.\n\n"
    rg -wNz -f "$TCONST_LIST" title.principals.tsv.gz |
        perl -p -e 's+nm0745728+nm0745694+' |
        perl -F"\t" -lane 'printf "%s\t%s\t\t%02d\t%s\t%s\n", @F[2,0,1,3,5]' |
        tee "$CREDITS_CSV" | cut -f 1 | sort -u | tee "$TMPFILE" >"$NCONST_LIST"

    # Use episodes list to lookup principal titles and add to credits csv
    # Copy field 1 to the episode title field!
    rg -wNz -f "$EPISODES_LIST" title.principals.tsv.gz |
        perl -F"\t" -lane 'printf "%s\t%s\t%s\t%02d\t%s\t%s\n", @F[2,0,0,1,3,5]' |
        tee -a "$CREDITS_CSV" | cut -f 1 | sort -u |
        rg -v -f "$TMPFILE" >>"$NCONST_LIST"

    # Create a perl script to convert an nconst to a name
    rg -wNz -f "$NCONST_LIST" name.basics.tsv.gz |
        perl -F"\t" -lane 'print "s{^@F[0]\\b}\{@F[1]};";' >"$NAMES_PL"

    # Get rid of ugly \N fields, and unneeded characters. Make sure commas are
    # followed by spaces. Separate multiple characters portrayed with semicolons,
    # remove quotes
    perl -pi -e 's+\\N++g; tr+[]++d; s+,+, +g; s+,  +, +g; s+", "+; +g; tr+"++d;' \
        "$CREDITS_CSV"

    # Translate tconst and nconst into titles and names
    perl -pi -f "$SHOWS_PL" "$CREDITS_CSV"
    perl -pi -f "$EPISODES_PL" "$CREDITS_CSV"
    perl -pi -f "$EPISODE_NAMES_PL" "$CREDITS_CSV"
    perl -pi -f "$NAMES_PL" "$CREDITS_CSV"

    # Switch from actor|actress to actor only to be compatible with web
    perl -pi -e 's+\tactress\t+\tactor\t+;' "$CREDITS_CSV"

    # Create the sorted RESULTS
    printf "Person\tShow Title\tEpisode Title\tRank\tJob\tCharacter Name\n" \
        >"$CAST_CSV"
    # Sort by Person (1), Show Title (2), Rank (4), Episode Title (3)
    sort -f -t$'\t' --key=1,2 --key=4,4 --key=3,3 "$CREDITS_CSV" \
        >>"$CAST_CSV"
fi

# Make sure we have an empty file
true >"$TMPFILE"

while read -r line; do
    cacheName=$(cut -f 1 <<<"$line")
    cacheFile="$cacheDirectory/$cacheName"
    showName=$(cut -f 2 <<<"$line")
    allNames+=("$showName")
    if [ -z "$(rg -c "^$cacheName$" "$CACHE_LIST")" ]; then
        rg "\t$showName\t" "$CAST_CSV" >"$cacheFile"
    fi
    cat "$cacheFile" >>"$TMPFILE"
    if [ -z "$MULTIPLE_NAMES_ONLY" ] && [ -z "$SHORT" ]; then
        if [ "$(rg -c "Person\tShow Title\tEpisode " "$cacheFile")" ]; then
            showName="$(tail -1 "$cacheFile" | cut -f 2)"
            awk -F "\t" '{printf("%s\t%s\t%s\t%s\n",$1,$5,$2,$6)}' "$cacheFile" |
                rg "$showName" >"$CAST_CSV"
            if [ "$maxCast" -ge 10 ]; then
                printf "==> Top $maxCast cast & crew members in IMDb billing order (Name|Job|Show|Role):\n"
                tsvPrint "$CAST_CSV" | head -"$maxCast"
            else
                printf "==> All cast & crew members in IMDb billing order (Name|Job|Show|Role):\n"
                tsvPrint "$CAST_CSV"
            fi
        else
            ./xrefCast.sh -f "$cacheFile" -pn "$showName"
        fi
        waitUntil -k
    fi
done <"$SHOW_NAMES"

# Any results? If not, don't continue.
if [ ! -s "$TMPFILE" ]; then
    printf "==> I didn't find ${RED}any${NO_COLOR} matching records.\n"
    printf "    Check the \"Searching for:\" section above.\n"
    loopOrExitP
fi

# Check for mutliples if appropriate
if [ -z "$SHORT" ]; then
    if [ "$numMatches" -ne 1 ] || [ -n "$MULTIPLE_NAMES_ONLY" ]; then
        ./xrefCast.sh -f "$TMPFILE" -dn "${allNames[@]}"
    else
        printf "\n"
    fi
fi

touch "$favoritesFile"
# Check whether shows searched are already in favoritesFile
# shellcheck disable=SC2154      # favoritesFile is defined
rg -IN "^tt" "$favoritesFile" | cut -f 1 | sort -u >"$CACHE_LIST"
printHistory "$favoritesFile" | rg -IN "^tt" | cut -f 1 |
    sort -u >"$TMPFILE"
comm -13 "$CACHE_LIST" "$TMPFILE" >"$TCONST_LIST"
rg -f "$TCONST_LIST" "$ALL_MATCHES" >"$TMPFILE"
if [ -s "$TMPFILE" ]; then
    numNew=$(sed -n '$=' "$TMPFILE")
    _vb="is"
    _pron="it"
    [ "$numNew" -gt 1 ] && plural="s" && _vb="are" && _pron="them"
    printf "==> I found %s show%s that %s not in $favoritesFile\n" \
        "$numNew" "$plural" "$_vb"
    tsvPrint "$TMPFILE"
    if waitUntil "$YN_PREF" -Y \
        "\n==> Shall I add $_pron to $favoritesFile?"; then
        # shellcheck disable=SC2094      # param is a string not a file
        printHistory "$favoritesFile" >>"$favoritesFile"
        ./augment_tconstFiles.sh -ay "$favoritesFile"
        printf "\n"
    else
        AW=" anyway"
    fi
else
    printf "==> I didn't find any shows that are not already in $favoritesFile\n"
    AW=" anyway"
fi
# Check if user wants to update data files, even if no new favorites.
waitUntil "$YN_PREF" -Y "==> Shall I update your data files$AW?" &&
    ./generateXrefData.sh -q

loopOrExitP
