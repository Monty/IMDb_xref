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

A show title only matches the title types listed in rg_types.rgx. A tconst
bypasses that list, so it can look up a tvEpisode, short, or any other type.

USAGE:
    ./findOtherShows.sh [TCONST] [SHOW TITLE]

OPTIONS:
    -h      Print this message.
    -a      Allow all title types -- normally only those in rg_types.rgx match.
            No effect on a tconst, which always bypasses the type list.
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
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
        printf "Not removing:\n" >&2
        cat <<EOT >&2
ALL_TERMS $ALL_TERMS
TCONST_TERMS $TCONST_TERMS
TCONST_PATTERNS $TCONST_PATTERNS
SHOWS_TERMS $SHOWS_TERMS
SHOWS_PATTERNS $SHOWS_PATTERNS
SHOWS_RAW $SHOWS_RAW
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
        rm -f "$TCONST_PATTERNS" "$SHOWS_PATTERNS" "$SHOWS_RAW"
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

function loopOrExitP() {
    printf "\n"
    terminate
    [[ -n $NO_MENUS ]] && exit
    exec ./start.command
}

while getopts ":ahm:n:r:" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    a)
        allowAllTypes="yes"
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
        printf "==> Ignoring invalid option: -%s\n\n" "$OPTARG" >&2
        ;;
    :)
        printf "==> Option -%s requires an argument.\n\n" "$OPTARG" >&2
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
TCONST_PATTERNS=$(mktemp)
SHOWS_TERMS=$(mktemp)
SHOWS_PATTERNS=$(mktemp)
SHOWS_RAW=$(mktemp)
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
if [[ $# -eq 0 ]]; then
    read -r -p "Enter a show name or tconst ID: " searchTerm </dev/tty
    tr -ds '"' '[:space:]' <<<"$searchTerm" >"$ALL_TERMS"
    if [[ ! -s $ALL_TERMS ]]; then
        loopOrExitP
    fi
    printf "\n"
else
    printf "$1" >"$ALL_TERMS"
fi

# Get title.basics.tsv.gz file size - should already exist but make sure...
num_TB="$(rg -N title.basics.tsv.gz "$numRecordsFile" 2>/dev/null | cut -f 2)"
[[ -z $num_TB ]] && num_TB="$(rg -cz "^t" title.basics.tsv.gz)"

# Split into two groups so we can process them differently
rg -wN "^tt[0-9]{7,8}" "$ALL_TERMS" | sort -fu >"$TCONST_TERMS"
rg -wNv "^tt[0-9]{7,8}" "$ALL_TERMS" | sort -fu >"$SHOWS_TERMS"
printf "==> Searching $num_TB records for:\n"
cat "$TCONST_TERMS" "$SHOWS_TERMS"

# Reconstitute the search patterns with column guards, but keep the two kinds
# in separate files -- they are filtered differently below.
perl -p -e 's/^/^/; s/$/\\t/;' "$TCONST_TERMS" >"$TCONST_PATTERNS"
perl -p -e 's/^/\\t/; s/$/\\t/;' "$SHOWS_TERMS" | sed 's+[()?]+\\&+g' >"$SHOWS_PATTERNS"
cat "$TCONST_PATTERNS" "$SHOWS_PATTERNS" >"$ALL_TERMS"
numTerms="$(sed -n '$=' "$ALL_TERMS")"

# Get all possible matches.
#
# A tconst names one exact title, so it bypasses rg_types.rgx entirely. That is
# the only way to ask for a tvEpisode, short, or anything else the type list
# leaves out: ./findOtherShows.sh tt8517292 used to report "I didn't find any
# matching shows" purely because tt8517292 is a tvEpisode. A show title is a
# guess that can match thousands of episode rows, so it keeps the filter.
#
# The filter tests field 2 rather than the whole line, so a title such as
# "Home Video" can't pass itself off as a type.
true >"$TMPFILE"
if [[ -s $TCONST_PATTERNS ]]; then
    rg -NzSI -f "$TCONST_PATTERNS" title.basics.tsv.gz >>"$TMPFILE"
fi
if [[ -s $SHOWS_PATTERNS ]]; then
    rg -NzSI -f "$SHOWS_PATTERNS" title.basics.tsv.gz >"$SHOWS_RAW"
    if [[ -n $allowAllTypes ]]; then
        cat "$SHOWS_RAW" >>"$TMPFILE"
    else
        awk -F"\t" 'NR==FNR {types[$0]; next} $2 in types' \
            rg_types.rgx "$SHOWS_RAW" >>"$TMPFILE"
        # Say what the filter removed. "I didn't find any matching shows" reads
        # the same whether the title isn't on IMDb or a short was filtered out,
        # and -a is no help to someone who can't tell those apart. Reported
        # whenever anything was dropped, not only on a total miss: 5 matches
        # out of 53 is also worth knowing about. Types are listed in the order
        # they first appear, since awk's for-in order is unspecified.
        awk -F"\t" 'NR==FNR {types[$0]; next}
            !($2 in types) {if (!($2 in n)) order[++k] = $2; n[$2]++}
            END {
                if (k == 0) exit
                for (i = 1; i <= k; i++)
                    out = out (i > 1 ? ", " : "") n[order[i]] " " order[i]
                printf("\n==> Filtered out %s. Use -a to include all types.\n", out)
            }' rg_types.rgx "$SHOWS_RAW"
    fi
fi
cut -f 1-4,6 "$TMPFILE" | perl -p -e 's+\\N++g;' |
    sort -f -t$'\t' --key=3 >"$POSSIBLE_MATCHES"

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

# Remember how many matches there were
numMatches=$(sed -n '$=' "$ALL_MATCHES")

# Get rid of the URL we added
cp "$ALL_MATCHES" "$TMPFILE"
sed 's+imdb.com/title/++' "$TMPFILE" >"$ALL_MATCHES"
# Build the lists we need, sort alphabetically
cut -f 1,3 "$ALL_MATCHES" | sort -f -t$'\t' --key=2 >"$SHOW_NAMES"
cut -f 1 "$SHOW_NAMES" | sort >"$TCONST_LIST"

# Build each show's cast cache from the local .gz datasets. The join lives in
# functions/buildShowCache.function, shared with findCastOf.sh so both writers
# produce the identical 8-column format generateXrefData.sh writes: Person, Show
# Title, Episode Title, Rank, Job, Character Name, nconst ID, tconst ID.
#
# An existing cache file is reused, and its Show Title kept. generateXrefData.sh
# writes the cache for every show in a .tconst under its translated name (Spring
# Tide, Arne Dahl (2011)); rebuilding it here under the title.basics name
# (Springfloden, Arne Dahl: Misterioso) showed the searched show under the wrong
# name, and every later search listed it that way too. A file is rebuilt only
# when title.principals.tsv.gz is newer, so a show outside the .tconst files
# still picks up new credits -- and keeps the name it already had.
while IFS='' read -r line; do
    cacheFile="$cacheDirectory/$line"
    if [[ ! -s $cacheFile ]] || [[ title.principals.tsv.gz -nt $cacheFile ]]; then
        showTitle="$(rg -N "^$line\t" "$SHOW_NAMES" | cut -f 2)"
        [[ -s $cacheFile ]] && showTitle="$(head -1 "$cacheFile" | cut -f 2)"
        buildShowCache "$line" "$showTitle" || continue
    fi
    if [[ $maxCast -gt 0 ]]; then
        cut -f 7 "$cacheFile" | rg "^nm" | head -"$maxCast" \
            >>"$NCONST_LIST"
    else
        # Save the nconst IDs
        cut -f 7 "$cacheFile" | rg "^nm" >>"$NCONST_LIST"
    fi
done <"$TCONST_LIST"
printf "\n"

cp "$NCONST_LIST" "$TMPFILE"
sort -fu "$TMPFILE" >"$NCONST_LIST"

# Every actor credit for the searched cast, kept only for people credited in at
# least two different tconsts. This used to sort the rows and print a pair only
# when a person's Show Title differed from the row above, so a run of rows under
# one name -- the films .xlate collapses onto "Arne Dahl (2012)", same-year
# dated duplicates -- kept only its first and last rows, and which ones survived
# depended on where the searched show's name happened to sort. Counting tconsts
# per nconst keeps them all.
#
# rg -w is only a fast pre-filter: without -w, nm0075003 also matched inside an
# 8-digit nconst. The awk then requires the nconst field itself, and tests the
# Job field for actor -- `rg 'actor'` over the line also matched a character or
# show title containing "actor".
PTAB='%s\t%s\t%s\t%s\t%s\t%s\t%s\n'
rg -wNI -f "$NCONST_LIST" "$cacheDirectory"/tt* |
    awk -F "\t" -v PF="$PTAB" -v nconsts="$NCONST_LIST" '
        FILENAME == nconsts { want[$1]; next }
        $7 in want && $5 == "actor" {
            row[++n] = sprintf(PF,$1,$5,$2,$4,$6,$7,$8)
            who[n] = $7
            if (!(($7, $8) in seen)) { seen[$7, $8]; shows[$7]++ }
        }
        END { for (i = 1; i <= n; i++) if (shows[who[i]] > 1) printf "%s", row[i] }
    ' "$NCONST_LIST" - | sort -fu |
    sort -f -t$'\t' --key=4,4n >"$CAST_CSV"

# Split the searched shows' own credits from everyone's other shows by tconst
# (field 7). This used `rg "$showName"` over the whole line, which broke once
# names come from the cache: the parentheses in "Arne Dahl (2011)" are regex
# grouping and never match, and a short name like "Crime" also matched "Irvine
# Welsh's Crime" and character names. It also overwrote both files per show, so
# only the last of several searched shows counted.
PTAB='%s\t%s\t%s\t%s\t%s\timdb.com/name/%s\n'
awk -F "\t" -v PF="$PTAB" 'NR == FNR { own[$1]; next }
    $7 in own {printf(PF,$1,$2,$3,$4,$5,$6)}' "$TCONST_LIST" "$CAST_CSV" \
    >"$CREDITS_CSV"

# One line per person per searched show. Someone credited more than once --
# two characters (Samuel Labarthe: Swan Laurence, Herbert Michel), or one
# character IMDb lists under two names (Abbas, Abbas El Fassi) -- got a block
# per credit, each repeating their whole list of other shows. Keep the best
# rank and join the distinct character names. CAST_CSV is sorted by rank, so
# the order of first appearance is rank order and names join best-ranked first.
awk -F "\t" -v OFS="\t" '
    {
        key = $6 SUBSEP $3
        if (!(key in at)) {
            at[key] = ++n
            line[n] = $0
            rank[n] = $4
            roles[n] = $5
            next
        }
        i = at[key]
        if ($4 + 0 < rank[i] + 0) rank[i] = $4
        if ($5 != "" && index("; " roles[i] "; ", "; " $5 "; ") == 0)
            roles[i] = roles[i] (roles[i] == "" ? "" : "; ") $5
    }
    END {
        for (i = 1; i <= n; i++) {
            $0 = line[i]
            $4 = rank[i]
            $5 = roles[i]
            print
        }
    }' "$CREDITS_CSV" >"$TMPFILE"
cp "$TMPFILE" "$CREDITS_CSV"
PTAB='%s\t%s\t%s\t%s\t%s\timdb.com/title/%s\n'
awk -F "\t" -v PF="$PTAB" 'NR == FNR { own[$1]; next }
    !($7 in own) {printf(PF,$1,$2,$3,$4,$5,$7)}' "$TCONST_LIST" "$CAST_CSV" \
    >"$OTHERS_CSV"

# Each person's other shows, matched on the exact Name field. `rg "$actor"` was
# a regex over the whole line, so "Ann" also matched "Anna" and character
# names, and a name with regex characters could match nothing at all.
true >"$CAST_CSV"
while IFS='' read -r line; do
    printf "$line\n" >"$TMPFILE"
    actor=$(cut -f 1 <<<"$line")
    actor="$actor" awk -F "\t" -v rmax="$maxRank" \
        '$1 == ENVIRON["actor"] && (rmax <= 0 || $4 <= rmax)' "$OTHERS_CSV" |
        sort -f -t$'\t' --key=4,4n --key=3,3 >>"$TMPFILE"
    numLines="$(sed -n '$=' "$TMPFILE")"
    if [[ $numLines -gt 1 ]]; then
        cat "$TMPFILE" >>"$CAST_CSV"
        printf " ---\t\t\t\t\t\n" >>"$CAST_CSV"
    fi
done <"$CREDITS_CSV"

printf "Person\tJob\tShow Title\tRank\tCharacter Name\tLink\n" >"$TMPFILE"
cat "$CAST_CSV" >>"$TMPFILE"

numLines="$(sed -n '$=' "$TMPFILE")"
if [[ $numLines -eq 1 ]]; then
    if [[ $maxCast -gt 0 ]]; then
        printf "==> None of the top $maxCast cast members appear in other cached shows.\n"
    else
        printf "==> None of the top cast members appear in other cached shows.\n"
    fi
    loopOrExitP
fi

# Create a copy to use in spreadsheets
showName="$(head -2 "$TMPFILE" | tail -1 | cut -f 3)"
CAST_SPREADSHEET="ShowsWithActorsFrom-$(safeFilename "$showName").csv"
printf "==> The shared cast list will be saved in ${BLUE}$CAST_SPREADSHEET${NO_COLOR}\n"
rg -v ' ---' "$TMPFILE" >"$CAST_SPREADSHEET"

if [[ $maxCast -gt 0 ]]; then
    printf "==> Top $maxCast cast members that appear in other cached shows (Name|Job|Show|Rank|Role|Link):\n"
else
    printf "==> Top cast members that appear in other cached shows (Name|Job|Show|Rank|Role|Link):\n"
fi

tsvPrint -c 1 "$CAST_CSV"

loopOrExitP
