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
cd $DIRNAME
. functions/define_colors
. functions/define_files
. functions/load_functions

function help() {
    cat <<EOF
Cross-reference shows, actors, and the characters they portray using data from IMDB.

USAGE:
    ./xrefCast.sh [OPTIONS] [-f SEARCH_FILE] SEARCH_TERM [SEARCH_TERM ...]

OPTIONS:
    -h      Print this message.
    -a      All -- Only print 'All names' section.
    -f      File -- Query a specific file rather than "Credits-Person*csv".
    -s      Summarize -- Only print 'Duplicated names' section.
    -i      Print info about any files that are searched.

EXAMPLES:
    ./xrefCast.sh 'Olivia Colman'
    ./xrefCast.sh 'Queen Elizabeth II' 'Princess Diana'
    ./xrefCast.sh 'The Crown'
    ./xrefCast.sh -s 'The Night Manager' 'The Crown' 'The Durrells in Corfu'

EOF
}

# Don't leave tempfiles around
trap "rm -rf $TMPFILE $SEARCH_TERMS" EXIT

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
        printf "Option -$OPTARG requires a 'translation file' argument'.\n\n" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

# Need some tempfiles
TMPFILE=$(mktemp)
SEARCH_TERMS=$(mktemp)

# Make sure a search term was supplied
if [ $# -eq 0 ]; then
    printf "==> [Error] Please supply one or more search terms.\n\n" >&2
    exit 1
fi

# Get latest Credits-Person file to search
[ -z "$SEARCH_FILE" ] && SEARCH_FILE="$(ls -1t Credits-Person*csv 2>/dev/null | head -1)"
#
if [ ! "$SEARCH_FILE" ]; then
    printf "==> [Error] Missing search file: Credits-Person*csv\n" >&2
    printf "    Run ./generateXrefData.sh then re-run this search.\n\n" >&2
    exit 1
fi
# Make sure SEARCH_FILE exists
if [ ! -e "$SEARCH_FILE" ]; then
    printf "==> [Error] Missing search file: $SEARCH_FILE\n\n" >&2
    exit 1
fi
#
[ "$INFO" == "yes" ] && printf "==> Searching $SEARCH_FILE for cast data.\n\n"

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
    if checkForExecutable xsv quietly; then
        xsv table -d "\t" $TMPFILE
    else
        awk -F "\t" -v PF="$PSPACE" '{printf (PF,$1,$2,$3,$4,$5)}' $TMPFILE
    fi
fi

# If ALL_NAMES_ONLY, exit here
[ -n "$ALL_NAMES_ONLY" ] && exit

# Print duplicated names, i.e. where field 1 is repeated in successive lines, but field 3 is different
printf "\n==> Duplicated names (Name|Job|Show|Episode|Role):\n"
if checkForExecutable xsv quietly; then
    awk -F "\t" -v PF="$PTAB" '{if($1==f[1]&&$3!=f[3]) {printf(PF,f[1],f[2],f[3],f[4],f[5]);
    printf(PF,$1,$2,$3,$4,$5)} split($0,f)}' $TMPFILE | sort -fu | xsv table -d "\t"
else
    awk -F "\t" -v PF="$PSPACE" '{if($1==f[1]&&$3!=f[3]) {printf(PF,f[1],f[2],f[3],f[4],f[5]);
    printf(PF,$1,$2,$3,$4,$5)} split($0,f)}' $TMPFILE | sort -fu
fi
