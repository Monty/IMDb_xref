#!/usr/bin/env bash
#
# Generate show and cast spreadsheets from:
#   1) .tconst file(s) containing a list of IMDb tconst identifiers
#
#       See https://www.imdb.com/interfaces/ for a description of IMDb Datasets
#       tconst (string) - alphanumeric unique identifier of the title
#
#       For example:
#           tt4380324
#           tt5433600
#           tt0408381
#           ...
#
#       Defaults to all .tconst files, or specify them on the command line
#
#    2) .xlate file(s) with tab separated pairs of non-English titles and their English equivalents
#
#       For example:
#           Brandvägg	Wallander: The Original Episodes
#           Capitaine Marleau	Captain Marleau
#           Den fördömde	Sebastian Bergman
#           ...
#
#       Defaults to all .xlate files, or specify one with -x [file] on the command line

# Keep track of elapsed time
SECONDS=0
scriptName="$(basename $0)"
savedFile=".durations"
touch $savedFile

# Save or update the elapsed time and exit
function saveDuration() {
    tm=$1
    mins="minute"
    #
    [[ $tm -ge 120 ]] && mins="minutes"
    if [[ $tm -gt 90 ]]; then
        duration="$scriptName\t$(date +%c) \t$((tm / 60)) $mins and $((TM % 60)) seconds"
    else
        duration="$scriptName\t$(date +%c) \t$((tm)) seconds"
    fi
    if [ $(rg -c "^$scriptName\t" $savedFile) ]; then
        perl -pi -e "s/$scriptName.*/$duration/" $savedFile
    else
        printf "$duration\n" >>$savedFile
    fi
    exit
}

function help() {
    cat <<EOF
Create lists and spreadsheets of shows, actors, and the characters they portray from
downloaded IMDb .gz files. See https://www.imdb.com/interfaces/ for details of the data
they contain.

USAGE:
    ./generateXrefData.sh [-x translation file] [tconst file ...]

OPTIONS:
    -h      Print this message.
    -d      Diff -- Create a 'diff' file comparing current against previously saved results.
    -o      Output -- Save file that can later be used for queries with "xrefCast.sh -f"
    -q      Quiet -- Minimize output, print only the list of shows being processed.
    -t      Test mode -- Use tconst.example, xlate.example; diff against test_results.
    -v      Debug mode -- set -v, enable 'breakpoint' function when editing this script.
    -x      Xlate -- Use a specific translation file instead of *xlate.
EOF
}

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\n"
    exit 130
}

function breakpoint() {
    if [ -n "$DEBUG" ]; then
        read -r -p "Quit now? [y/N] " YESNO
        if [ "$YESNO" == "y" ]; then
            printf "Quitting ...\n"
            exit 1
        fi
    fi
}

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd $DIRNAME

# Make sort consistent between Mac and Linux
export LC_COLLATE="C"

while getopts ":o:x:hdqtv" opt; do
    case $opt in
    d)
        CREATE_DIFF="yes"
        ;;
    h)
        help
        exit
        ;;
    o)
        OUTPUT_FILE="$OPTARG"
        ;;
    q)
        QUIET="yes"
        ;;
    t)
        TEST_MODE="yes"
        ;;
    v)
        DEBUG="yes"
        ;;
    x)
        XLATE_FILES="$OPTARG"
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

# Make sure we can execute rg.
if [ ! -x "$(which rg 2>/dev/null)" ]; then
    printf "[Error] Can't run rg. Install rg and rerun this script.\n"
    printf "        zgrep could be used, but is 15x slower in my tests.\n"
    printf "        See https://crates.io/crates/ripgrep for details.\n"
    exit 1
fi

# Make sure we have downloaded the IMDb files
if [ -e "name.basics.tsv.gz" ] && [ -e "title.basics.tsv.gz" ] && [ -e "title.principals.tsv.gz" ] &&
    [ -e "title.episode.tsv.gz" ]; then
    [ -s $QUIET ] && printf "==> Using existing IMDb .gz files.\n"
else
    [ -s $QUIET ] && printf "==> Downloading new IMDb .gz files.\n"
    # Make sure we can execute curl.
    if [ ! -x "$(which curl 2>/dev/null)" ]; then
        printf "[Error] Can't run curl. Install curl and rerun this script.\n"
        printf "        To test, type:  curl -Is https://github.com/ | head -5\n"
        exit 1
    fi
    for file in name.basics.tsv.gz title.basics.tsv.gz title.episode.tsv.gz title.principals.tsv.gz; do
        if [ ! -e "$file" ]; then
            source="https://datasets.imdbws.com/$file"
            [ -s $QUIET ] && printf "Downloading $source\n"
            curl -s -O $source
        fi
    done
fi
[ -s $QUIET ] && printf "\n"

# If the user hasn't created a .tconst or .xlate file, create a small example from a PBS show.
# This is relatively harmless, and keeps this script simpler.
if [ ! "$(ls *.xlate 2>/dev/null)" ]; then
    [ -s $QUIET ] && printf "==> Creating an example translation file: PBS.xlate\n\n"
    rg -Ne "^#" -e "^$" -e "The Durrells" xlate.example >"PBS.xlate"
fi
if [ ! "$(ls *.tconst 2>/dev/null)" ]; then
    [ -s $QUIET ] && printf "==> Creating an example tconst file: PBS.tconst\n\n"
    rg -Ne "^#" -e "^$" -e "The Durrells" -e "The Night Manager" -e "The Crown" tconst.example >"PBS.tconst"
fi

# Pick xlate file(s) to process if not specified with -x option
[ -z "$XLATE_FILES" ] && XLATE_FILES="*.xlate"
[ -n "$TEST_MODE" ] && XLATE_FILES="xlate.example"
#
if [ "$XLATE_FILES" == "*.xlate" ]; then
    [ -s $QUIET ] && printf "==> Using all .xlate files for IMDb title translation.\n\n"
else
    [ -s $QUIET ] && printf "==> Using $XLATE_FILES for IMDb title translation.\n\n"
fi
if [ ! "$(ls $XLATE_FILES 2>/dev/null)" ]; then
    printf "==> [Error] No such file(s): $XLATE_FILES\n"
    exit 1
fi

# Pick tconst file(s) to process
[ $# -eq 0 ] && TCONST_FILES="*.tconst" || TCONST_FILES="$@"
[ -n "$TEST_MODE" ] && TCONST_FILES="tconst.example"
#
if [ "$TCONST_FILES" == "*.tconst" ]; then
    [ -s $QUIET ] && printf "==> Searching all .tconst files for IMDb title identifiers.\n\n"
else
    [ -s $QUIET ] && printf "==> Searching $TCONST_FILES for IMDb title identifiers.\n\n"
fi
if [ ! "$(ls $TCONST_FILES 2>/dev/null)" ]; then
    printf "==> [Error] No such file(s): $TCONST_FILES\n"
    exit 1
fi

# Create some timestamps
DATE_ID="-$(date +%y%m%d)"
LONGDATE="-$(date +%y%m%d.%H%M%S)"

# Required subdirectories
WORK="secondary"
BASE="baseline"
[ -n "$TEST_MODE" ] && BASE="test_results"
mkdir -p $WORK $BASE

# Error and debugging info (per run)
POSSIBLE_DIFFS="diffs$LONGDATE.txt"
ERRORS="anomalies$LONGDATE.txt"
[ -n "$CREATE_DIFF" ] &&
    printf "\n==> $POSSIBLE_DIFFS contains diffs between generated files and files saved in $BASE\n"

# Final output spreadsheets
CREDITS_SHOW="Credits-Show$DATE_ID.csv"
CREDITS_PERSON="Credits-Person$DATE_ID.csv"
KNOWN_PERSONS="Persons-KnownFor$DATE_ID.csv"
SHOWS="Shows-Episodes$DATE_ID.csv"
LINKS_TO_PERSONS="LinksToPersons$DATE_ID.csv"
LINKS_TO_TITLES="LinksToTitles$DATE_ID.csv"
ASSOCIATED_TITLES="AssociatedTitles$DATE_ID.csv"

# Final output lists
UNIQUE_PERSONS="uniqPersons$DATE_ID.txt"
UNIQUE_TITLES="uniqTitles$DATE_ID.txt"

# Intermediate working files
DUPES="$WORK/dupes$DATE_ID.txt"
CONFLICTS="$WORK/conflicts$DATE_ID.txt"
TCONST_LIST="$WORK/tconst$DATE_ID.txt"
EPISODES_LIST="$WORK/tconst-episodes$DATE_ID.txt"
KNOWNFOR_LIST="$WORK/tconst_known$DATE_ID.txt"
NCONST_LIST="$WORK/nconst$DATE_ID.txt"
RAW_SHOWS="$WORK/raw_shows$DATE_ID.csv"
RAW_EPISODES="$WORK/raw_episodes$DATE_ID.csv"
RAW_PERSONS="$WORK/raw_persons$DATE_ID.csv"
UNSORTED_CREDITS="$WORK/unsorted_credits$DATE_ID.csv"
UNSORTED_EPISODES="$WORK/unsorted_episodes$DATE_ID.csv"
#
TCONST_SHOWS_PL="$WORK/tconst-shows-pl$DATE_ID.txt"
TCONST_EPISODES_PL="$WORK/tconst-episodes-pl$DATE_ID.txt"
TCONST_EPISODE_NAMES_PL="$WORK/tconst-episode_names-pl$DATE_ID.txt"
TCONST_KNOWN_PL="$WORK/tconst-known-pl$DATE_ID.txt"
NCONST_PL="$WORK/nconst-pl$DATE_ID.txt"
XLATE_PL="$WORK/xlate-pl$DATE_ID.txt"

# Manually entered list of tconst ID's that we don't want tvEpisodes for
# either because they have too many episodes, or the episodes don't translate well
SKIP_EPISODES="skipEpisodes.example"
SKIP_TCONST="$WORK/tconst-skip$DATE_ID.txt"

# Saved files used for comparison with current files
PUBLISHED_SKIP_EPISODES="$BASE/skipEpisodes.example"
PUBLISHED_CREDITS_SHOW="$BASE/Credits-Show.csv"
PUBLISHED_CREDITS_PERSON="$BASE/Credits-Person.csv"
PUBLISHED_KNOWN_PERSONS="$BASE/Persons-KnownFor.csv"
PUBLISHED_SHOWS="$BASE/Shows.csv"
PUBLISHED_LINKS_TO_PERSONS="$BASE/LinksToPersons.csv"
PUBLISHED_LINKS_TO_TITLES="$BASE/LinksToTitles.csv"
PUBLISHED_ASSOCIATED_TITLES="$BASE/AssociatedTitles.csv"
#
PUBLISHED_UNIQUE_PERSONS="$BASE/uniqPersons.txt"
PUBLISHED_UNIQUE_TITLES="$BASE/uniqTitles.txt"
#
PUBLISHED_TCONST_LIST="$BASE/tconst.txt"
PUBLISHED_EPISODES_LIST="$BASE/tconst-episodes.csv"
PUBLISHED_KNOWNFOR_LIST="$BASE/tconst_known.txt"
PUBLISHED_NCONST_LIST="$BASE/nconst.txt"
PUBLISHED_RAW_SHOWS="$BASE/raw_shows.csv"
PUBLISHED_RAW_PERSONS="$BASE/raw_persons.csv"

# Filename groups used for cleanup
ALL_WORKING="$CONFLICTS $DUPES $SKIP_TCONST $TCONST_LIST $NCONST_LIST "
ALL_WORKING+="$EPISODES_LIST $KNOWNFOR_LIST $XLATE_PL $TCONST_SHOWS_PL "
ALL_WORKING+="$NCONST_PL $TCONST_EPISODES_PL $TCONST_EPISODE_NAMES_PL $TCONST_KNOWN_PL"
ALL_TXT="$UNIQUE_TITLES $UNIQUE_PERSONS"
ALL_CSV="$RAW_SHOWS $RAW_PERSONS $UNSORTED_EPISODES $UNSORTED_CREDITS"
ALL_SPREADSHEETS="$LINKS_TO_TITLES $LINKS_TO_PERSONS $SHOWS $KNOWN_PERSONS $ASSOCIATED_TITLES "
ALL_SPREADSHEETS+="$CREDITS_SHOW $CREDITS_PERSON "

# Cleanup any possible leftover files
rm -f $ALL_WORKING $ALL_TXT $ALL_CSV $ALL_SPREADSHEETS

[ -n "$DEBUG" ] && set -v
# Coalesce a single tconst input list
rg -IN "^tt" $TCONST_FILES | cut -f 1 | sort -u >$TCONST_LIST

# Create a perl "substitute" script to translate any known non-English titles to their English equivalent
# Regex delimiter needs to avoid any characters present in the input, use {} for readability
rg -INv -e "^#" -e "^$" $XLATE_FILES | cut -f 1,2 | sort -fu |
    perl -p -e 's+\t+\\t}\{\\t+; s+^+s{\\t+; s+$+\\t};+' >$XLATE_PL

# Generate a csv of titles from the tconst list, remove the "adult" field,
# translate any known non-English titles to their English equivalent,
TAB=$(printf "\t")
rg -wNz -f $TCONST_LIST title.basics.tsv.gz | cut -f 1-4,6-9 | perl -p -f $XLATE_PL |
    perl -p -e 's+\t+\t\t\t+;' | tee $RAW_SHOWS | cut -f 5 | sort -fu >$UNIQUE_TITLES

# Check for translation conflicts
rg -INv -e "^#" -e "^$" $XLATE_FILES | cut -f 1 | sort -f | uniq -d >$DUPES

rg -IN -f $DUPES $XLATE_FILES | sort -fu | cut -f 1 | sort -f | uniq -d >$CONFLICTS
cut -f 6 $RAW_SHOWS | sort -f | uniq -d >>$CONFLICTS
if [ -s $CONFLICTS ]; then
    printf "\n==> [Error] Conflicts are listed below. Fix them then rerun this script.\n"
    printf "\n==> These shows have more than one tconst for the same title.\n"
    rg -H -f $CONFLICTS $RAW_SHOWS
    printf "\n"
    printf "==> You need to delete all but one tconst per title in any files listed below.\n"
    printf "    It may help to look up each tconst on IMDb to pick the best one to keep.\n"
    printf "    Make sure to delete corresponding .tconst lines if more than one file is listed.\n"
    rg -f $CONFLICTS $XLATE_FILES $TCONST_FILES
    printf "\n"
    exit 1
fi

# We don't want to check for episodes in any tvSeries that has hundreds of tvEpisodes
# or that has episodes with titles that aren't unique like "Episode 1" that can't be "translated"
# back to the original show. Manually maintain a skip list in $SKIP_EPISODES.
rg -v -e "^#" -e "^$" $SKIP_EPISODES | cut -f 1 >$SKIP_TCONST

# Let us know what shows we're processing - format for readability, separate with ";"
num_titles=$(sed -n '$=' $UNIQUE_TITLES)
printf "==> Processing $num_titles shows found in $TCONST_FILES:\n"
perl -p -e 's+$+;+' $UNIQUE_TITLES | fmt -w 80 | perl -p -e 's+^+\t+' | sed '$ s+.$++'

# Let us know how long it took last time
if [ $(rg -c "^$scriptName\t" $savedFile) ]; then
    printf "\n==> Previously, this took "
    rg "^$scriptName\t" $savedFile | cut -f 3
    printf "\n"
fi

# Use the tconst list to lookup episode IDs and generate an episode tconst file
rg -wNz -f $TCONST_LIST title.episode.tsv.gz | perl -p -e 's+\\N++g;' |
    sort -f --field-separator="$TAB" --key=2,2 --key=3,3n --key=4,4n | rg -wv -f $SKIP_TCONST |
    tee $UNSORTED_EPISODES | cut -f 1 >$EPISODES_LIST

# Use the episodes list to generate raw episodes
rg -wNz -f $EPISODES_LIST title.basics.tsv.gz | cut -f 1-4,6-9 | perl -p -f $XLATE_PL |
    perl -p -e 's+\\N++g;' | sort -f --field-separator="$TAB" --key=3,3 --key=5,5 --key=4,4 >$RAW_EPISODES

# Use the tconst list to lookup principal titles and generate a tconst/nconst credits csv
# Fix bogus nconst nm0745728, it should be nm0745694. Rearrange fields
rg -wNz -f $TCONST_LIST title.principals.tsv.gz | rg -w -e actor -e actress -e writer -e director |
    sort --key=1,1 --key=2,2n | perl -p -e 's+nm0745728+nm0745694+' | perl -p -e 's+\\N++g;' |
    perl -F"\t" -lane 'printf "%s\t%s\t\t%02d\t%s\t%s\n", @F[2,0,1,3,5]' | tee $UNSORTED_CREDITS |
    cut -f 1 | sort -u >$NCONST_LIST

# Use the episodes list to lookup principal titles and add to the tconst/nconst credits csv
rg -wNz -f $EPISODES_LIST title.principals.tsv.gz | rg -w -e actor -e actress -e writer -e director |
    sort --key=1,1 --key=2,2n | perl -p -e 's+\\N++g;' |
    perl -F"\t" -lane 'printf "%s\t%s\t%s\t%02d\t%s\t%s\n", @F[2,0,0,1,3,5]' | tee -a $UNSORTED_CREDITS |
    cut -f 1 | sort -u | rg -v -f $NCONST_LIST >>$NCONST_LIST

# Create a perl script to globally convert a show tconst to a show title
cut -f 1,5 $RAW_SHOWS | perl -F"\t" -lane 'print "s{\\b@F[0]\\b}\{'\''@F[1]}g;";' >$TCONST_SHOWS_PL

# Create a perl script to convert an episode tconst to its parent show title
perl -F"\t" -lane 'print "s{\\b@F[0]\\b}\{@F[1]\\t@F[2]\\t@F[3]};";' $UNSORTED_EPISODES |
    perl -p -f $TCONST_SHOWS_PL >$TCONST_EPISODES_PL

# Create a perl script to convert an episode tconst to its episode title
perl -F"\t" -lane 'print "s{\\b@F[0]\\b}\{'\''@F[2]};";' $RAW_EPISODES >$TCONST_EPISODE_NAMES_PL

# Convert raw episodes to raw shows
perl -pi -f $TCONST_EPISODES_PL $RAW_EPISODES

# Remove extra tab fields from $TCONST_EPISODES_PL
perl -pi -e 's/\\t.*}/}/' $TCONST_EPISODES_PL

# Create a perl script to convert an nconst to a name
rg -wNz -f $NCONST_LIST name.basics.tsv.gz | perl -p -e 's+\\N++g;' | cut -f 1-2,6 | sort -fu --key=2 |
    tee $RAW_PERSONS | perl -F"\t" -lane 'print "s{^@F[0]\\b}\{@F[1]};";' >$NCONST_PL

# Get rid of ugly \N fields, unneeded characters, and make sure commas are followed by spaces
perl -pi -e 's+\\N++g; tr+"[]++d; s+,+, +g; s+,  +, +g;' $ALL_CSV

# Create the KNOWN_PERSONS spreadsheet
printf "Person\tKnown For Titles: 1\tKnown For Titles: 2\tKnown For Titles: 3\tKnown For Titles: 4\n" \
    >$KNOWN_PERSONS
cut -f 1,3 $RAW_PERSONS | perl -p -e 's+, +\t+g' >>$KNOWN_PERSONS

# Create the LINKS_TO_PERSONS spreadsheet
printf "nconst\tName\tHyperlink to Name\n" >$LINKS_TO_PERSONS
cut -f 1,2 $RAW_PERSONS | perl -F"\t" -lane \
    'print "@F[0]\t@F[1]\t=HYPERLINK(\"https://www.imdb.com/name/@F[0]\";\"@F[1]\")";' |
    sort -fu --field-separator="$TAB" --key=2,2 >>$LINKS_TO_PERSONS

# Create a tconst list of the knownForTitles
cut -f 3 $RAW_PERSONS | rg "^tt" | perl -p -e 's+, +\n+g' | sort -u >$KNOWNFOR_LIST

# Create a perl script to globally convert a known show tconst to a show title
rg -wNz -f $KNOWNFOR_LIST title.basics.tsv.gz | perl -p -f $XLATE_PL | cut -f 1,3 |
    perl -F"\t" -lane 'print "s{\\b@F[0]\\b}\{'\''@F[1]}g;";' >$TCONST_KNOWN_PL

# Create the LINKS_TO_TITLES spreadsheet
printf "tconst\tShow Title\tHyperlink to Title\n" >$LINKS_TO_TITLES
perl -p -e 's+^.*btt+tt+; s+\\b}\{+\t+; s+}.*++;' $TCONST_SHOWS_PL | perl -F"\t" -lane \
    'print "@F[0]\t@F[1]\t=HYPERLINK(\"https://www.imdb.com/title/@F[0]\";\"" . substr(@F[1],1) . "\")";' |
    sort -fu --field-separator="$TAB" --key=2,2 >>$LINKS_TO_TITLES

# Create a spreadsheet of associated titles gained from IMDb knownFor data
printf "tconst\tShow Title\tHyperlink to Title\n" >$ASSOCIATED_TITLES
perl -p -e 's+^.*btt+tt+; s+\\b}\{+\t+; s+}.*++;' $TCONST_KNOWN_PL | perl -F"\t" -lane \
    'print "@F[0]\t@F[1]\t=HYPERLINK(\"https://www.imdb.com/title/@F[0]\";\"" . substr(@F[1],1) . "\")";' |
    sort -fu --field-separator="$TAB" --key=2,2 | rg -wv -f $TCONST_LIST >>$ASSOCIATED_TITLES

# Add episodes into raw shows
perl -p -f $TCONST_EPISODES_PL $RAW_EPISODES >>$RAW_SHOWS

# Translate tconst and nconst into titles and names
perl -pi -f $TCONST_SHOWS_PL $RAW_SHOWS
perl -pi -f $TCONST_SHOWS_PL $UNSORTED_CREDITS
perl -pi -f $TCONST_EPISODES_PL $UNSORTED_CREDITS
perl -pi -f $TCONST_EPISODE_NAMES_PL $UNSORTED_CREDITS
perl -pi -f $NCONST_PL $UNSORTED_CREDITS
perl -pi -f $TCONST_KNOWN_PL $KNOWN_PERSONS
perl -pi -f $NCONST_PL $KNOWN_PERSONS

# Create UNIQUE_PERSONS
cut -f 2 $RAW_PERSONS | sort -fu >$UNIQUE_PERSONS

# Create the SHOWS spreadsheet by removing duplicate field from RAW_SHOWS
printf "Show Title\tShow Type\tShow or Episode Title\tSn_#\tEp_#\tStart\tEnd\tMinutes\tGenres\n" >$SHOWS
# Sort by Show Title (1), Show Type (2r), Sn_# (4n), Ep_# (5n), Start (6)
perl -F"\t" -lane 'printf "%s\t%s\t'\''%s\t%s\t%s\t%s\t%s\t%s\t%s\n", @F[0,3,5,1,2,6,7,8,9]' $RAW_SHOWS |
    sort -f --field-separator="$TAB" --key=1,1 --key=2,2r --key=4,4n --key=5,5n --key=6,6 >>$SHOWS

# Create the sorted CREDITS spreadsheets
printf "Person\tShow Title\tEpisode Title\tRank\tJob\tCharacter Name\n" | tee $CREDITS_SHOW >$CREDITS_PERSON
# Sort by Person (1), Show Title (2), Rank (4), Episode Title (3)
sort -f --field-separator="$TAB" --key=1,2 --key=4,4 --key=3,3 $UNSORTED_CREDITS >>$CREDITS_PERSON
# Sort by Show Title (2), Episode Title (3), Rank (4)
sort -f --field-separator="$TAB" --key=2,4 $UNSORTED_CREDITS >>$CREDITS_SHOW

# Save file for later searching
[ -n "$OUTPUT_FILE" ] && cp -p $CREDITS_PERSON "$OUTPUT_FILE"

[ -n "$DEBUG" ] && set -

# Shortcut for printing file info (before adding totals)
function printAdjustedFileInfo() {
    # Print filename, size, date, number of lines
    # Subtract lines to account for headers or trailers, 0 for no adjustment
    #   INVOCATION: printAdjustedFileInfo filename adjustment
    numlines=$(($(sed -n '$=' $1) - $2))
    ls -loh $1 | perl -lane 'printf "%-45s%6s%6s %s %s ",@F[7,3,4,5,6];'
    printf "%8d lines\n" "$numlines"
}

# Output some stats from $SHOWS
if [ -s $QUIET ]; then
    printf "==> Show types in $SHOWS:\n"
    cut -f 4 $RAW_SHOWS | sort | uniq -c | sort -nr | perl -p -e 's+^+\t+'

    # Output some stats from credits
    printf "\n==> Stats from processing $CREDITS_PERSON:\n"
    numPersons=$(sed -n '$=' $UNIQUE_PERSONS)
    printf "%8d people credited -- some in more than one job function\n" "$numPersons"
    for i in actor actress writer director; do
        count=$(cut -f 1,5 $UNSORTED_CREDITS | sort -fu | rg -cw "$i$")
        printf "%13d as %s\n" "$count" "$i"
    done

    # Output some stats, adjust by 1 if header line is included.
    printf "\n==> Stats from processing IMDb data:\n"
    printAdjustedFileInfo $UNIQUE_TITLES 0
    printAdjustedFileInfo $LINKS_TO_TITLES 1
    # printAdjustedFileInfo $TCONST_LIST 0
    # printAdjustedFileInfo $RAW_SHOWS 0
    printAdjustedFileInfo $SHOWS 1
    # printAdjustedFileInfo $NCONST_LIST 0
    printAdjustedFileInfo $UNIQUE_PERSONS 0
    printAdjustedFileInfo $LINKS_TO_PERSONS 1
    # printAdjustedFileInfo $RAW_PERSONS 0
    printAdjustedFileInfo $KNOWN_PERSONS 1
    printAdjustedFileInfo $ASSOCIATED_TITLES 1
    printAdjustedFileInfo $CREDITS_SHOW 1
    printAdjustedFileInfo $CREDITS_PERSON 1
# printAdjustedFileInfo $KNOWNFOR_LIST 0
fi

# Skip diff output if requested
[ -z "$CREATE_DIFF" ] && saveDuration $SECONDS

# Shortcut for checking differences between two files.
# checkdiffs basefile newfile
function checkdiffs() {
    printf "\n"
    if [ ! -e "$1" ]; then
        # If the basefile file doesn't yet exist, assume no differences
        # and copy the newfile to the basefile so it can serve
        # as a base for diffs in the future.
        printf "==> $1 does not exist. Creating it, assuming no diffs.\n"
        cp -p "$2" "$1"
    else
        printf "==> what changed between $1 and $2:\n"
        # first the stats
        diff -c "$1" "$2" | diffstat -sq \
            -D $(cd $(dirname "$2") && pwd -P) |
            sed -e "s+ 1 file changed,+==>+" -e "s+([+-=\!])++g"
        # then the diffs
        diff \
            --unchanged-group-format='' \
            --old-group-format='==> deleted %dn line%(n=1?:s) at line %df <==
%<' \
            --new-group-format='==> added %dN line%(N=1?:s) after line %de <==
%>' \
            --changed-group-format='==> changed %dn line%(n=1?:s) at line %df <==
%<------ to:
%>' "$1" "$2"
        if [ $? == 0 ]; then
            printf "==> no diffs found.\n"
        fi
    fi
}

# Preserve any possible errors for debugging
cat >>$POSSIBLE_DIFFS <<EOF
==> ${0##*/} completed: $(date)

### Check the diffs to see if any changes are meaningful
$(checkdiffs $PUBLISHED_SKIP_EPISODES $SKIP_EPISODES)
$(checkdiffs $PUBLISHED_TCONST_LIST $TCONST_LIST)
$(checkdiffs $PUBLISHED_EPISODES_LIST $EPISODES_LIST)
$(checkdiffs $PUBLISHED_KNOWNFOR_LIST $KNOWNFOR_LIST)
$(checkdiffs $PUBLISHED_NCONST_LIST $NCONST_LIST)
$(checkdiffs $PUBLISHED_UNIQUE_TITLES $UNIQUE_TITLES)
$(checkdiffs $PUBLISHED_UNIQUE_PERSONS $UNIQUE_PERSONS)
$(checkdiffs $PUBLISHED_RAW_PERSONS $RAW_PERSONS)
$(checkdiffs $PUBLISHED_RAW_SHOWS $RAW_SHOWS)
$(checkdiffs $PUBLISHED_SHOWS $SHOWS)
$(checkdiffs $PUBLISHED_KNOWN_PERSONS $KNOWN_PERSONS)
$(checkdiffs $PUBLISHED_CREDITS_SHOW $CREDITS_SHOW)
$(checkdiffs $PUBLISHED_CREDITS_PERSON $CREDITS_PERSON)
$(checkdiffs $PUBLISHED_ASSOCIATED_TITLES $ASSOCIATED_TITLES)

### Any funny stuff with file lengths?

$(wc $ALL_WORKING $ALL_TXT $ALL_CSV $ALL_SPREADSHEETS)

EOF

saveDuration $SECONDS
