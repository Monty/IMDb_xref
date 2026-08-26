#!/usr/bin/env bash
#
# Find common cast & crew members between multiple shows
#
# NOTES:
#   Requires cast member files produced by generateXrefData.sh
#   Note: Cast & crew member data from IMDb sometimes has errors or omissions
#
#   To help refine searches, the output is rather wordy (unless -d is used).
#   The final section (Names that occur more than once) is of highest interest.
#
#   It may help to start with an actor or character, e.g.
#       ./xrefCast.sh 'Olivia Colman'
#       ./xrefCast.sh 'Queen Elizabeth II' 'Princess Diana'
#
#   Then move to more complex queries that expose other common cast & crew members
#       ./xrefCast.sh 'The Crown'
#       ./xrefCast.sh -d 'The Night Manager' 'The Crown' 'The Durrells'
#
#   Experiment to find the most useful results.

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
xrefCast.sh -- Cross-reference shows, actors, and the characters they portray using IMDB data.

If you don't enter a search term on the command line, you'll be prompted for one.

USAGE:
    ./xrefCast.sh [OPTIONS] [-f SEARCH_FILE] [SEARCH_TERM ...]

OPTIONS:
    -h      Print this message.
    -u      Union -- Also search shows that are in the cross-reference cache but
            in none of your .tconst lists.
    -p      Principal -- Only print 'Principal cast & crew members' section.
    -d      Duplicates -- Only list cast & crew who are found in more than one show
    -f      File -- Query a specific file rather than "Credits-Person*csv".
    -i      Print info about any files that are searched.

"Credits-Person*csv" is built from your .tconst lists and carries episode-level
credits, so guest and supporting players are in it. The cross-reference cache
also holds every show ever added by findCastOf.sh or findOtherShows.sh --
including shows you looked up once and never curated -- but only each show's ~10
series principals, with no episode credits.

-u searches both: your curated shows at full depth, plus the uncurated ones at
principals-only depth. Results say which shows came from the cache, because a
miss on one of those is inconclusive rather than a definite absence.

EXAMPLES:
    ./xrefCast.sh "Olivia Colman"
    ./xrefCast.sh "Queen Elizabeth II" "Princess Diana"
    ./xrefCast.sh "The Crown"
    ./xrefCast.sh -d "The Night Manager" "The Crown" "The Durrells"
    ./xrefCast.sh -d "Elizabeth Debicki"
    ./xrefCast.sh -u "The Crown"
    ./xrefCast.sh -pf Clooney.csv "Brad Pitt"
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
TMPFILE $TMPFILE
CACHEFILE $CACHEFILE
FRINGEFILE $FRINGEFILE
UNIONFILE $UNIONFILE
SEARCH_TERMS $SEARCH_TERMS
ALL_NAMES $ALL_NAMES
MULTIPLE_NAMES $MULTIPLE_NAMES
EOT
    else
        rm -rf "$TMPFILE" "$CACHEFILE" "$FRINGEFILE" "$UNIONFILE" "$SEARCH_TERMS" \
            "$ALL_NAMES" "$MULTIPLE_NAMES"
    fi
}

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

# Should we loop or not? Loop unless NO_MENUS is set.
function loopOrExitP() {
    printf "\n"
    terminate
    [[ -n $NO_MENUS ]] && exit
    exec ./start.command
}

# Build "Credits-Person.csv" plus the cache rows for shows it doesn't contain.
# Non-zero if the cache holds no shows.
#
# Show-level, not row-level, which is what dissolves the dedup problem: for a
# show present in both stores the cache adds nothing, since both derive their
# series-level rows from title.principals for the same tconst and the CSV also
# carries that show's episode rows. Filtering the cache down to tconsts the CSV
# lacks therefore leaves nothing to deduplicate -- no rank or character-format
# matching needed. Verified on Money Heist (tt6468322): 12 cache rows vs 12 CSV
# series-level rows, identical but for actor/actress, which the perl below
# reconciles anyway.
function buildUnionFile() {
    buildCacheFile || return 1
    awk -F "\t" 'NR==FNR {curated[$8]=1; next} !($8 in curated)' \
        "$1" "$CACHEFILE" >"$FRINGEFILE"
    cat "$1" "$FRINGEFILE" >"$UNIONFILE"
}

# Name the shows in a result that came from the cache rather than from the
# .tconst corpus. The two contribute at different depths -- a curated show
# carries episode-level credits, a fringe show only its ~10 series principals --
# and nothing in a four-column row shows which is which. So a character search
# that misses on a fringe show is inconclusive rather than negative: Elizabeth
# Debicki's Princess Diana is credited on The Crown's episodes, and if The Crown
# is a fringe show here those rows don't exist to be found. Named after the
# results, where the ambiguity is, rather than marked per row -- that would touch
# the projection, the column widths, and tsvPrint.
function printFringeFooter() {
    local matched
    [[ -s $FRINGEFILE ]] || return
    matched=$(awk -F "\t" 'NR==FNR {fringe[$2]=1; next} ($3 in fringe) {print $3}' \
        "$FRINGEFILE" "$1" | sort -fu)
    [[ -z $matched ]] && return
    printf "\n    From the cross-reference cache, which has no episode credits --\n"
    printf "    a missing character or guest actor is inconclusive, not an absence:\n"
    printf "%s\n" "$matched" | awk '{print "      " $0}'
}

# Concatenate the per-show cache into one searchable file. Non-zero if the
# cache holds no shows, in which case CACHEFILE is left untouched.
function buildCacheFile() {
    [[ -n "$(ls -1 "$cacheDirectory" 2>/dev/null | rg "^tt")" ]] || return 1
    cat "$cacheDirectory"/tt* | rg -v '^Person\tShow Title\t' | rg -v '^$' |
        sort -fu >"$CACHEFILE"
}

# How many records would $1 return for these search terms? Deliberately uses the
# same projection as the real search further down: the searcher only ever sees
# Name|Job|Show|Role, not the nconst and tconst columns, so counting raw rows
# here would promise hits that switching corpora can't actually produce.
function countMatches() {
    [[ -s $1 ]] || return
    awk -F "\t" -v PF="$PTAB" '{printf(PF, $1,$5,$2,$6)}' "$1" |
        rg -wNzSIF -c -f "$SEARCH_TERMS"
}

# On an empty result, say whether the uncurated shows would have answered.
# The corpora are not coverage levels of one store, they answer different
# questions: "Credits-Person.csv" is built from the .tconst lists, so it means
# "shows I've committed to", while the cache accumulates everything ever looked
# up -- including shows deliberately never added. An empty result is therefore
# often the correct answer rather than a misspelling, but the message above
# suggests a typo either way, which is the only thing wrong with it.
function suggestOtherCorpus() {
    local count
    local record="records are"
    # An explicit -f means the caller chose the corpus; don't second-guess it.
    [[ -n $EXPLICIT_SEARCH_FILE ]] && return
    # Already searched everything there is.
    [[ -n $USE_UNION ]] && return
    buildUnionFile "Credits-Person.csv" || return
    count="$(countMatches "$FRINGEFILE")"
    [[ -z $count ]] && return
    [[ $count -eq 1 ]] && record="record is"
    printf "    However, %s matching %s in shows that are cached but in none of\n" \
        "$count" "$record"
    printf "    your .tconst lists. Retry with -u.\n"
}

while getopts ":f:hupdi" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    u)
        USE_UNION="yes"
        ;;
    p)
        PRINCIPAL_CAST_ONLY="yes"
        ;;
    d)
        MULTIPLE_NAMES_ONLY="yes"
        ;;
    f)
        SEARCH_FILE="$OPTARG"
        ;;
    i)
        INFO="yes"
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
TMPFILE=$(mktemp)
SEARCH_TERMS=$(mktemp)
FRINGEFILE=$(mktemp)
UNIONFILE=$(mktemp)
ALL_NAMES=$(mktemp)
MULTIPLE_NAMES=$(mktemp)
CACHEFILE="Credits-cache.csv"

# If a SEARCH_FILE was specified...
if [[ -n $SEARCH_FILE ]]; then
    # Make sure it exists, no way to recover
    if [[ ! -e $SEARCH_FILE ]]; then
        printf "==> [${RED}Error${NO_COLOR}] Missing search file: $SEARCH_FILE\n\n" >&2
        loopOrExitP
    fi
    # An explicit -f wins over -u. Without this the union block below
    # silently replaced the file the caller asked for -- including
    # findCastOf.sh's internal "xrefCast.sh -f" call, which would then
    # cross-reference every cached show instead of just the ones searched for.
    # (Was FULLCAST, then -c, before -u replaced them.)
    EXPLICIT_SEARCH_FILE="yes"
else
    SEARCH_FILE="Credits-Person.csv"
    # If it doesn't exist, generate it
    [[ ! -e $SEARCH_FILE ]] && ensureDataFiles
fi

# -u widens the search to shows that are cached but in none of the .tconst
# lists. It is a union, not a corpus swap: the curated shows keep their
# episode-level depth and the uncurated ones are added at principals-only depth.
#
# Deliberately not the default. The CSV means "shows I've committed to"; the
# cache means "everything I've ever looked at", which on a personal corpus
# includes shows considered and rejected. Folding those into "my shows" would
# break the question this tool exists to answer.
#
# The predecessor -c swapped corpora instead, trading away episode depth on
# every curated show to reach the fringe -- and before that, the FULLCAST
# environment variable did the same thing under a name that promised the
# opposite. Both are gone.
if [[ -n $USE_UNION ]] && [[ -n $EXPLICIT_SEARCH_FILE ]]; then
    printf "==> [${YELLOW}Warning${NO_COLOR}] Ignoring -u because -f was supplied.\n\n" >&2
fi
if [[ -n $USE_UNION ]] && [[ -z $EXPLICIT_SEARCH_FILE ]]; then
    if buildUnionFile "$SEARCH_FILE"; then
        SEARCH_FILE="$UNIONFILE"
    else
        printf "==> [${YELLOW}Warning${NO_COLOR}] The cross-reference cache is empty. " >&2
        printf "Searching $SEARCH_FILE alone.\n\n" >&2
    fi
fi

# Make sure a search term is supplied
if [[ $# -eq 0 ]]; then
    # No search terms on command line, read them from user into TMPFILE
    cat <<EOF
==> I can cross-reference shows, actors, and the characters they portray,
    such as The Crown, Olivia Colman, and Queen Elizabeth -- as long as
    the search terms exist in $SEARCH_FILE

Only one search term per line. Enter a blank line to finish.
EOF
    while read -r -p "Enter a show, actor, or character: " searchTerm; do
        [[ -z $searchTerm ]] && break
        tr -ds '"' '[:space:]' <<<"$searchTerm" >>"$TMPFILE"
    done </dev/tty
    if [[ ! -s $TMPFILE ]]; then
        if waitUntil "$YN_PREF" -N \
            "Would you like to see who played Queen Elizabeth II as an example?"; then
            printf "Queen Elizabeth II\n" >>"$TMPFILE"
            printf "\n"
        else
            loopOrExitP
        fi
    fi
else
    # Put any search terms from the command line into TMPFILE
    for a in "$@"; do
        printf "$a\n" >>"$TMPFILE"
    done
fi
# Ensure SEARCH_TERMS has one unique search term per line
sort -fu "$TMPFILE" >"$SEARCH_TERMS"

# Let us know how many records we're searching
numRecords=$(sed -n '$=' "$SEARCH_FILE")
[[ $INFO == "yes" ]] &&
    printf "==> Searching $numRecords records in $SEARCH_FILE for cast & crew data.\n\n"

# Let us know what we're searching for
printf "==> Searching for:\n"
cat "$SEARCH_TERMS"

# Set up awk printf formats with tabs
# Name|Job|Show|Role
PTAB='%s\t%s\t%s\t%s\n'

# Make sure TMPFILE is empty in case we don't find anything
true >"$TMPFILE"

# Rearrange any matches and put them in TMPFILE
# Sort by Job (2), Person (1), Show Title (3)
#
# The search runs on the projection, not on the source rows, so what is
# searchable is exactly what is displayed: Name, Job, Show, Character. The
# nconst, tconst, Episode Title, and Rank columns are dropped before matching
# and are therefore not searchable -- deliberately. Highlighting happens at
# display time via tsvPrint -p, so a row matched on a dropped column could not
# be marked: it would come back with nothing highlighted and no visible reason
# for being in the results. This used to be gated by a second rg over the full
# 8-column rows, which meant a tconst entered the block and then matched
# nothing, reporting "I didn't find any" about data that was present.
#
# No --color here: escapes in the data would land in the sort keys (ESC sorts
# before letters, so name-matched people jumped to the front of their job
# group) and in tsvPrint's column-width arithmetic, which counted them as
# visible characters and misaligned every highlighted row.
#
# -F matches the terms literally. They are show titles, person names, and
# character names -- never regex. The previous sed escaped only ( ) and ?, so
# every other metacharacter stayed live and produced real false positives:
# "D.S." returned "Bertrand (DGSE)" and "DCSU Russell Cornish", the dots
# matching DGSE and DCSU. That sed was a hand-rolled partial -F; -F does
# completely what it did partially, and it makes search and highlight agree,
# since tsvPrint -p has always matched literally.
awk -F "\t" -v PF="$PTAB" '{printf(PF, $1,$5,$2,$6)}' "$SEARCH_FILE" |
    rg -wNzSIF -f "$SEARCH_TERMS" |
    perl -p -e 's+\tactress\t+\tactor\t+;' |
    sort -f -t$'\t' --key=2,2 --key=1,1 --key=3,3 -fu >"$TMPFILE"

# Any results? If not, don't continue.
if [[ ! -s $TMPFILE ]]; then
    printf "==> I didn't find ${RED}any${NO_COLOR} matching records.\n"
    printf "    Check the \"Searching for:\" section above.\n"
    suggestOtherCorpus
    loopOrExitP
else
    numAll=$(cut -f 1 "$TMPFILE" | sort -fu | sed -n '$=')
    [[ $numAll -eq 1 ]] && [[ -z $MULTIPLE_NAMES_ONLY ]] &&
        PRINCIPAL_CAST_ONLY="yes"
fi

# Get rid of initial single quote used to force show/episode names in spreadsheet to be strings.
perl -pi -e "s+\t'+\t+g;" "$TMPFILE"

# Save ALL_NAMES
cp "$TMPFILE" "$ALL_NAMES"

# Save MULTIPLE_NAMES
# Print names that occur more than once, i.e. where field 1 is repeated in
# successive lines, but field 3 is different
awk -F "\t" -v PF="$PTAB" '{if($1==f[1]&&$3!=f[3]) {printf(PF,f[1],f[2],f[3],f[4]);
    printf(PF,$1,$2,$3,$4)} split($0,f)}' "$TMPFILE" | sort -fu |
    sort -f -t$'\t' -k 2,2 -k 1,1 -k 3,3 >"$MULTIPLE_NAMES"

# Multiple results?
if [[ ! -s $MULTIPLE_NAMES ]]; then
    numMultiple="0"
else
    _vb="is"
    _pron="that"
    numMultiple=$(cut -f 1 "$TMPFILE" | sort -f | uniq -d | sed -n '$=')
    [[ $numMultiple -gt 1 ]] && _vb="are" && _pron="those"
fi

# If in interactive mode, give user a choice of all or duplicates only
if [[ -z $NO_MENUS ]] && [[ -z $MULTIPLE_NAMES_ONLY ]] &&
    [[ -z $PRINCIPAL_CAST_ONLY ]] && [[ $numMultiple -ne 0 ]]; then
    printf "\n==> I found $numAll principal cast & crew members. "
    printf "$numMultiple $_vb listed in more than one show.\n"
    waitUntil "$YN_PREF" -N "Should I only print $_pron $numMultiple?" &&
        MULTIPLE_NAMES_ONLY="yes"
fi

# Unless MULTIPLE_NAMES_ONLY, print all search results
if [[ -z $MULTIPLE_NAMES_ONLY ]]; then
    printf "\n==> Principal cast & crew members in alphabetical order (Name|Job|Show|Role):\n"
    tsvPrint -p "$SEARCH_TERMS" "$ALL_NAMES"
    printFringeFooter "$ALL_NAMES"
fi

# If PRINCIPAL_CAST_ONLY, exit here
[[ -n $PRINCIPAL_CAST_ONLY ]] && loopOrExitP

# Print multiple search results
if [[ $numMultiple -eq 0 ]]; then
    [[ -n $MULTIPLE_NAMES_ONLY ]] &&
        printf "\n==> I didn't find any cast or crew members who are listed in more than one show.\n"
else
    printf "\n==> Principal cast & crew members listed in more than one show (Name|Job|Show|Role):\n"
    tsvPrint -p "$SEARCH_TERMS" "$MULTIPLE_NAMES"
    printFringeFooter "$MULTIPLE_NAMES"
fi

# Do we really want to quit?
loopOrExitP
