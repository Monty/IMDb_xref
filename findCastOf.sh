#!/usr/bin/env bash
#
# List all people found in a named show on IMDb

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

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
    -n      Number of cast & crew members to list, 0 = all, defaults to 0.
            "All" means all principals: this branch reads title.principals.tsv.gz,
            which carries roughly ten names per title. The full cast of hundreds
            is only available on the live-fetch branch, which scrapes the
            fullcredits page.
    -f      File -- Add to specific file rather than the default $favoritesFile.
    -s      Short - don't list details, just ask about adding to $favoritesFile.

EXAMPLES:
    ./findCastOf.sh
    ./findCastOf.sh -d
    ./findCastOf.sh "The Crown"
    ./findCastOf.sh -n 10 "The Crown"
    ./findCastOf.sh tt1606375
    ./findCastOf.sh tt1606375 tt1399664 "Broadchurch"
    ./findCastOf.sh -s tt1606375 tt1399664 "Broadchurch"
    ./findCastOf.sh -d "The Night Manager" "The Crown" "The Durrells"
EOF
}

# Don't leave tempfiles around
trap terminate EXIT
#
function terminate() {
    trimHistory -m 20 "$favoritesFile"
    if [[ -n $DEBUG ]]; then
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

CAST_CSV $CAST_CSV

TMPFILE $TMPFILE
EOT
        [[ ! -s $favoritesFile ]] && printf "favoritesFile $favoritesFile\n" >&2
    else
        rm -f "$ALL_TERMS" "$TCONST_TERMS" "$SHOWS_TERMS" "$POSSIBLE_MATCHES"
        rm -f "$MATCH_COUNTS" "$ALL_MATCHES" "$CACHE_LIST" "$SEARCH_LIST"
        rm -f "$TCONST_LIST" "$SHOW_NAMES"
        rm -f "$CAST_CSV" "$TMPFILE"
        [[ ! -s $favoritesFile ]] && rm -f "$favoritesFile"
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
    [[ -n $NO_MENUS ]] && exit
    exec ./start.command
}

while getopts ":hf:dm:n:s" opt; do
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
    n)
        maxCast="$OPTARG"
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
#
CAST_CSV=$(mktemp)
#
TMPFILE=$(mktemp)

# Make sure a search term is supplied
if [[ $# -eq 0 ]]; then
    cat <<EOF

==> I can find principal cast & crew members based on show names or tconst IDs,
    such as tt1606375 -- which is the tconst for Downton Abbey taken from this URL:
    https://www.imdb.com/title/tt1606375/

Only one search term per line. Enter a blank line to finish. Enter two or
more shows to see any principal cast & crew members they have in common.
EOF
    while read -r -p "Enter a show name or tconst ID: " searchTerm; do
        [[ -z $searchTerm ]] && break
        tr -ds '"' '[:space:]' <<<"$searchTerm" >>"$ALL_TERMS"
    done </dev/tty
    if [[ ! -s $ALL_TERMS ]]; then
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
[[ -z $num_TB ]] && num_TB="$(rg -cz "^t" title.basics.tsv.gz)"

# Set up ALL_TERMS with one search term per line
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
    # shellcheck disable=SC2001      # too complex for ${variable//search/replace}
    match=$(sed 's+[()?]+\\&+g' <<<"$rawmatch")
    if [[ $count -eq 1 ]]; then
        rg "\t$match\t" "$POSSIBLE_MATCHES" |
            sed 's+^+imdb.com/title/+' >>"$ALL_MATCHES"
        continue
    fi
    if [[ -z $alreadyPrintedP ]]; then
        cat <<EOF

Some titles on IMDb occur more than once, e.g. as both a movie and TV show.
You can determine which one to select using the provided links to imdb.com.
EOF
        alreadyPrintedP="yes"
    fi

    printf "\nI found $count shows titled \"$match\"\n"
    if [[ $count -ge ${maxMenuSize:-25} ]]; then
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
        if [[ $REPLY -ge 1 ]] 2>/dev/null &&
            [[ $REPLY -le ${#pickOptions[@]} ]]; then
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
if [[ ! -s $ALL_MATCHES ]]; then
    printf "\n==> I didn't find ${RED}any${NO_COLOR} matching shows.\n"
    printf "    Check the \"Searching $num_TB records for:\" section above.\n"
    loopOrExitP
fi

# Remove any duplicates
sort -f "$ALL_MATCHES" | uniq -d >"$TMPFILE"
if [[ -s $TMPFILE ]]; then
    sort -fu "$ALL_MATCHES" >"$TMPFILE"
    sort -f -t$'\t' --key=2,2 --key=5,5r "$TMPFILE" >"$ALL_MATCHES"
fi

# Remember how many matches there were
numMatches=$(sed -n '$=' "$ALL_MATCHES")

# Did we find more than requested?
while [[ $numMatches -gt $numTerms ]]; do
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
        if [[ $REPLY -ge 1 ]] 2>/dev/null &&
            [[ $REPLY -le ${#pickOptions[@]} ]]; then
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
[[ -n "$(diff "$TMPFILE" "$ALL_MATCHES")" ]] &&
    saveHistory "$ALL_MATCHES" "$favoritesFile"

# Figure out which tconst IDs are cached and which aren't
ls -1 "$cacheDirectory" | rg "^tt" >"$CACHE_LIST"
comm -13 "$CACHE_LIST" "$SEARCH_LIST" >"$TCONST_LIST"

# maxCast caps how many billing-order rows we display. 0 means all, matching
# findOtherShows.sh -n. Set with -n rather than read from the FULLCAST
# environment variable, which used to set it here: FULLCAST also selected a data
# source in xrefCast.sh and iQuery.sh, so one variable meant three unrelated
# things across the branch, and only values >= 10 took effect here while
# findOtherShows.sh honored any value -- so -n 5 capped at 5 in one script and
# silently meant "no cap" in the other. Both are now plain -n options.
#
# The cast itself is read from the .gz files below. The live-fetch path FULLCAST
# used to drive -- curl the fullcredits page and parse it with
# getFullcredits.awk -- is retired: IMDb 403s a bot User-Agent, WAF-challenges a
# browser one, and the fullcredits page is React-rendered now, so the awk matched
# nothing and left header-only cache files that masked the real data.
maxCast="${maxCast:-0}"
if [[ ! $maxCast =~ ^[0-9]+$ ]]; then
    printf "==> [${YELLOW}Warning${NO_COLOR}] Ignoring non-numeric -n " >&2
    printf "${YELLOW}$maxCast${NO_COLOR}. Listing all cast & crew members.\n\n" >&2
    maxCast=0
fi

# Let the user know if any shows still need a cache built. The cast itself is
# built per-show by buildShowCache below, which joins title.principals.tsv.gz
# and name.basics.tsv.gz into the shared 8-column format -- the same function
# findOtherShows.sh uses, so a show cached by either script now carries the
# nconst and tconst IDs the cross-reference needs.
numUncached="$(rg -c "^tt" "$TCONST_LIST")"
[[ -n $numUncached ]] &&
    printf "==> Building a cast cache for %s show(s) from the local datasets.\n\n" \
        "$numUncached"

# Make sure we have an empty file
true >"$TMPFILE"

while read -r line; do
    cacheName=$(cut -f 1 <<<"$line")
    cacheFile="$cacheDirectory/$cacheName"
    showName=$(cut -f 2 <<<"$line")
    allNames+=("$showName")
    if [[ -z "$(rg -c "^$cacheName$" "$CACHE_LIST")" ]]; then
        buildShowCache "$cacheName" "$showName"
    fi
    [[ -s $cacheFile ]] || continue
    cat "$cacheFile" >>"$TMPFILE"
    if [[ -z $MULTIPLE_NAMES_ONLY ]] && [[ -z $SHORT ]]; then
        # Cast is read from the shared 8-column cache (Person|Show|Episode|Rank|
        # Job|Character|nconst|tconst, no header row); the display needs only the
        # first six. Collapse to unique Name|Job|Show|Role rows in IMDb billing
        # order (lowest Rank first). Character-name variants (e.g. "Simon
        # Magellan" vs "SimonMagellan") intentionally stay separate.
        sort -f -t$'\t' --key=4,4n "$cacheFile" |
            awk -F "\t" '!seen[$1 FS $5 FS $2 FS $6]++ {printf("%s\t%s\t%s\t%s\n",$1,$5,$2,$6)}' >"$CAST_CSV"
        # Says "principal" rather than "all" deliberately. The cast comes from
        # title.principals.tsv.gz -- roughly ten names per title -- so there is
        # no fuller list to be had here, and "All cast & crew members" promised
        # the hundreds-long fullcredits page that only live-fetch can reach.
        if [[ $maxCast -gt 0 ]]; then
            printf "==> Top $maxCast principal cast & crew members in IMDb billing order (Name|Job|Show|Role):\n"
            tsvPrint "$CAST_CSV" | head -"$maxCast"
        else
            printf "==> Principal cast & crew members in IMDb billing order (Name|Job|Show|Role):\n"
            tsvPrint "$CAST_CSV"
        fi
        waitUntil -k
    fi
done <"$SHOW_NAMES"

# Any results? If not, don't continue.
if [[ ! -s $TMPFILE ]]; then
    printf "==> I didn't find ${RED}any${NO_COLOR} matching records.\n"
    printf "    Check the \"Searching for:\" section above.\n"
    loopOrExitP
fi

# Check for mutliples if appropriate
if [[ -z $SHORT ]]; then
    if [[ $numMatches -ne 1 ]] || [[ -n $MULTIPLE_NAMES_ONLY ]]; then
        ./xrefCast.sh -f "$TMPFILE" -dn "${allNames[@]}"
    else
        printf "\n"
    fi
fi

touch "$favoritesFile"
# Check whether shows searched are already in favoritesFile
# shellcheck disable=SC2154     # favoritesFile is defined
rg -IN "^tt" "$favoritesFile" | cut -f 1 | sort -u >"$CACHE_LIST"
printHistory "$favoritesFile" | rg -IN "^tt" | cut -f 1 |
    sort -u >"$TMPFILE"
comm -13 "$CACHE_LIST" "$TMPFILE" >"$TCONST_LIST"
rg -f "$TCONST_LIST" "$ALL_MATCHES" >"$TMPFILE"
if [[ -s $TMPFILE ]]; then
    numNew=$(sed -n '$=' "$TMPFILE")
    _vb="is"
    _pron="it"
    [[ $numNew -gt 1 ]] && plural="s" && _vb="are" && _pron="them"
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
