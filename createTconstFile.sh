#!/usr/bin/env bash
#
# Add a tconst to a file

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

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd $DIRNAME

. functions/define_colors
. functions/ask_YN.function
. functions/read_YN.function

# Make sort consistent between Mac and Linux
export LC_COLLATE="C"

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
RESULTS=$(mktemp)
SEARCH_TERMS=$(mktemp)
BESTMATCH=$(mktemp)

# Don't leave tempfiles around
trap "rm -rf $RESULTS $SEARCH_TERMS $BESTMATCH" EXIT

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    rm -rf $RESULTS $SEARCH_TERMS $BESTMATCH
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

# Make sure a tconst was supplied
if [ $# -eq 0 ]; then
    printf "==> [Error] Please supply one or more tconst IDs -- such as tt1606375.\n"
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

# Can't use /t in "sort --field-separator", so setup a TAB variable
TAB=$(printf "\t")

# Find the tconst IDs
rg -wNz -f $SEARCH_TERMS "title.basics.tsv.gz" | rg -v "tvEpisode" | cut -f 1-4 |
    sort -fu --field-separator="$TAB" --key=2 >$RESULTS

# Let us know what types of shows we found
printf "==> This will add the following:\n"
cut -f 2 $RESULTS | sort | uniq -c

# Vary number of tabs before "Title"
function printHeader() {
    printf "\n# tconst\tType\t"
    [[ ${#2} -gt 8 ]] && printf "\t"
    printf "Title\n"
}
#
printHeader $(head -1 $RESULTS)

# Let us know what show this would add
cut -f 1-3 $RESULTS

# See if we found the right number of results
numSearched=$(sed -n '$=' $SEARCH_TERMS)
numFound=$(sed -n '$=' $RESULTS)

# Found the same number we were searching for
if [[ $numSearched -eq $numFound ]]; then
    printf "\n==> Found all the shows searched for.\n"
    if ask_YN "    Shall I add these to $TCONST_FILE?" Y; then
        printf "Ok. Adding:\n"
        cat $RESULTS >>$TCONST_FILE
        ask_YN "Shall I sort $TCONST_FILE by title?" Y && ./augment_tconstFiles.sh -i $TCONST_FILE
    else
        printf "Skipping....\n"
    fi
fi

# Found fewer than we were searching for
if [[ $numSearched -gt $numFound ]]; then
    printf "\n==> Found fewer shows than expected. Check the \"Searching for:\" section above.\n"
    if ask_YN "    Shall I add the ones I found to $TCONST_FILE?" Y; then
        printf "Ok. Adding:\n"
        cat $RESULTS >>$TCONST_FILE
        ask_YN "Shall I sort $TCONST_FILE by title?" Y && ./augment_tconstFiles.sh -i $TCONST_FILE
    else
        printf "Skipping....\n"
    fi
fi

# Found more than we were searching for
if [[ $numFound -gt $numSearched ]]; then
    printf "\n==> Found more shows than expected. These are the most likely matches.\n"
    rg -wN "^tt[0-9]{7,8}" $SEARCH_TERMS >$BESTMATCH
    rg -wN -f $BESTMATCH $RESULTS
    printf "\n==> These are the questionable matches.\n"
    rg -wNv -f $BESTMATCH $RESULTS
    printf "\n==> Sorry I can't help resolve this yet.\n"
fi

# Clean up
rm -rf $RESULTS $SEARCH_TERMS $BESTMATCH
