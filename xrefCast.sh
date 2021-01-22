#!/usr/bin/env bash
#
# Find common cast members between multiple shows
#
# NOTES:
#   Requires cast member files produced by generateXrefData.sh
#   Note: Cast member data from IMDb sometimes has errors or omissions
#
#   To help refine searches, the output is rather wordy (unless the -s option is used).
#   The final section (Duplicated names) is the section of highest interest.
#
#   It may help to start with an actor or character, e.g.
#       ./xrefCast.sh 'Olivia Colman'
#       ./xrefCast.sh 'Queen Elizabeth II' 'Princess Diana'
#
#   Then move to more complex queries that expose other common cast members
#       ./xrefCast.sh 'The Crown'
#       ./xrefCast.sh -s 'The Night Manager' 'The Crown' 'The Durrells in Corfu'
#
#   Experiment to find the most useful results.

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME"
source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
xrefCast.sh -- Cross-reference shows, actors, and the characters they portray using IMDB data.

If you don't enter a search term on the command line, you'll be prompted for input.

USAGE:
    ./xrefCast.sh [OPTIONS] [-f SEARCH_FILE] [SEARCH_TERM ...]

OPTIONS:
    -h      Print this message.
    -a      All -- Only print 'All names' section.
    -f      File -- Query a specific file rather than "Credits-Person*csv".
    -s      Summarize -- Only print 'Duplicated names' section.
    -i      Print info about any files that are searched.

EXAMPLES:
    ./xrefCast.sh "Olivia Colman"
    ./xrefCast.sh "Queen Elizabeth II" "Princess Diana"
    ./xrefCast.sh "The Crown"
    ./xrefCast.sh -s "The Night Manager" "The Crown" "The Durrells in Corfu"
    ./xrefCast.sh -af Clooney.csv "Brad Pitt"
EOF
}

# Don't leave tempfiles around
trap terminate EXIT
#
function terminate() {
    if [ -n "$DEBUG" ]; then
        printf "\nTerminating: $(basename $0)\n" >&2
        printf "Not removing:\n" >&2
        printf "$TMPFILE $SEARCH_TERMS\n" >&2
    else
        rm -rf $TMPFILE $SEARCH_TERMS
    fi
}

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

while getopts ":f:hasi" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    a)
        ALL_NAMES_ONLY="yes"
        ;;
    s)
        SUMMARIZE="yes"
        ;;
    i)
        INFO="yes"
        ;;
    f)
        SEARCH_FILE="$OPTARG"
        ;;
    \?)
        printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2
        ;;
    :)
        printf "==> Option -$OPTARG requires a 'translation file' argument'.\n\n" >&2
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

# If a SEARCH_FILE was specified...
if [ -n "$SEARCH_FILE" ]; then
    # Make sure it exists, no way to recover
    if [ ! -e "$SEARCH_FILE" ]; then
        printf "==> [${RED}Error${NO_COLOR}] Missing search file: $SEARCH_FILE\n\n" >&2
        exit 1
    fi
else
    SEARCH_FILE="Credits-Person.csv"
    # If it doesn't exist, generate it
    [ ! -e "$SEARCH_FILE" ] && ensureDataFiles
fi

# Make sure a search term is supplied
if [ $# -eq 0 ]; then
    printf "==> I can cross-reference shows, actors, and the characters they portray,\n"
    printf "    such as The Crown, Olivia Colman, and Queen Elizabeth -- as long as\n"
    printf "    the search terms exist in $SEARCH_FILE\n\n"
    printf "Only one search term per line. Enter a blank line to finish.\n"
    while read -r -p "Enter a show, actor, or character: " searchTerm; do
        [ -z "$searchTerm" ] && break
        tr -ds '"' '[[:space:]]' <<<"$searchTerm" >>$SEARCH_TERMS
    done </dev/tty
    if [ ! -s "$SEARCH_TERMS" ]; then
        if waitUntil $ynPref -N "Would you like to see who played Queen Elizabeth II?"; then
            printf "Queen Elizabeth II\n" >>$SEARCH_TERMS
            printf "\n"
        else
            exit 1
        fi
    fi
fi

# Let us know how many records we're searching
numRecords=$(sed -n '$=' $SEARCH_FILE)
[ "$INFO" == "yes" ] && printf "==> Searching $numRecords records in $SEARCH_FILE for cast data.\n\n"

# Setup SEARCH_TERMS with one search term per line, let us know what's in it.
printf "==> Searching for:\n"
for a in "$@"; do
    printf "$a\n" >>$SEARCH_TERMS
done
cat $SEARCH_TERMS

# Setup awk printf formats with spaces or tabs
# Name|Job|Show|Episode|Role
PSPACE='%-20s  %-10s  %-40s  %-17s  %s\n'
PTAB='%s\t%s\t%s\t%s\t%s\n'

# If we find anything, rearrange it and put it in TMPFILE
if [ $(rg -wNzSI -c -f $SEARCH_TERMS $SEARCH_FILE) ]; then
    rg -wNzSI --color always -f $SEARCH_TERMS $SEARCH_FILE |
        awk -F "\t" -v PF="$PTAB" '{printf (PF, $1,$5,$2,$3,$6)}' |
        sort -f --field-separator=$'\t' --key=1,1 --key=3,3 -fu >$TMPFILE
fi

# Get rid of initial single quote that was used to force show/episode names in spreadsheet to be strings.
perl -pi -e "s+\t'+\t+g;" $TMPFILE

# Unless SUMMARIZE, put all search results into tabular format and print them
if [ -z "$SUMMARIZE" ]; then
    printf "\n==> All names (Name|Job|Show|Episode|Role):\n"
    if checkForExecutable -q xsv; then
        xsv table -d "\t" $TMPFILE
    else
        awk -F "\t" -v PF="$PSPACE" '{printf (PF,$1,$2,$3,$4,$5)}' $TMPFILE
    fi
fi

# If ALL_NAMES_ONLY, exit here
[ -n "$ALL_NAMES_ONLY" ] && exit

# Print duplicated names, i.e. where field 1 is repeated in successive lines, but field 3 is different
printf "\n==> Duplicated names (Name|Job|Show|Episode|Role):\n"
if checkForExecutable -q xsv; then
    awk -F "\t" -v PF="$PTAB" '{if($1==f[1]&&$3!=f[3]) {printf(PF,f[1],f[2],f[3],f[4],f[5]);
    printf(PF,$1,$2,$3,$4,$5)} split($0,f)}' $TMPFILE | sort -fu | xsv table -d "\t"
else
    awk -F "\t" -v PF="$PSPACE" '{if($1==f[1]&&$3!=f[3]) {printf(PF,f[1],f[2],f[3],f[4],f[5]);
    printf(PF,$1,$2,$3,$4,$5)} split($0,f)}' $TMPFILE | sort -fu
fi
