#!/usr/bin/env bash
#
# Add a tconst to a file

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd $DIRNAME
export LC_COLLATE="C"
. functions/define_colors
. functions/define_files
. functions/load_functions

# Limit the number of results to display in case someone uses an unquoted string
# We may be able to suggest new search results after we enhance the search logic
maxResults=100

function help() {
    cat <<EOF
Add a tconst to a file

USAGE:
    ./createTconstFile.sh [-f TCONST_FILE] TCONST [TCONST...] [SHOW TITLE...]

OPTIONS:
    -h      Print this message.
    -f      File -- Add to specific file rather than the default $USER.tconst

EXAMPLES:
    ./createTconstFile.sh tt1606375
    ./createTconstFile.sh tt1606375 tt1399664 'Broadchurch'
    ./createTconstFile.sh -f Dramas.tconst tt1606375

EOF
}

# Don't leave tempfiles around
trap "rm -rf $SEARCH_TERMS $SEARCH_RESULTS $FINAL_RESULTS $BESTMATCH" EXIT

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

while getopts ":f:h" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    f)
        TCONST_FILE="$OPTARG"
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

# Need some tempfiles
SEARCH_TERMS=$(mktemp)
SEARCH_RESULTS=$(mktemp)
FINAL_RESULTS=$(mktemp)
BESTMATCH=$(mktemp)

# Make sure a tconst was supplied
if [ $# -eq 0 ]; then
    printf "==> [Error] Please supply one or more tconst IDs -- such as tt1606375,\n"
    printf "    which is the tconst for 'Downton Abbey'.\n"
    if ask_YN "Would you like me to add this tconst for you?" N; then
        printf "tt1606375\n" >>$SEARCH_TERMS
    else
        exit 1
    fi
fi

# Make sure we have the gz file to search
if [ ! -e "title.basics.tsv.gz" ]; then
    printf "==> Missing title.basics.tsv.gz. Run downloadIMDbFiles.sh to fix this problem.\n"
    if ask_YN "Would you like me to do this for you?" N; then
        printf "Ok. Downloading...\n"
        ./downloadIMDbFiles.sh 2>/dev/null
    else
        printf "Skipping download. Try again after running downloadIMDbFiles.sh.\n"
        exit
    fi
fi

function addToFileP() {
    if ask_YN "    Shall I add them to $TCONST_FILE?" Y; then
        printf "Ok. Adding:\n"
        cat $FINAL_RESULTS >>$TCONST_FILE
        ask_YN "    Shall I sort $TCONST_FILE by title?" Y && ./augment_tconstFiles.sh -iy $TCONST_FILE
        ask_YN "    Shall I update your data files?"  Y && ./generateXrefData.sh -q
    else
        printf "Skipping....\n"
    fi
}

# Get a TCONST_FILE
[ -z "$TCONST_FILE" ] && TCONST_FILE="$USER.tconst"
#
printf "==> Adding tconst IDs to $TCONST_FILE\n\n"

# Setup SEARCH_TERMS with one search term per line, let us know what's in it.
printf "==> Searching for:\n"
for a in "$@"; do
    printf "$a\n" >>$SEARCH_TERMS
done
cat $SEARCH_TERMS
printf "\n"

# Find the tconst IDs
rg -wNz -f $SEARCH_TERMS "title.basics.tsv.gz" | rg -v "tvEpisode" | cut -f 1-4 |
    sort -fu --field-separator=$'\t' --key=2 | tee $FINAL_RESULTS >$SEARCH_RESULTS

# How many SEARCH_TERMS and SEARCH_RESULTS are there?
numSearched=$(sed -n '$=' $SEARCH_TERMS)
numFound=$(sed -n '$=' $SEARCH_RESULTS)

# Didn't find any results
if [[ $numFound -eq "0" ]]; then
    printf "==> Didn't find ${RED}any${NO_COLOR} matching shows. "
    printf "Check the \"Searching for:\" section above.\n\n"
    exit
fi

# Found some shows. Let us know what types.
printf "==> This will add the following:\n"
cut -f 2 $SEARCH_RESULTS | summarizeTypes

# Found too many results.
if [[ $numFound -ge "$maxResults" ]]; then
    printf "\n==> $numFound results is too many to reasonably display. "
    printf "Check the \"Searching for:\" section above.\n"
    printf "    ** You need to quote a 'show name' if it includes spaces. **\n\n"
    exit
fi

# Vary number of tabs before "Title"
function printHeader() {
    printf "\n# tconst\tType\t"
    [[ ${#2} -gt 8 ]] && printf "\t"
    printf "Title\n"
}
#
printHeader $(head -1 $SEARCH_RESULTS)

# Let us know what shows this would add
# Displaying more than three columns is confusing if cols 3 & 4 are the same
cut -f 1-3 $SEARCH_RESULTS

# Found the same number of results we were searching for
if [[ $numSearched -eq $numFound ]]; then
    printf "\n==> Found all the shows searched for.\n"
    addToFileP
fi

# Found fewer than we were searching for
if [[ $numSearched -gt $numFound ]]; then
    printf "\n==> Found fewer shows than expected. Check the \"Searching for:\" section above.\n"
    addToFileP
fi

# Found more than we were searching for
if [[ $numFound -gt $numSearched ]]; then
    printf "\n==> Found more shows than expected.\n"
    rg -wN "^tt[0-9]{7,8}" $SEARCH_TERMS >$BESTMATCH
    rg -wN -f $BESTMATCH $SEARCH_RESULTS | tee $FINAL_RESULTS
    if [ -s $FINAL_RESULTS ]; then
        printf "\n==> These are the most likely matches.\n"
        addToFileP
    fi
    printf "\n==> These are the ${RED}questionable${NO_COLOR} matches.\n"
    rg -wNv -f $BESTMATCH $SEARCH_RESULTS | sort -f --field-separator=$'\t' --key=2,2 --key=3,3
    printf "\n==> Sorry, but I can't resolve this automatically quite yet. If you spot the\n"
    printf "    tconst of the show you want, re-run ./createTconstFile.sh with that tconst.\n"
    printf "\n==> ${RED}Some candidates${NO_COLOR} are:\n"
    rg -wNv -f $BESTMATCH $SEARCH_RESULTS | rg -e "\ttvSeries\t" -e "\ttvMiniSeries\t" |
        sort -f --field-separator=$'\t' --key=2,2 --key=3,3
fi
