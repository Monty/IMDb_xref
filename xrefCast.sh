#!/usr/bin/env bash
#
# Find common cast members between multiple shows
#
# NOTES:
#   Requires cast member files produced by generateXrefData.sh
#   Note: Cast member data from IMDb sometimes has errors or omissions
#
#   To help refine searches, the output is rather wordy (unless -d is used).
#   The final section (Names that occur more than once) is of highest interest.
#
#   It may help to start with an actor or character, e.g.
#       ./xrefCast.sh 'Olivia Colman'
#       ./xrefCast.sh 'Queen Elizabeth II' 'Princess Diana'
#
#   Then move to more complex queries that expose other common cast members
#       ./xrefCast.sh 'The Crown'
#       ./xrefCast.sh -d 'The Night Manager' 'The Crown' 'The Durrells in Corfu'
#
#   Experiment to find the most useful results.

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

export LC_COLLATE="C"
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
    -p      Principal -- Only print 'Principal cast members' section.
    -d      Duplicates -- Only print cast members that are in more than one show
    -f      File -- Query a specific file rather than "Credits-Person*csv".
    -i      Print info about any files that are searched.
    -n      No loop - don't offer to do another search upon exit

EXAMPLES:
    ./xrefCast.sh "Olivia Colman"
    ./xrefCast.sh "Queen Elizabeth II" "Princess Diana"
    ./xrefCast.sh "The Crown"
    ./xrefCast.sh -d "The Night Manager" "The Crown" "The Durrells in Corfu"
    ./xrefCast.sh -dn "Elizabeth Debicki"
    ./xrefCast.sh -pf Clooney.csv "Brad Pitt"
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
TMPFILE $TMPFILE
SEARCH_TERMS $SEARCH_TERMS
ALL_NAMES $ALL_NAMES
MULTIPLE_NAMES $MULTIPLE_NAMES
EOT
    else
        rm -rf "$TMPFILE" "$SEARCH_TERMS" "$ALL_NAMES" "$MULTIPLE_NAMES"
    fi
}

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

# Should we loop or not? Loop unless we were called with -n
function loopOrExitP() {
    printf "\n"
    terminate
    [ -n "$noLoop" ] || [ -n "$TESTING" ] && exit
    exec ./startUp.sh
}

while getopts ":f:hpdin" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    p)
        PRINCIPAL_CAST_ONLY="yes"
        ;;
    d)
        MULTIPLE_NAMES_ONLY="yes"
        ;;
    i)
        INFO="yes"
        ;;
    n)
        noLoop="yes"
        ;;
    f)
        SEARCH_FILE="$OPTARG"
        ;;
    \?)
        printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2
        ;;
    :)
        printf "==> Option -$OPTARG requires a 'search file' argument'.\n\n" >&2
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
ALL_NAMES=$(mktemp)
MULTIPLE_NAMES=$(mktemp)

# If a SEARCH_FILE was specified...
if [ -n "$SEARCH_FILE" ]; then
    # Make sure it exists, no way to recover
    if [ ! -e "$SEARCH_FILE" ]; then
        printf "==> [${RED}Error${NO_COLOR}] Missing search file: $SEARCH_FILE\n\n" >&2
        loopOrExitP
    fi
else
    SEARCH_FILE="Credits-Person.csv"
    # If it doesn't exist, generate it
    [ ! -e "$SEARCH_FILE" ] && ensureDataFiles
fi

# Make sure a search term is supplied
if [ $# -eq 0 ]; then
    cat <<EOF
==> I can cross-reference shows, actors, and the characters they portray,
    such as The Crown, Olivia Colman, and Queen Elizabeth -- as long as
    the search terms exist in $SEARCH_FILE

Only one search term per line. Enter a blank line to finish.
EOF
    while read -r -p "Enter a show, actor, or character: " searchTerm; do
        [ -z "$searchTerm" ] && break
        tr -ds '"' '[:space:]' <<<"$searchTerm" >>"$TMPFILE"
    done </dev/tty
    if [ ! -s "$TMPFILE" ]; then
        if waitUntil "$YN_PREF" -N \
            "Would you like to see who played Queen Elizabeth II?"; then
            printf "Queen Elizabeth II\n" >>"$TMPFILE"
            printf "\n"
        else
            loopOrExitP
        fi
    fi
fi

# Let us know how many records we're searching
numRecords=$(sed -n '$=' "$SEARCH_FILE")
[ "$INFO" == "yes" ] &&
    printf "==> Searching $numRecords records in $SEARCH_FILE for cast data.\n\n"

# Setup TMPFILE with one search term per line, let us know what's in it.
printf "==> Searching for:\n"
for a in "$@"; do
    printf "$a\n" >>"$TMPFILE"
done
sort -fu "$TMPFILE" >"$SEARCH_TERMS"
cat "$SEARCH_TERMS"

# Make sure TMPFILE is empty
true >"$TMPFILE"

# Escape metacharacters known to appear in titles, persons, characters
sed -i '' 's+[()?]+\\&+g' "$SEARCH_TERMS"

# Setup awk printf formats with spaces or tabs
# Name|Job|Show|Role
PSPACE='%-20s  %-10s  %-40s  %s\n'
PTAB='%s\t%s\t%s\t%s\n'

# If we find anything, rearrange it and put it in TMPFILE
# Sort by Job (2), Person (1), Show Title (3)
if [ -n "$(rg -wNzSI -c -f "$SEARCH_TERMS" "$SEARCH_FILE")" ]; then
    rg -wNzSI --color always -f "$SEARCH_TERMS" "$SEARCH_FILE" |
        awk -F "\t" -v PF="$PTAB" '{printf(PF, $1,$5,$2,$6)}' |
        sort -f -t$'\t' --key=2,2 --key=1,1 --key=3,3 -fu >"$TMPFILE"
fi

# Any results? If not, don't continue.
if [ ! -s "$TMPFILE" ]; then
    printf "==> I didn't find ${RED}any${NO_COLOR} matching records.\n"
    printf "    Check the \"Searching for:\" section above.\n"
    loopOrExitP
else
    numAll=$(cut -f 1 "$TMPFILE" | sort -fu | sed -n '$=')
    [ "$numAll" -eq 1 ] && [ -z "$MULTIPLE_NAMES_ONLY" ] &&
        PRINCIPAL_CAST_ONLY="yes"
fi

# Get rid of initial single quote used to force show/episode names in spreadsheet to be strings.
perl -pi -e "s+\t'+\t+g;" "$TMPFILE"

# Save ALL_NAMES
printf "\n==> Principal cast members (Name|Job|Show|Role):\n" >"$ALL_NAMES"
# Can't use tsvPrint because we want better alignment than bare tabs
if checkForExecutable -q xsv; then
    xsv table -d "\t" "$TMPFILE" >>"$ALL_NAMES"
else
    awk -F "\t" -v PF="$PSPACE" '{printf(PF,$1,$2,$3,$4)}' "$TMPFILE" >>"$ALL_NAMES"
fi

# Save MULTIPLE_NAMES
# Print names that occur more than once, i.e. where field 1 is repeated in
# successive lines, but field 3 is different
if checkForExecutable -q xsv; then
    awk -F "\t" -v PF="$PTAB" '{if($1==f[1]&&$3!=f[3]) {printf(PF,f[1],f[2],f[3],f[4]);
    printf(PF,$1,$2,$3,$4)} split($0,f)}' "$TMPFILE" | sort -fu |
        sort -f -t$'\t' -k 2,2 -k 1,1 -k 3,3 |
        xsv table -d "\t" >>"$MULTIPLE_NAMES"
else
    awk -F "\t" -v PF="$PSPACE" '{if($1==f[1]&&$3!=f[3]) {printf(PF,f[1],f[2],f[3],f[4]);
    printf(PF,$1,$2,$3,$4)} split($0,f)}' "$TMPFILE" | sort -fu |
        sort -f -t$'\t' -k 2,2 -k 1,1 -k 3,3 >>"$MULTIPLE_NAMES"
fi

# Multiple results?
if [ ! -s "$MULTIPLE_NAMES" ]; then
    numMultiple="0"
else
    _vb="appears"
    _pron="that"
    numMultiple=$(cut -f 1 "$TMPFILE" | sort -f | uniq -d | sed -n '$=')
    [ "$numMultiple" -gt 1 ] && _vb="appear" && _pron="those"
fi

# If we're in interactive mode, give user a choice of all or duplicates only
if [ -z "$noLoop" ] && [ -z "$MULTIPLE_NAMES_ONLY" ] &&
    [ -z "$PRINCIPAL_CAST_ONLY" ] && [ "$numMultiple" -ne 0 ]; then
    printf "\n==> I found $numAll cast members. $numMultiple $_vb in more than one show.\n"
    waitUntil "$YN_PREF" -N "Should I only print $_pron $numMultiple?" &&
        MULTIPLE_NAMES_ONLY="yes"
fi

# Unless MULTIPLE_NAMES_ONLY, print all search results
[ -z "$MULTIPLE_NAMES_ONLY" ] && cat "$ALL_NAMES"

# If PRINCIPAL_CAST_ONLY, exit here
[ -n "$PRINCIPAL_CAST_ONLY" ] && loopOrExitP

# Print multiple search results
if [ "$numMultiple" -eq 0 ]; then
    [ -n "$MULTIPLE_NAMES_ONLY" ] &&
        printf "\n==> I didn't find ${RED}any${NO_COLOR} cast members who appear in more than one show.\n"
else
    printf "\n==> Cast members who appear in more than one show (Name|Job|Show|Role):\n"
    cat "$MULTIPLE_NAMES"
fi

# Do we really want to quit?
loopOrExitP
