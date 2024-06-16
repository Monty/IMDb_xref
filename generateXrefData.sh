#!/usr/bin/env bash
#
# Generate show and cast spreadsheets from:
#   1) .tconst file(s) containing a list of IMDb tconst identifiers
#
#       See https://www.imdb.com/interfaces/ for a description of IMDb datasets
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
#    2) .xlate file(s) with tab separated pairs of non-English titles and their
#    English equivalents
#
#       For example:
#           Brandvägg	Wallander: The Original Episodes
#           Capitaine Marleau	Captain Marleau
#           Den fördömde	Sebastian Bergman
#           ...
#
#       Defaults to all .xlate files, or specify one with -x [file] on the
#       command line
#
#   Set DEBUG environment variable to enable 'breakpoint' function, save
#   secondary files
#
# shellcheck disable=SC2317     # Command appears to be unreachable

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

# Keep track of elapsed time
SECONDS=0

function help() {
    cat <<EOF
generateXrefData.sh -- Create lists/spreadsheets of shows, actors, and characters they portray.

This uses downloaded IMDb .gz files. See https://www.imdb.com/interfaces for details
of the data they contain.

USAGE:
    ./generateXrefData.sh [-x translation file] [tconst file ...]

OPTIONS:
    -h      Print this message.
    -a      All jobs -- not just actor, actress, writer, director, producer
    -d      Directory -- Create a subdirectory for results. Don't overwrite existing files.
    -f      File -- Save file that can later be used for queries with "xrefCast.sh -f"
    -x      Xlate -- Use a specific translation file instead of *xlate.
    -q      Quiet -- Minimize output, print only the list of shows being processed.
    -r      Reload -- Force all data to be reloaded, even if not necessary.
    -t      Test mode -- Use tconst.example, xlate.example; diff against test_results.

EXAMPLES:
    ./generateXrefData.sh
    ./generateXrefData.sh -x Contrib/Others.xlate Contrib/OPB.tconst
    ./generateXrefData.sh -d Comedies
    ./generateXrefData.sh -arq
    ./generateXrefData.sh -t

EOF
}

# Don't leave tempfiles around
trap terminate EXIT
#
function terminate() {
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: %s\n" "$(basename "$0")" >&2
        printf "Not removing:\n" >&2
        cat <<EOT >&2
ALL_TEMPS ${ALL_TEMPS[@]}
ALL_WORK ${ALL_WORK[@]}
ALL_CSV ${ALL_CSV[@]}
TCONST_LIST $TCONST_LIST
EVERY_TCONST $EVERY_TCONST
CACHE $CACHE
EOT
    else
        rm -f "${ALL_TEMPS[@]}" "${ALL_WORK[@]}" "${ALL_CSV[@]}"
        rm -f "$TCONST_LIST" "$EVERY_TCONST"
        rm -rf "$CACHE"
    fi
}

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

function processDurations() {
    # If we're not in the primary directory, don't record times
    [[ -n $OUTPUT_DIR ]] || [[ -n $BYPASS_PROCESSING ]] && exit
    saveDurations "$SECONDS"
    # Only keep 10 duration lines for this script
    trimDurations -m 10
    # Save the contents of every tconst to use for manual comparison next time
    [[ -n $useEveryTconst ]] && saveHistory "$EVERY_TCONST"
    # Keep 20 history files for this script
    trimHistory -m 20
    exit
}

function breakpoint() {
    if [[ -n $DEBUG ]]; then
        if waitUntil "$YN_PREF" -N "Quit now?"; then
            printf "Quitting ...\n"
            exit 1
        fi
    fi
}

while getopts ":d:f:x:hraqt" opt; do
    case $opt in
    a)
        ALL_JOBS="^"
        ;;
    h)
        help
        exit
        ;;
    r)
        RELOAD="yes"
        ;;
    d)
        OUTPUT_DIR="./$OPTARG/"
        ;;
    f)
        OUTPUT_FILE="$OPTARG"
        ;;
    q)
        QUIET="yes"
        ;;
    t)
        TEST_MODE="yes"
        CREATE_DIFF="yes"
        ;;
    x)
        XLATE_FILES=("$OPTARG")
        ;;
    \?)
        printf "==> Ignoring invalid option: -%s\n\n" "$OPTARG" >&2
        ;;
    :)
        printf "==> Option -%s requires an argument'.\n\n" "$OPTARG" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

# Make sure prerequisites are satisfied
ensurePrerequisites

# Create some timestamps - only use DATE_ID if we're debugging
[[ -n $DEBUG ]] && DATE_ID="-$(date +%y%m%d)"
LONGDATE="-$(date +%y%m%d.%H%M%S)"

# Required subdirectories
WORK="secondary"
CACHE="${WORK}/cache"
BASE="test_results"
[[ -n $OUTPUT_DIR ]] && mkdir -p "$OUTPUT_DIR"
mkdir -p "$WORK" "$BASE" "$CACHE"

# Error and debugging info (per run)
POSSIBLE_DIFFS="diffs$LONGDATE.txt"
[[ -n $CREATE_DIFF ]] &&
    printf "\n==> %s contains diffs between generated files and files saved in %s\n" \
        "$POSSIBLE_DIFFS" "$BASE"

# Error and debugging info (per run)
ERRORS="${OUTPUT_DIR}generate_anomalies$LONGDATE.txt"

# Final output spreadsheets
ASSOCIATED_TITLES="${OUTPUT_DIR}AssociatedTitles$DATE_ID.csv"
CREDITS_PERSON="${OUTPUT_DIR}Credits-Person$DATE_ID.csv"
CREDITS_SHOW="${OUTPUT_DIR}Credits-Show$DATE_ID.csv"
EPISODE_COUNT="${OUTPUT_DIR}Episode-Count$DATE_ID.csv"
KNOWN_PERSONS="${OUTPUT_DIR}Persons-KnownFor$DATE_ID.csv"
LINKS_TO_PERSONS="${OUTPUT_DIR}LinksToPersons$DATE_ID.csv"
LINKS_TO_TITLES="${OUTPUT_DIR}LinksToTitles$DATE_ID.csv"
SHOWS="${OUTPUT_DIR}Shows-Episodes$DATE_ID.csv"

# Final output lists
UNIQUE_CHARS="${OUTPUT_DIR}uniqCharacters$DATE_ID.txt"
UNIQUE_PERSONS="${OUTPUT_DIR}uniqPersons$DATE_ID.txt"
UNIQUE_TITLES="${OUTPUT_DIR}uniqTitles$DATE_ID.txt"

# Intermediate working temps
TEMPFILE="$WORK/tempfile$DATE_ID.txt"
TEMP_AWK="$WORK/conflicts$DATE_ID.awk"
TEMP_DUPES="$WORK/dupes$DATE_ID.txt"
TEMP_SKIPS="$WORK/tconst-skip$DATE_ID.txt"
# Intermediate working txt
EPISODES_LIST="$WORK/tconst-episodes$DATE_ID.txt"
KNOWNFOR_LIST="$WORK/tconst_known$DATE_ID.txt"
NCONST_LIST="$WORK/nconst$DATE_ID.txt"
HIST_TCONST="$WORK/hist_tconst$DATE_ID.txt"
# Intermediate working csv
RAW_EPISODES="$WORK/raw_episodes$DATE_ID.csv"
RAW_PERSONS="$WORK/raw_persons$DATE_ID.csv"
RAW_SHOWS="$WORK/raw_shows$DATE_ID.csv"
UNSORTED_CREDITS="$WORK/unsorted_credits$DATE_ID.csv"
UNSORTED_EPISODES="$WORK/unsorted_episodes$DATE_ID.csv"
# Intermediate working perl
NCONST_PL="$WORK/nconst-pl$DATE_ID.txt"
TCONST_EPISODES_PL="$WORK/tconst-episodes-pl$DATE_ID.txt"
TCONST_EPISODE_NAMES_PL="$WORK/tconst-episode_names-pl$DATE_ID.txt"
TCONST_KNOWN_PL="$WORK/tconst-known-pl$DATE_ID.txt"
TCONST_SHOWS_PL="$WORK/tconst-shows-pl$DATE_ID.txt"
XLATE_PL="$WORK/xlate-pl$DATE_ID.txt"
# Special files that shouldn't be removed before processing
TCONST_LIST="$WORK/tconst$DATE_ID.txt"
EVERY_TCONST="$WORK/every_tconst$DATE_ID.txt"

# Manually entered list of tconst ID's that we don't want tvEpisodes for
# either because they have too many episodes, or episodes don't translate well
SKIP_EPISODES="skipEpisodes.example"

# Saved files used for comparison with current files
PUBLISHED_ASSOCIATED_TITLES="$BASE/AssociatedTitles.csv"
PUBLISHED_CREDITS_PERSON="$BASE/Credits-Person.csv"
PUBLISHED_CREDITS_SHOW="$BASE/Credits-Show.csv"
PUBLISHED_KNOWN_PERSONS="$BASE/Persons-KnownFor.csv"
PUBLISHED_SHOWS="$BASE/Shows.csv"
PUBLISHED_SKIP_EPISODES="$BASE/skipEpisodes.example"
#
PUBLISHED_UNIQUE_CHARS="$BASE/uniqCharacters.txt"
PUBLISHED_UNIQUE_PERSONS="$BASE/uniqPersons.txt"
PUBLISHED_UNIQUE_TITLES="$BASE/uniqTitles.txt"
#
PUBLISHED_EPISODES_LIST="$BASE/tconst-episodes.csv"
PUBLISHED_EPISODE_COUNT="$BASE/episode-count.csv"
PUBLISHED_KNOWNFOR_LIST="$BASE/tconst_known.txt"
PUBLISHED_NCONST_LIST="$BASE/nconst.txt"
PUBLISHED_RAW_PERSONS="$BASE/raw_persons.csv"
PUBLISHED_RAW_SHOWS="$BASE/raw_shows.csv"
PUBLISHED_TCONST_LIST="$BASE/tconst.txt"

# Filename groups used for cleanup
# Intermediate working temps
ALL_TEMPS=("$TEMPFILE" "$TEMP_AWK" "$TEMP_DUPES" "$TEMP_SKIPS")
#
# Intermediate working csv
ALL_CSV=("$RAW_EPISODES" "$RAW_PERSONS" "$RAW_SHOWS")
ALL_CSV+=("$UNSORTED_CREDITS" "$UNSORTED_EPISODES")
#
# Intermediate working txt
ALL_WORK=("$EPISODES_LIST" "$KNOWNFOR_LIST" "$NCONST_LIST" "$HIST_TCONST")
# Intermediate working perl
ALL_WORK+=("$NCONST_PL" "$TCONST_EPISODES_PL" "$TCONST_EPISODE_NAMES_PL")
ALL_WORK+=("$TCONST_KNOWN_PL" "$TCONST_SHOWS_PL" "$XLATE_PL")
#
# Final output lists
ALL_TXT=("$UNIQUE_CHARS" "$UNIQUE_PERSONS" "$UNIQUE_TITLES")
#
# Final output spreadsheets
ALL_SHEETS=("$ASSOCIATED_TITLES" "$CREDITS_PERSON" "$CREDITS_SHOW")
ALL_SHEETS+=("$KNOWN_PERSONS" "$LINKS_TO_PERSONS" "$LINKS_TO_TITLES" "$SHOWS")

# If we ALWAYS want QUIET
[[ -n "$(rg -c "QUIET=yes" "$configFile")" ]] && QUIET="yes"

# All jobs or just the most important ones?
[[ -z $ALL_JOBS ]] && ALL_JOBS="\b(actor|actress|writer|director|producer)\b"

# If the user hasn't created a .tconst or .xlate file, create a small example
# from a PBS show. This is relatively harmless, and keeps this script simpler.

if [[ -z "$(ls -- *.xlate 2>/dev/null)" ]]; then
    [[ -z $QUIET ]] &&
        printf "==> Creating an example translation file: PBS.xlate\n\n"
    rg -N -e "^#|^$" -e "The Durrells" xlate.example >"PBS.xlate"
fi
if [[ -z "$(ls -- *.tconst 2>/dev/null)" ]]; then
    [[ -z $QUIET ]] &&
        printf "==> Creating an example tconst file: PBS.tconst\n\n"
    rg -N -e "^#|^$" -e "The Durrells" -e "The Night Manager" \
        -e "The Crown" tconst.example >"PBS.tconst"
fi

if [[ -n $TEST_MODE ]]; then
    XLATE_FILES=("xlate.example")
    TCONST_FILES=("tconst.example")
    printf "==> Using xlate.example files for IMDb title translation.\n\n"
    printf "==> Searching tconst.example for IMDb title identifiers.\n"
else
    # Pick xlate file(s) to process if not specified with -x option
    if [[ -z ${XLATE_FILES[*]} ]]; then
        XLATE_FILES=(*.xlate)
        [[ -z $QUIET ]] &&
            printf "==> Using all .xlate files for IMDb title translation.\n\n"
    else
        [[ -z $QUIET ]] &&
            printf "==> Using %s for IMDb title translation.\n\n" "${XLATE_FILES[@]}"
    fi
    if [[ -z "$(ls "${XLATE_FILES[@]}" 2>/dev/null)" ]]; then
        printf "==> [${RED}Error${NO_COLOR}] No such file: %s\n" "${XLATE_FILES[@]}" >&2
        exit 1
    fi

    # Pick tconst file(s) to process
    if [[ $# -eq 0 ]]; then
        TCONST_FILES=(*.tconst)
        [[ -z $QUIET ]] &&
            printf "==> Searching all .tconst files for IMDb title identifiers.\n"
        # Cache is only enabled if *.tconst is used, which is the usual mode.
        useEveryTconst="yes"
        # The history file should contain the contents of every tconst file used
        head -9999 -- *tconst | rg -v "^$|#" >"$EVERY_TCONST"
    else
        for file in "$@"; do
            if [[ ! -e $file ]]; then
                printf "==> [${RED}Error${NO_COLOR}] No such file: %s\n" "$file" >&2
                exit 1
            fi
            TCONST_FILES+=("$file")
        done
        [[ -z $QUIET ]] &&
            printf "==> Searching %s for IMDb title identifiers.\n" "${TCONST_FILES[*]}"
    fi
fi

# Coalesce a single tconst input list
rg -IN "^tt" "${TCONST_FILES[@]}" | cut -f 1 | sort -u >"$TCONST_LIST"

if [[ -z $RELOAD ]] && [[ -n $useEveryTconst ]]; then
    # Figure out whether we can use previous run as a cache.
    # Must force reload everything if:
    # 1) Missing any gzip or previous generateXrefData files
    #    All gzip files should be here as they are loaded by ensurePrerequisites
    # 2) Any gzip file is newer than any generateXrefData file

    # 1) Missing any gzip or previous generateXrefData files?
    numRequired="$((${#ALL_TXT[@]} + ${#ALL_SHEETS[@]} + ${#gzFiles[@]}))"
    numAvailable="$(ls -1 "${ALL_TXT[@]}" "${ALL_SHEETS[@]}" "${gzFiles[@]}" \
        2>/dev/null | sed -n '$=')"
    # [ "$numRequired" -ne "$numAvailable" ] && printf "Files missing.\n"
    [[ $numRequired -ne $numAvailable ]] && RELOAD="yes"

    # 2) Is any gzip file newer than any generateXrefData file?
    lastWritten="$(find "${ALL_TXT[@]}" "${ALL_SHEETS[@]}" "${gzFiles[@]}" \
        2>/dev/null | tail -1)"
    # [[ "$lastWritten" =~ .*tsv\.gz ]] && printf "Last written is a tsv.gz.\n"
    [[ $lastWritten =~ .*tsv\.gz ]] && RELOAD="yes"

    if [[ -z $RELOAD ]]; then
        # Get tconst IDs from previous run
        printHistory | rg -IN "^tt" | cut -f 1 | sort -u >"$HIST_TCONST"
        #
        if [[ -z "$(comm -13 "$HIST_TCONST" "$TCONST_LIST")" ]]; then
            # Nothing new. No processing required. Very fast...
            BYPASS_PROCESSING="yes"
            printf "\n==> No changes, no new files generated. Use -r to "
            printf "force reload all shows.\n\n"
        else
            # Some new shows. Minimal processing required. Use merge strategy.
            numNew="$(comm -13 "$HIST_TCONST" "$TCONST_LIST" | tee "$TEMPFILE" |
                sed -n '$=')"
            [[ $numNew -gt 1 ]] && plural="s"
            printf "\n==> Adding $numNew new show$plural. Use -r to "
            printf "force reload all shows.\n\n"
            mergeFilesP="yes"
            mv "$TEMPFILE" "$TCONST_LIST"
            mv "${ALL_TXT[@]}" "${ALL_SHEETS[@]}" "$CACHE"
        fi
    fi
fi

if [[ -z $BYPASS_PROCESSING ]]; then
    # Cleanup any possible leftover files
    rm -f "${ALL_TEMPS[@]}" "${ALL_WORK[@]}" "${ALL_TXT[@]}" "${ALL_CSV[@]}" "${ALL_SHEETS[@]}"

    # Create a perl "substitute" script to translate any known non-English titles to
    # their English equivalent. Regex delimiter needs to avoid any characters
    # present in the input, use {} for readability
    rg -INv "^#|^$" "${XLATE_FILES[@]}" | cut -f 1,2 | sort -fu |
        perl -p -e 's+\t+\\t}\{\\t+; s+^+s{\\t+; s+$+\\t};+' >"$XLATE_PL"

    # Check for translation conflicts
    rg -INv "^#|^$" "${XLATE_FILES[@]}" | sort -fu | cut -f 1 | sort -f | uniq -d >"$TEMP_DUPES"
    ### Stop here if there are translation conflicts.
    if [[ -s $TEMP_DUPES ]]; then
        # shellcheck disable=SC2059      # variables in printf OK here
        printf "[${RED}Error${NO_COLOR}] Translation conflicts for show titles are listed below. "
        cat "$TEMP_DUPES"
        printf "\n==> These files have different translations for the same show title.\n"
        printf "    Please ensure all translations for a title are the same, then re-run this script\n"
        rg -p -f "$TEMP_DUPES" "${XLATE_FILES[@]}" | rg -v ":#"
        exit 1
    fi

    # Generate a csv of titles from the tconst list, remove the "adult" field,
    # translate any known non-English titles to their English equivalent,
    rg -wNz -f "$TCONST_LIST" title.basics.tsv.gz | cut -f 1-4,6-9 |
        perl -p -f "$XLATE_PL" | perl -p -e 's+\t+\t\t\t+;' >"$RAW_SHOWS"

    ### Check for and repair duplicate titles
    cut -f 5 "$RAW_SHOWS" | sort -f | uniq -d >"$TEMP_DUPES"
    if [[ -s $TEMP_DUPES ]]; then
        # Create an awk script to add dates to titles on shows with title conflicts
        printf 'BEGIN {OFS = "\\t"}\n' >"$TEMP_AWK"
        perl -p -e 's+^+\$5 == "+; s+$+" {\$5 = \$5 " (" \$7 ")"}+;' "$TEMP_DUPES" \
            >>"$TEMP_AWK"
        printf '{print}\n' >>"$TEMP_AWK"
        # Let the user know what we will change
        printf "\n==> Adding dates to titles to fix these title conflicts.\n" >&2
        perl -pi -e 's+^+\\t+; s+$+\\t+;' "$TEMP_DUPES"
        rg -N -f "$TEMP_DUPES" "$RAW_SHOWS" | cut -f 1,4-7 |
            sort -f -t$'\t' --key=3 >"$TEMPFILE"
        tsvPrint "$TEMPFILE" >&2
        # Change the shows by adding (<DATE>) to title
        cp "$RAW_SHOWS" "$TEMPFILE"
        awk -F "\t" -f "$TEMP_AWK" "$TEMPFILE" >"$RAW_SHOWS"
    fi

    # We don't want to check for episodes in any tvSeries that has hundreds of
    # tvEpisodes or has episodes with titles that aren't unique like "Episode 1"
    # that can't be "translated" back to the original show. Manually maintain a skip
    # list in $SKIP_EPISODES.
    rg -v -e "^#" -e "^$" "$SKIP_EPISODES" | cut -f 1 >"$TEMP_SKIPS"

    # We should now be conflict free
    cut -f 5 "$RAW_SHOWS" | sort -fu >"$UNIQUE_TITLES"
    num_titles=$(sed -n '$=' "$UNIQUE_TITLES")

    # Generate a list of tconst files used, separated by commas.
    tc_list="$(printf "${TCONST_FILES[*]}" | sed 's+ +, +g')"
    #
    # Let us know shows we're processing. Format for readability, separate with ";"
    printf "\n==> Processing %s shows found in %s:\n\n" "$num_titles" "$tc_list" |
        fmt -w 80
    perl -p -e 's+$+;+' "$UNIQUE_TITLES" | fmt -w 80 | perl -p -e 's+^+\t+' |
        sed '$ s+.$++'
    [[ -n $OUTPUT_DIR ]] && printf "\n"

    # Let us know how long it took last time, unless we're not in the primary directory
    [[ -z $OUTPUT_DIR ]] && printDuration

    # Use the tconst list to lookup episode IDs and generate an episode tconst file
    rg -wNz -f "$TCONST_LIST" title.episode.tsv.gz | perl -p -e 's+\\N++g;' |
        sort -f -t$'\t' --key=2,2 --key=3,3n --key=4,4n |
        rg -wv -f "$TEMP_SKIPS" | tee "$UNSORTED_EPISODES" | cut -f 1 >"$EPISODES_LIST"

    # Use the episodes list to generate raw episodes
    rg -wNz -f "$EPISODES_LIST" title.basics.tsv.gz | cut -f 1-4,6-9 |
        perl -p -e 's+\\N++g;' |
        sort -f -t$'\t' --key=3,3 --key=5,5 --key=4,4 >"$RAW_EPISODES"

    # Use tconst list to lookup principal titles & generate tconst/nconst credits csv
    # Fix bogus nconst nm0745728, it should be nm0745694. Rearrange fields
    rg -wNz -f "$TCONST_LIST" title.principals.tsv.gz |
        sort --key=1,1 --key=2,2n | perl -p -e 's+nm0745728+nm0745694+' |
        perl -p -e 's+\\N++g;' |
        perl -F"\t" -lane 'printf "%s\t%s\t\t%02d\t%s\t%s\t%s\t%s\n", @F[2,0,1,3,5,2,0]' |
        rg "$ALL_JOBS" | tee "$UNSORTED_CREDITS" | cut -f 1 |
        sort -u | tee "$TEMPFILE" >"$NCONST_LIST"

    # Use episodes list to lookup principal titles & add to tconst/nconst credits csv
    rg -wNz -f "$EPISODES_LIST" title.principals.tsv.gz |
        sort --key=1,1 --key=2,2n | perl -p -e 's+\\N++g;' |
        perl -F"\t" -lane 'printf "%s\t%s\t%s\t%02d\t%s\t%s\t%s\t%s\n", @F[2,0,0,1,3,5,2,0]' |
        rg "$ALL_JOBS" |
        tee -a "$UNSORTED_CREDITS" | cut -f 1 | sort -u |
        rg -v -f "$TEMPFILE" >>"$NCONST_LIST"

    # Create a perl script to globally convert a show tconst to a show title
    cut -f 1,5 "$RAW_SHOWS" |
        perl -F"\t" -lane 'print "s{\\b@F[0]\\b}\{'\''@F[1]};";' >"$TCONST_SHOWS_PL"

    # Create a perl script to convert an episode tconst to its parent show title
    perl -F"\t" -lane 'print "s{\\b@F[0]\\b}\{@F[1]\\t@F[2]\\t@F[3]};";' "$UNSORTED_EPISODES" |
        perl -p -f "$TCONST_SHOWS_PL" >"$TCONST_EPISODES_PL"

    # Create a perl script to convert an episode tconst to its episode title
    perl -F"\t" -lane 'print "s{\\b@F[0]\\b}\{'\''@F[2]};";' "$RAW_EPISODES" \
        >"$TCONST_EPISODE_NAMES_PL"

    # Convert raw episodes to raw shows
    perl -pi -f "$TCONST_EPISODES_PL" "$RAW_EPISODES"

    # Remove extra tab fields from $TCONST_EPISODES_PL
    perl -pi -e 's/\\t.*}/}/' "$TCONST_EPISODES_PL"

    # Create a perl script to convert an nconst to a name
    rg -wNz -f "$NCONST_LIST" name.basics.tsv.gz | perl -p -e 's+\\N++g;' |
        cut -f 1-2,6 | sort -fu --key=2 | tee "$RAW_PERSONS" |
        perl -F"\t" -lane 'print "s{^@F[0]\\b}\{@F[1]};";' >"$NCONST_PL"

    # Get rid of ugly \N fields, and unneeded characters. Make sure commas are
    # followed by spaces. Separate multiple characters portrayed with semicolons,
    # remove quotes
    perl -pi -e 's+\\N++g; tr+[]++d; s+,+, +g; s+,  +, +g; s+", "+; +g; tr+"++d;' "${ALL_CSV[@]}"

    # Create the KNOWN_PERSONS spreadsheet, ensure always 5 fields
    printf "Person\tKnown For Titles: 1\tKnown For Titles: 2\tKnown For Titles: 3\tKnown For Titles: 4\n" \
        >"$KNOWN_PERSONS"
    cut -f 1,3 "$RAW_PERSONS" | perl -p -e 's+, +\t+g' |
        perl -F"\t" -lane 'printf "%s\t%s\t%s\t%s\t%s\n", @F[0,1,2,3,4]' \
            >>"$KNOWN_PERSONS"

    # Create the LINKS_TO_PERSONS spreadsheet
    printf "nconst\tName\tHyperlink to Name\n" >"$LINKS_TO_PERSONS"
    cut -f 1,2 "$RAW_PERSONS" | perl -F"\t" -lane \
        'print "@F[0]\t@F[1]\t=HYPERLINK(\"https://www.imdb.com/name/@F[0]\";\"@F[1]\")";' |
        sort -fu -t$'\t' --key=2,2 >>"$LINKS_TO_PERSONS"

    # Create a tconst list of the knownForTitles
    cut -f 3 "$RAW_PERSONS" | rg "^tt" | perl -p -e 's+, +\n+g' |
        sort -u >"$KNOWNFOR_LIST"

    # Create a perl script to globally convert a known show tconst to a show title
    rg -wNz -f "$KNOWNFOR_LIST" title.basics.tsv.gz | perl -p -f "$XLATE_PL" |
        cut -f 1,3 |
        perl -F"\t" -lane 'print "s{\\b@F[0]\\b}\{'\''@F[1]}g;";' >"$TCONST_KNOWN_PL"

    # Create the LINKS_TO_TITLES spreadsheet
    printf "tconst\tShow Title\tHyperlink to Title\n" >"$LINKS_TO_TITLES"
    perl -p -e 's+^.*btt+tt+; s+\\b}\{+\t+; s+}.*++;' "$TCONST_SHOWS_PL" | perl -F"\t" -lane \
        'print "@F[0]\t@F[1]\t=HYPERLINK(\"https://www.imdb.com/title/@F[0]\";\"" . substr(@F[1],1) . "\")";' |
        sort -fu -t$'\t' --key=2,2 >>"$LINKS_TO_TITLES"

    # Create a spreadsheet of associated titles gained from IMDb knownFor data
    printf "tconst\tShow Title\tHyperlink to Title\n" >"$ASSOCIATED_TITLES"
    perl -p -e 's+^.*btt+tt+; s+\\b}\{+\t+; s+}.*++;' "$TCONST_KNOWN_PL" |
        perl -F"\t" -lane \
            'print "@F[0]\t@F[1]\t=HYPERLINK(\"https://www.imdb.com/title/@F[0]\";\"" . substr(@F[1],1) . "\")";' |
        sort -fu -t$'\t' --key=2,2 | rg -wv -f "$TCONST_LIST" \
        >>"$ASSOCIATED_TITLES"

    # Add episodes into raw shows
    perl -p -f "$TCONST_EPISODES_PL" "$RAW_EPISODES" >>"$RAW_SHOWS"

    # Fix perl errors for shows ending in '$' -- 'Arli$$' 'Biz Kid$'
    perl -pi -e 's/Arli\$/Arli\\\$/g;' -e 's/\$\}/\\\$}/g;' "$TCONST_KNOWN_PL"

    # Translate tconst and nconst into titles and names
    perl -pi -f "$TCONST_SHOWS_PL" "$RAW_SHOWS"
    perl -pi -f "$TCONST_SHOWS_PL" "$UNSORTED_CREDITS"
    perl -pi -f "$TCONST_EPISODES_PL" "$UNSORTED_CREDITS"
    perl -pi -f "$TCONST_EPISODE_NAMES_PL" "$UNSORTED_CREDITS"
    perl -pi -f "$NCONST_PL" "$UNSORTED_CREDITS"
    perl -pi -f "$TCONST_KNOWN_PL" "$KNOWN_PERSONS"
    perl -pi -f "$NCONST_PL" "$KNOWN_PERSONS"

    # Create UNIQUE_PERSONS
    cut -f 2 "$RAW_PERSONS" | sort -fu >"$UNIQUE_PERSONS"

    # Create UNIQUE_CHARS
    cut -f 6 "$UNSORTED_CREDITS" | sort -fu | rg -v "^$" | perl -p -e 's+; +\n+g;' |
        sort -fu >"$UNIQUE_CHARS"

    # Create the SHOWS spreadsheet by removing duplicate field from RAW_SHOWS
    printf "Show Title\tShow Type\tShow or Episode Title\tSn_#\tEp_#\tStart\tEnd\tMinutes\tGenres\n" >"$SHOWS"
    # Sort by Show Title (1), Show Type (2r), Sn_# (4n), Ep_# (5n), Start (6)
    perl -F"\t" -lane 'printf "%s\t%s\t'\''%s\t%s\t%s\t%s\t%s\t%s\t%s\n", @F[0,3,5,1,2,6,7,8,9]' "$RAW_SHOWS" |
        sort -f -t$'\t' --key=1,1 --key=2,2r --key=4,4n --key=5,5n \
            --key=6,6 >>"$SHOWS"

    # Create the EPISODE_COUNT spreadsheet
    printf "Count\tTitle\n" >"$EPISODE_COUNT"
    rg "^'" "$SHOWS" | cut -f 1 | uniq -c | sort -nr |
        perl -p -e "s/ '/  \t'/" >>"$EPISODE_COUNT"

    # Create the sorted CREDITS spreadsheets
    printf "Person\tShow Title\tEpisode Title\tRank\tJob\tCharacter Name\tnconst ID\ttconst ID\n" |
        tee "$CREDITS_SHOW" >"$CREDITS_PERSON"
    # Sort by Person (1), Show Title (2), Rank (4), Episode Title (3)
    sort -f -t$'\t' --key=1,2 --key=4,4 --key=3,3 "$UNSORTED_CREDITS" \
        >>"$CREDITS_PERSON"
    # Sort by Show Title (2), Episode Title (3), Rank (4)
    sort -f -t$'\t' --key=2,4 "$UNSORTED_CREDITS" >>"$CREDITS_SHOW"

# End of BYPASS_PROCESSING
fi

if [[ -n $mergeFilesP ]]; then
    # Merge two files that have a header line. Sort key is 2nd param.
    function mergeSort() {
        file="$1"
        oldFile="$CACHE/$(basename "$file")"
        tail +2 "$file" >"$TEMPFILE"
        tail +2 "$oldFile" >>"$TEMPFILE"
        #
        head -1 "$oldFile" >"$file"
        # shellcheck disable=SC2086      # Need glob/split
        sort -fu "$TEMPFILE" | sort -f -t$'\t' $2 >>"$file"
    }

    # Text files that have no header. Sort doesn't need keys.
    for file in "${ALL_TXT[@]}"; do
        oldFile="$CACHE/$(basename "$file")"
        cat "$file" "$oldFile" | sort -fu >"$TEMPFILE"
        mv "$TEMPFILE" "$file"
    done
    # Files that have header and require sorting
    mergeSort "$LINKS_TO_PERSONS" '-k 2,2'
    mergeSort "$LINKS_TO_TITLES" '-k 2,2'
    mergeSort "$ASSOCIATED_TITLES" '-k 2,2'
    mergeSort "$KNOWN_PERSONS" '-k 1,2'
    mergeSort "$SHOWS" '-k 1,1 -k 2,2r -k 4,4n -k 5,5n -k 6,6'
    mergeSort "$CREDITS_SHOW" '-k 2,4'
    mergeSort "$CREDITS_PERSON" '-k 1,2 -k 4,4 -k 3,3'
fi

# Save file for later searching
[[ -n $OUTPUT_FILE ]] && cp -p "$CREDITS_PERSON" "$OUTPUT_FILE"

# Shortcut for printing file info (before adding totals)
function printAdjustedFileInfo() {
    # Print filename, size, date, number of lines
    # Subtract lines to account for headers or trailers, 0 for no adjustment
    #   INVOCATION: printAdjustedFileInfo filename adjustment
    numlines=$(($(sed -n '$=' "$1") - $2))
    # We're formatting the output string of "ls -loh", not walking the result
    # shellcheck disable=SC2012      # Breaks unless ls -loh is used
    ls -loh "$1" | perl -lane 'printf "%-45s%6s%6s %s %s ",@F[7,3,4,5,6];'
    printf "%8d lines\n" "$numlines"
}

# Check for SHOWS starting with tt
if [[ -n "$(rg -c "^tt" "$SHOWS")" ]]; then
    printf "### Shows in %s with a tconst instead of a name:\n" "$SHOWS" \
        >"$ERRORS"
    rg -N "^tt" "$SHOWS" >>"$ERRORS"
    cat >>"$ERRORS" <<EOF
### Usually caused by an episode tconst without its parent tconst. If you
### only want specific episodes, but not all episodes in a show, add the
### parent tconst to skipEpisodes.example
EOF
    #
    printf "==> [${YELLOW}Warning${NO_COLOR}] Shows in $SHOWS have a tconst for a name:\n"
    printf "    For more details:\n"
    printf "    rg -N '^tt[0-9]*' %s\n\n" "$SHOWS"
fi

# Output some stats from $SHOWS
if [[ -z $QUIET ]]; then
    printf "==> Show types in %s:\n" "$SHOWS"
    rg -v "^Show Title\t" "$SHOWS" | cut -f 2 | frequency

    # Output some stats from credits
    printf "\n==> Stats from processing %s:\n" "$CREDITS_PERSON"
    numPersons=$(sed -n '$=' "$UNIQUE_PERSONS")
    printf "%8d people credited -- some in more than one job function\n" \
        "$numPersons"
    rg -v "^Person\tShow Title\t" "$CREDITS_PERSON" | cut -f 1,5 | sort -fu |
        cut -f 2 | frequency

    # Output some stats, adjust by 1 if header line is included.
    printf "\n==> Stats from processing IMDb data:\n"
    printAdjustedFileInfo "$UNIQUE_TITLES" 0
    printAdjustedFileInfo "$LINKS_TO_TITLES" 1
    # printAdjustedFileInfo $TCONST_LIST 0
    # printAdjustedFileInfo $RAW_SHOWS 0
    printAdjustedFileInfo "$EPISODE_COUNT" 1
    printAdjustedFileInfo "$SHOWS" 1
    # printAdjustedFileInfo $NCONST_LIST 0
    printAdjustedFileInfo "$UNIQUE_CHARS" 0
    printAdjustedFileInfo "$UNIQUE_PERSONS" 0
    printAdjustedFileInfo "$LINKS_TO_PERSONS" 1
    # printAdjustedFileInfo $RAW_PERSONS 0
    printAdjustedFileInfo "$KNOWN_PERSONS" 1
    printAdjustedFileInfo "$ASSOCIATED_TITLES" 1
    printAdjustedFileInfo "$CREDITS_SHOW" 1
    printAdjustedFileInfo "$CREDITS_PERSON" 1
    # printAdjustedFileInfo $KNOWNFOR_LIST 0
fi

# List the ten shows having the most episodes
printf "\n==> Shows with the most episodes from %s:\n" "$SHOWS"
head -11 "$EPISODE_COUNT" | perl -p -e "s/\t'/\t/"

# Skip diff output if requested. Save durations and exit
[[ -z $CREATE_DIFF ]] && processDurations

# Shortcut for checking differences between two files.
# checkdiffs basefile newfile
function checkdiffs() {
    printf "\n"
    if [[ ! -e $2 ]]; then
        printf "==> $2 does not exist. Skipping diff.\n"
        return 1
    fi
    if [[ ! -e $1 ]]; then
        # If the basefile file doesn't yet exist, assume no differences
        # and copy the newfile to the basefile so it can serve
        # as a base for diffs in the future.
        printf "==> $1 does not exist. Creating it, assuming no diffs.\n"
        cp -p "$2" "$1"
    else
        # first the stats
        printf "./whatChanged.sh \"$1\" \"$2\"\n"
        diff -u "$1" "$2" | diffstat -sq \
            -D "$(cd "$(dirname "$2")" && pwd -P)" |
            sed -e "s/ 1 file changed,/==>/" -e "s/([+-=\!])//g"
        # then the diffs
        if cmp --quiet "$1" "$2"; then
            printf "==> no diffs found.\n"
        else
            diff -U 0 "$1" "$2" | awk -f formatUnifiedDiffOutput.awk
        fi
    fi
}

# Preserve any possible errors for debugging
cat >>"$POSSIBLE_DIFFS" <<EOF
==> ${0##*/} completed: $(date)

### Check the diffs to see if any changes are meaningful
$(checkdiffs "$PUBLISHED_SKIP_EPISODES" "$SKIP_EPISODES")
$(checkdiffs "$PUBLISHED_TCONST_LIST" "$TCONST_LIST")
$(checkdiffs "$PUBLISHED_EPISODES_LIST" "$EPISODES_LIST")
$(checkdiffs "$PUBLISHED_EPISODE_COUNT" "$EPISODE_COUNT")
$(checkdiffs "$PUBLISHED_KNOWNFOR_LIST" "$KNOWNFOR_LIST")
$(checkdiffs "$PUBLISHED_NCONST_LIST" "$NCONST_LIST")
$(checkdiffs "$PUBLISHED_UNIQUE_TITLES" "$UNIQUE_TITLES")
$(checkdiffs "$PUBLISHED_UNIQUE_CHARS" "$UNIQUE_CHARS")
$(checkdiffs "$PUBLISHED_UNIQUE_PERSONS" "$UNIQUE_PERSONS")
$(checkdiffs "$PUBLISHED_RAW_PERSONS" "$RAW_PERSONS")
$(checkdiffs "$PUBLISHED_RAW_SHOWS" "$RAW_SHOWS")
$(checkdiffs "$PUBLISHED_SHOWS" "$SHOWS")
$(checkdiffs "$PUBLISHED_KNOWN_PERSONS" "$KNOWN_PERSONS")
$(checkdiffs "$PUBLISHED_CREDITS_SHOW" "$CREDITS_SHOW")
$(checkdiffs "$PUBLISHED_CREDITS_PERSON" "$CREDITS_PERSON")
$(checkdiffs "$PUBLISHED_ASSOCIATED_TITLES" "$ASSOCIATED_TITLES")

### Any funny stuff with file lengths?

EOF

touch "$HIST_TCONST" # In case we've not run printHistory
wc "${ALL_WORK[@]}" "${ALL_TXT[@]}" "${ALL_CSV[@]}" "${ALL_SHEETS[@]}" \
    >>"$POSSIBLE_DIFFS"

# Save durations and exit
processDurations
