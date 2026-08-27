#!/usr/bin/env bash
#
# Save a filmography for a named person in IMDb

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
saveFilmography.sh -- Save a filmography for a named person in IMDb.

Search IMDb titles for person names or nconst IDs. An nconst ID should be
unique, but a person name can have several or even many matches. Allow user to
select one match or skip if there are too many.

Filmographies are created in subdirectories so they will not overload the
primary directory. Every job category is collected; you'll be asked once
before anything is written, and can page through the results instead.

Two files are written: a .tsv listing the person's credits by job category,
with an IMDb URL per title, and a .tconst list of the same titles suitable
for augment_tconstFiles.sh or generateXrefData.sh.

If you don't enter a parameter on the command line, you'll be prompted for
input.

USAGE:
    ./saveFilmography.sh [NCONST...] [PERSON NAME...]

OPTIONS:
    -h      Print this message.
    -m      Maximum matches for a person name allowed in menu - defaults to 10

EXAMPLES:
    ./saveFilmography.sh
    ./saveFilmography.sh "George Clooney"
    ./saveFilmography.sh nm0000123
    ./saveFilmography.sh nm0000123 "Quentin Tarantino"
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
ALL_TERMS $ALL_TERMS
NCONST_TERMS $NCONST_TERMS
PERSON_TERMS $PERSON_TERMS
POSSIBLE_MATCHES $POSSIBLE_MATCHES
MATCH_COUNTS $MATCH_COUNTS
PERSON_RESULTS $PERSON_RESULTS
JOB_RESULTS $JOB_RESULTS
JOB_ROLES $JOB_ROLES
ALLOWED_ROLES $ALLOWED_ROLES
FINAL_RESULTS $FINAL_RESULTS
TMPFILE $TMPFILE
EOT
    else
        rm -f "$ALL_TERMS" "$NCONST_TERMS" "$PERSON_TERMS" "$POSSIBLE_MATCHES"
        rm -f "$MATCH_COUNTS" "$PERSON_RESULTS" "$JOB_RESULTS" "$FINAL_RESULTS"
        rm -f "$JOB_ROLES" "$ALLOWED_ROLES" "$TMPFILE"
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

while getopts ":hm:" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    m)
        maxMenuSize="$OPTARG"
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
ALL_TERMS=$(mktemp)
NCONST_TERMS=$(mktemp)
PERSON_TERMS=$(mktemp)
POSSIBLE_MATCHES=$(mktemp)
MATCH_COUNTS=$(mktemp)
PERSON_RESULTS=$(mktemp)
JOB_RESULTS=$(mktemp)
JOB_ROLES=$(mktemp)
ALLOWED_ROLES=$(mktemp)
FINAL_RESULTS=$(mktemp)
TMPFILE=$(mktemp)

# Make sure a search term is supplied
if [[ $# -eq 0 ]]; then
    cat <<EOF
==> I can generate a filmography based on a person's name or nconst ID, such as
    nm0000123 -- which is the nconst for George Clooney taken from this URL:
    https://www.imdb.com/name/nm0000123/

Only one search term per line. Enter a blank line to finish.
EOF
    while read -r -p "Enter a person name or nconst ID: " searchTerm; do
        [[ -z $searchTerm ]] && break
        tr -ds '"' '[:space:]' <<<"$searchTerm" >>"$ALL_TERMS"
    done </dev/tty
    if [[ ! -s $ALL_TERMS ]]; then
        if waitUntil "$YN_PREF" -N \
            "Would you like me to generate a George Clooney filmography as an example?"; then
            printf "nm0000123\n" >>"$ALL_TERMS"
        else
            loopOrExitP
        fi
    fi
    printf "\n"
fi

# Get gz file size - which should already exist but make sure...
numRecords="$(rg -N name.basics.tsv.gz "$numRecordsFile" 2>/dev/null | cut -f 2)"
[[ -z $numRecords ]] && numRecords="$(rg -cz "^n" name.basics.tsv.gz)"

# Set up ALL_TERMS with one search term per line
for param in "$@"; do
    printf "$param\n" >>"$ALL_TERMS"
done
# Split into two groups so we can process them differently
rg -wN "^nm[0-9]{7,8}" "$ALL_TERMS" | sort -fu >"$NCONST_TERMS"
rg -wNv "nm[0-9]{7,8}" "$ALL_TERMS" | sort -fu >"$PERSON_TERMS"
printf "==> Searching $numRecords records for:\n"
cat "$NCONST_TERMS" "$PERSON_TERMS"

# Reconstitute ALL_TERMS with column guards
perl -p -e 's/^/^/; s/$/\\t/;' "$NCONST_TERMS" >"$ALL_TERMS"
perl -p -e 's/^/\\t/; s/$/\\t/;' "$PERSON_TERMS" >>"$ALL_TERMS"

# Get all possible matches at once
rg -NzSI -f "$ALL_TERMS" name.basics.tsv.gz | rg -wN "tt[0-9]{7,8}" | cut -f 1-5 |
    sort -f -t$'\t' --key=2 >"$POSSIBLE_MATCHES"
perl -pi -e 's+\\N++g; s+,+, +g; s+,  +, +g;' "$POSSIBLE_MATCHES"

# Figure how many matches for each possible match
cut -f 2 "$POSSIBLE_MATCHES" | frequency -s >"$MATCH_COUNTS"

# Job categories to save, one per line, "#" for comments -- the same file
# live-fetch uses to pick markdown sections. A missing or empty file means
# save everything.
allowedJobs=$(rg -N '^[^#]' rg_sections.rgx 2>/dev/null | tr '\n' '|')
allowedJobs="${allowedJobs%|}"
[[ -z $allowedJobs ]] && allowedJobs=".*"

# Build the filmography .tsv. $1 holds augmented title rows (tconst, titleType,
# primaryTitle, originalTitle, startYear), $2 holds the principals rows kept
# before augmenting (tconst, nconst, category, characters).
#
# Sections are separated by a blank row and a job name rather than carrying a
# job column. Both are padded to the full column count so the file stays
# rectangular. Note the tradeoff: a spreadsheet sort across the whole file
# will pull the job rows into the data. Sort a selected range, or sort before
# generating.
function _generate_filmography_tsv() {
    awk -F'\t' -v OFS='\t' '
        # First file: title data, keyed by tconst
        NR == FNR {
            type[$1] = $2; title[$1] = $3; year[$1] = $5
            next
        }
        # Second file: one row per credit
        {
            tconst = $1
            # augment_tconstFiles.sh drops tvEpisodes, so a tconst with no
            # title entry is an episode row and is skipped here too.
            if (!(tconst in title)) next
            # characters is a JSON array string: ["Ryan Bingham"] or \N
            chars = $4
            if (chars == "\\N") chars = ""
            sub(/^\[/, "", chars); sub(/\]$/, "", chars)
            gsub(/","/, "; ", chars)
            gsub(/"/, "", chars)
            # Bulk spells categories with underscores, the credits page uses
            # spaces. Match live-fetch.
            job = $3
            gsub(/_/, " ", job)
            print job, year[tconst], title[tconst], type[tconst], chars, \
                "https://www.imdb.com/title/" tconst "/"
        }
    ' "$1" "$2" |
        sort -f -t$'\t' --key=1,1 --key=2,2r --key=3,3 |
        awk -F'\t' -v OFS='\t' '
            BEGIN { print "Year", "Title", "Type", "Character", "URL" }
            # Separator and section rows are padded to the full column count.
            # A ragged row is not just untidy here -- tsvPrint parses this file
            # as CSV and errors out on a row with the wrong number of fields.
            $1 != job {
                job = $1
                print "", "", "", "", ""
                print job, "", "", "", ""
            }
            { print $2, $3, $4, $5, $6 }
        '
}

# Add possible matches one at a time, preceded by URL
while read -r line; do
    count=$(cut -f 1 <<<"$line")
    match=$(cut -f 2 <<<"$line")
    if [[ $count -eq 1 ]]; then
        rg "\t$match\t" "$POSSIBLE_MATCHES" |
            sed 's+^+imdb.com/name/+' >>"$PERSON_RESULTS"
        continue
    fi
    if [[ -z $alreadyPrintedP ]]; then
        cat <<EOF

Some person names occur more than once on IMDb, e.g. John Wayne or John Lennon.
You can determine which one to select using the provided links to imdb.com.
EOF
        alreadyPrintedP="yes"
    fi

    printf "\nI found $count persons named \"$match\"\n"
    if [[ $count -ge ${maxMenuSize:-10} ]]; then
        waitUntil "$YN_PREF" -Y "Should I skip trying to select one?" && continue
    fi

    # Create parallel tabbed and sorted array
    rg "\t$match\t" "$POSSIBLE_MATCHES" | sort -f -t$'\t' --key=3,3r --key=5 |
        sed 's+^+imdb.com/name/+' >"$TMPFILE"
    #
    tabbedOptions=()
    while IFS='' read -r line; do tabbedOptions+=("$line"); done <"$TMPFILE"

    # Create tsvPrinted select array
    rg "\t$match\t" "$POSSIBLE_MATCHES" | sort -f -t$'\t' --key=3,3r --key=5 |
        sed 's+^+imdb.com/name/+' >"$TMPFILE"
    #
    pickOptions=()
    while IFS='' read -r line; do
        pickOptions+=("$line")
    done < <(tsvPrint -c 2 "$TMPFILE")
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
                printf "${tabbedOptions[REPLY - 1]}\n" >>"$PERSON_RESULTS"
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
if [[ ! -s $PERSON_RESULTS ]]; then
    printf "==> I didn't find ${RED}any${NO_COLOR} matching persons.\n"
    printf "    Check the \"Searching $numRecords records for:\" section above.\n"
    loopOrExitP
fi

# Found results, check with user before adding
printf "\nThese are the results I can process:\n"
tsvPrint -c 2 "$PERSON_RESULTS"

# Get rid of the URL preface we added
cp "$PERSON_RESULTS" "$TMPFILE"
sed 's+imdb.com/name/++;' "$TMPFILE" >"$PERSON_RESULTS"

if ! waitUntil "$YN_PREF" -Y; then
    loopOrExitP
fi

cut -f 1 "$PERSON_RESULTS" >"$NCONST_TERMS"
# tconst, nconst, category, characters. The characters field is kept for the
# .tsv -- augment_tconstFiles.sh replaces these rows with title.basics columns,
# so anything not saved before augmenting is lost.
rg -Nz -f "$NCONST_TERMS" title.principals.tsv.gz |
    cut -f 1,3,4,6 >"$POSSIBLE_MATCHES"

# Filmography data comes from the local title.principals.tsv.gz read above. The
# FULLCAST live-fetch path (curl the person's fullcredits page, parse with
# getFilmography.awk) is retired -- IMDb 403s a bot User-Agent, WAF-challenges a
# browser one, and the page is React-rendered now, so the awk parsed nothing.

while read -r line; do
    true >"$FINAL_RESULTS"
    true >"$ALLOWED_ROLES"
    nconstID="$line"
    nconstName="$(rg -N "$line" "$PERSON_RESULTS" | cut -f 2)"
    rg -Nw "$nconstID" "$POSSIBLE_MATCHES" | cut -f 3 | frequency -t >"$MATCH_COUNTS"
    if [[ ! -s $MATCH_COUNTS ]]; then
        printf "\n==> I didn't find any principal cast & crew member records for "
        printf "${RED}$nconstName${NO_COLOR}.\n"
        printf "    Check ${RED}imdb.com/name/$nconstID${NO_COLOR} to get more details.\n"
        continue
    fi
    noSpaceName="$(safeFilename "$nconstName")"
    filmographyDir="$noSpaceName-Filmography"
    filmographyFile="$filmographyDir/$noSpaceName.tconst"
    filmographyTsv="$filmographyDir/$noSpaceName.tsv"
    filmographyDB="$filmographyDir/$noSpaceName.csv"
    TCONST_FILE="$filmographyFile"

    # Collect the whitelisted job categories. Deciding which of those to keep
    # is easier done by editing the finished file than by answering a prompt
    # per category, so this only reports what it found. Summary lines are
    # buffered so the total can be printed above them, as on live-fetch.
    true >"$TMPFILE"
    while read -r job; do
        match=$(cut -f 2 <<<"$job")
        rg -Nw "$nconstID\t$match" "$POSSIBLE_MATCHES" >"$JOB_RESULTS"
        # augment_tconstFiles.sh overwrites its argument, so keep the credit
        # rows -- job category and characters -- for the .tsv first.
        cp "$JOB_RESULTS" "$JOB_ROLES"
        ./augment_tconstFiles.sh -y "$JOB_RESULTS"
        # Counted after augmenting, which drops tvEpisodes -- so this is the
        # number of titles that will actually be written, not the raw
        # principals count.
        numResults=$(sed -n '$=' "$JOB_RESULTS")
        [[ -z $numResults ]] && numResults=0
        [[ $numResults -eq 0 ]] && continue
        # IMDb's bulk dataset spells categories with underscores
        # (archive_footage) where the credits page -- and so rg_sections.rgx --
        # uses spaces. Normalize before matching rather than carrying two
        # spellings in the whitelist.
        if rg -qxNi -e "$allowedJobs" <<<"$(tr '_' ' ' <<<"$match")"; then
            printf "  %-20s %s titles\n" "$match:" "$numResults" >>"$TMPFILE"
            cat "$JOB_RESULTS" >>"$FINAL_RESULTS"
            cat "$JOB_ROLES" >>"$ALLOWED_ROLES"
        else
            printf "  %-20s %s titles (not saved)\n" "$match:" "$numResults" >>"$TMPFILE"
        fi
    done <"$MATCH_COUNTS"

    if [[ ! -s $FINAL_RESULTS ]]; then
        printf "\n==> There aren't ${RED}any${NO_COLOR} $nconstName titles to add.\n"
        continue
    fi

    # A title can credit the same person under more than one category (actress
    # and producer, say), so the per-job files overlap. The job name is not
    # part of an augmented row, so duplicates are byte-identical.
    sort -u "$FINAL_RESULTS" -o "$FINAL_RESULTS"
    numlines=$(sed -n '$=' "$FINAL_RESULTS")

    printf "\n==> Filmography for $nconstName ($numlines titles)\n"
    cat "$TMPFILE"

    printf "\n==> Save to ${BLUE}$filmographyTsv${NO_COLOR}\n"
    printf "        and ${BLUE}$filmographyFile${NO_COLOR}?\n"
    if waitUntil "$YN_PREF" -Y "==> Save filmography?"; then
        mkdir -p "$filmographyDir"
        rg -N "^tt" "$FINAL_RESULTS" | sort -f -t$'\t' --key=3,3 >"$TCONST_FILE"
        _generate_filmography_tsv "$FINAL_RESULTS" "$ALLOWED_ROLES" >"$filmographyTsv"
        printf "==> Saved.\n"
        waitUntil "$YN_PREF" -Y \
            "\n==> Shall I generate ${BLUE}$(basename "$filmographyDB")${NO_COLOR}?" &&
            ./generateXrefData.sh -q -f "$filmographyDB" -d "$filmographyDir" "$filmographyFile"
    else
        # Nothing was written, so offer a look at what would have been.
        # Exploring in $PAGER beats saving a file just to delete it later.
        if waitUntil "$YN_PREF" -N "==> Would you like to view it instead?"; then
            _generate_filmography_tsv "$FINAL_RESULTS" "$ALLOWED_ROLES" >"$TMPFILE"
            tsvPrint -n "$TMPFILE" | ${PAGER:-less}
        fi
    fi
done <"$NCONST_TERMS"

# Do we really want to quit?
loopOrExitP
