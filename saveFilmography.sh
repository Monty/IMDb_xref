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

Filmographies are saved in the primary directory, named
Person_Name-nconst-Filmography.md, matching live-fetch. Only the job
categories listed in rg_sections.rgx are written; the rest are reported but
skipped. You'll be asked once before the markdown file is saved, and again
before a .tconst list of the titles is written.

Note that this branch reads IMDb's bulk .tsv.gz datasets, which list only the
principal names per title. Supporting and guest work is under-represented --
use live-fetch for a complete filmography.

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
JOB_ROLES $JOB_ROLES
ALLOWED_ROLES $ALLOWED_ROLES
TITLE_INFO $TITLE_INFO
EPISODE_MAP $EPISODE_MAP
EPISODE_COUNTS $EPISODE_COUNTS
FINAL_RESULTS $FINAL_RESULTS
TMPFILE $TMPFILE
EOT
    else
        rm -f "$ALL_TERMS" "$NCONST_TERMS" "$PERSON_TERMS" "$POSSIBLE_MATCHES"
        rm -f "$MATCH_COUNTS" "$PERSON_RESULTS" "$FINAL_RESULTS" "$TITLE_INFO"
        rm -f "$JOB_ROLES" "$ALLOWED_ROLES" "$EPISODE_MAP" "$EPISODE_COUNTS"
        rm -f "$TMPFILE"
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
JOB_ROLES=$(mktemp)
ALLOWED_ROLES=$(mktemp)
TITLE_INFO=$(mktemp)
EPISODE_MAP=$(mktemp)
EPISODE_COUNTS=$(mktemp)
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

# Emit one sorted row per credit. Columns: rank, upcoming, job, year, title,
# type, character, episodes, tconst.
#
# $1 holds title rows (tconst, titleType, primaryTitle, originalTitle,
# startYear), $2 holds the principals credit rows (tconst, nconst, category,
# characters), $3 holds episode counts keyed by nconst, series tconst and
# category.
#
# Files are matched by FILENAME rather than the usual NR == FNR chain: any of
# them can legitimately be empty -- a person with no episode credits is the
# common case -- and an empty file would silently shift every later one into
# the wrong branch.
#
# rank sorts acting first, then the other credited roles, before everything
# else -- matching live-fetch's section order. upcoming floats titles with no
# startYear to the top of their section, where live-fetch puts Post-production
# and Pre-production. Bulk has no status field, so a missing year is the only
# available proxy: usually an unreleased title, but an obscure old credit with
# no recorded year lands there too. The emitter drops these two columns.
_filmography_rows() {
    awk -F'\t' -v OFS='\t' -v titlesFile="$1" -v epsFile="$3" '
        # Title data, keyed by tconst
        FILENAME == titlesFile {
            type[$1] = $2; title[$1] = $3; year[$1] = $5
            next
        }
        # Episode counts, keyed by nconst, series tconst and category
        FILENAME == epsFile {
            eps[$1 FS $2 FS $3] = $4
            next
        }
        # One row per credit
        {
            tconst = $1
            # tvEpisodes were filtered out of the title lookup, so a tconst
            # with no title entry is an episode row and is skipped here too.
            if (!(tconst in title)) next
            # characters is a JSON array string: ["Ryan Bingham"] or \N
            chars = $4
            if (chars == "\\N") chars = ""
            sub(/^\[/, "", chars); sub(/\]$/, "", chars)
            gsub(/","/, "; ", chars)
            gsub(/"/, "", chars)
            episodes = eps[$2 FS tconst FS $3]
            # Bulk spells categories with underscores, the credits page uses
            # spaces. Match live-fetch.
            job = $3
            gsub(/_/, " ", job)
            rank = 4
            if (job == "actor" || job == "actress") rank = 0
            else if (job == "director") rank = 1
            else if (job == "writer")   rank = 2
            else if (job == "producer") rank = 3
            upcoming = (year[tconst] == "") ? 0 : 1
            print rank, upcoming, job, year[tconst], title[tconst], \
                type[tconst], chars, episodes, tconst
        }
    ' "$1" "$3" "$2" |
        sort -f -t$'\t' --key=1,1 --key=3,3 --key=2,2 --key=4,4r --key=5,5
}

# Markdown, matching live-fetch's layout so a filmography from either branch
# reads the same. $4 is the person name, $5 the nconst.
#
# The note under the title is not decoration. title.principals caps at roughly
# ten names per title, so this output silently omits work rather than
# truncating visibly -- Elizabeth Debicki's The Crown is absent entirely, and
# her Night Manager episode count comes in under the real one. A reader who
# does not know that will read a short filmography as a complete one.
_generate_filmography_md() {
    _filmography_rows "$1" "$2" "$3" |
        awk -F'\t' -v name="$4" -v nconst="$5" '
            function esc(s) { gsub(/\|/, "\\&#124;", s); return s }
            function titleCase(s,   i, parts, count, out) {
                count = split(s, parts, " ")
                out = ""
                for (i = 1; i <= count; i++)
                    out = out (i > 1 ? " " : "") \
                        toupper(substr(parts[i], 1, 1)) substr(parts[i], 2)
                return out
            }
            # Buffered per section: the Episodes column is only written when
            # the section has data for it, which is not known until the last
            # row of that section has been read.
            function flush(   i, charHeader, when, cell, eps) {
                if (rows == 0) return
                printf("\n## %s (%d)\n\n", titleCase(job), rows)
                charHeader = (job == "actor" || job == "actress") ? "Character" : "Credit"
                if (hasEps) {
                    printf("| Year | Title | Type | %s | Episodes |\n", charHeader)
                    printf("|------|-------|------|-----------|---------:|\n")
                } else {
                    printf("| Year | Title | Type | %s |\n", charHeader)
                    printf("|------|-------|------|-----------|\n")
                }
                for (i = 1; i <= rows; i++) {
                    when = (bYear[i] == "" ? "-" : bYear[i])
                    cell = (bChar[i] == "" ? "-" : esc(bChar[i]))
                    printf("| %s | [%s](https://www.imdb.com/title/%s/) | %s | %s",
                        when, esc(bTitle[i]), bTconst[i],
                        (bType[i] == "" ? "-" : esc(bType[i])), cell)
                    if (hasEps) {
                        eps = (bEps[i] == "" || bEps[i] == 0) ? "-" : bEps[i]
                        printf(" | %s", eps)
                    }
                    printf(" |\n")
                }
                rows = 0; hasEps = 0
            }
            BEGIN {
                print "# [" name "](https://www.imdb.com/name/" nconst "/)"
                print ""
                print "> Generated from IMDb'"'"'s bulk .tsv.gz datasets, which list only"
                print "> the principal names per title. Supporting and guest work is"
                print "> under-represented: some titles are missing entirely, and episode"
                print "> counts are the episodes where this person was a principal, not"
                print "> IMDb'"'"'s credited-episode totals. Use the live-fetch branch for a"
                print "> complete filmography."
            }
            $3 != job { flush(); job = $3 }
            {
                rows++
                bYear[rows] = $4; bTitle[rows] = $5; bType[rows] = $6
                bChar[rows] = $7; bEps[rows] = $8; bTconst[rows] = $9
                if ($8 != "" && $8 != 0) hasEps = 1
            }
            END { flush() }
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
# tconst, nconst, category, characters. The characters field feeds the
# Character column; the episode counts below need these rows before the
# tvEpisode entries are filtered out of the title lookup.
rg -Nz -f "$NCONST_TERMS" title.principals.tsv.gz |
    cut -f 1,3,4,6 >"$POSSIBLE_MATCHES"

# Episode counts. title.principals credits a person once per episode they were
# a principal in, so the count is the number of those rows whose parent series
# is the title being listed. Computed from the raw principals rows, which still
# carry the tvEpisode entries the title lookup filters out.
#
# Note what this counts: episodes where the person made the ~10-name principals
# cut, not the credited-episode total IMDb's own page reports. Expect leads to
# match and supporting players to undercount.
cut -f 1 "$POSSIBLE_MATCHES" | sort -u |
    perl -p -e 's/^/^/; s/$/\\t/;' >"$TMPFILE"
rg -Nz -f "$TMPFILE" title.episode.tsv.gz | cut -f 1,2 >"$EPISODE_MAP"
awk -F'\t' -v OFS='\t' -v mapFile="$EPISODE_MAP" '
    # episode tconst -> parent series tconst
    FILENAME == mapFile { parent[$1] = $2; next }
    # Credit rows: tconst, nconst, category, characters. Only rows whose
    # tconst is an episode contribute; a series-level row is the thing being
    # counted for, not a count of one.
    ($1 in parent) { count[$2 FS parent[$1] FS $3]++ }
    END { for (key in count) print key, count[key] }
' "$EPISODE_MAP" "$POSSIBLE_MATCHES" >"$EPISODE_COUNTS"

# Filmography data comes from the local title.principals.tsv.gz read above. The
# FULLCAST live-fetch path (curl the person's fullcredits page, parse with
# getFilmography.awk) is retired -- IMDb 403s a bot User-Agent, WAF-challenges a
# browser one, and the page is React-rendered now, so the awk parsed nothing.

while read -r line; do
    true >"$FINAL_RESULTS"
    true >"$ALLOWED_ROLES"
    savedAnything=""
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
    # Top level, not a per-person subdirectory, and carrying the nconst --
    # matching live-fetch, so a filmography from either branch is recognizable
    # as the same kind of thing. The nconst is the only part guaranteed
    # unique.
    filmographyMd="${noSpaceName}-${nconstID}-Filmography.md"
    filmographyFile="${noSpaceName}-${nconstID}.tconst"
    filmographyDB="${noSpaceName}-${nconstID}.csv"
    TCONST_FILE="$filmographyFile"

    # One title.basics lookup for every title this person is credited on,
    # replacing augment_tconstFiles.sh -y. That was called once per job
    # category -- six scans of the same .gz for George Clooney -- and
    # overwrote its argument, so the credit rows had to be copied aside before
    # each call. Its behaviours are reproduced here: cut -f 1-4,6 for the
    # column set, dropping tvEpisodes so a series is one row rather than one
    # row per episode, and stripping IMDb's \N NULL marker -- without that
    # last step an unreleased title with no startYear renders a literal \N in
    # the Year column instead of being treated as missing.
    #
    # The .tconst written below is augmented separately by
    # augment_tconstFiles.sh, so nothing here has to match its column format.
    rg -Nz -f <(rg -Nw "$nconstID" "$POSSIBLE_MATCHES" | cut -f 1 | sort -u |
        perl -p -e 's/^/^/; s/$/\\t/;') title.basics.tsv.gz |
        cut -f 1-4,6 | perl -p -e 's+\\N++g;' |
        rg -wNv "tvEpisode" >"$TITLE_INFO"

    # Collect the whitelisted job categories. Deciding which of those to keep
    # is easier done by editing the finished file than by answering a prompt
    # per category, so this only reports what it found. Summary lines are
    # buffered so the total can be printed above them, as on live-fetch.
    true >"$TMPFILE"
    while read -r job; do
        match=$(cut -f 2 <<<"$job")
        rg -Nw "$nconstID\t$match" "$POSSIBLE_MATCHES" >"$JOB_ROLES"
        # Unique titles for this category that survived the tvEpisode filter
        # -- the number that will actually be written, not the raw principals
        # count.
        numResults=$(awk -F'\t' -v titlesFile="$TITLE_INFO" '
            FILENAME == titlesFile { keep[$1]; next }
            ($1 in keep) && !seen[$1]++ { n++ }
            END { print n + 0 }
        ' "$TITLE_INFO" "$JOB_ROLES")
        [[ $numResults -eq 0 ]] && continue
        # IMDb's bulk dataset spells categories with underscores
        # (archive_footage) where the credits page -- and so rg_sections.rgx --
        # uses spaces. Normalize before matching rather than carrying two
        # spellings in the whitelist.
        if rg -qxNi -e "$allowedJobs" <<<"$(tr '_' ' ' <<<"$match")"; then
            printf "  %-20s %s titles\n" "$match:" "$numResults" >>"$TMPFILE"
            cat "$JOB_ROLES" >>"$ALLOWED_ROLES"
        else
            printf "  %-20s %s titles (not saved)\n" "$match:" "$numResults" >>"$TMPFILE"
        fi
    done <"$MATCH_COUNTS"

    # The title rows behind the whitelisted credits, one per title. A title can
    # credit the same person under more than one category (actress and
    # producer, say), so the categories overlap and duplicates are dropped
    # here.
    awk -F'\t' -v OFS='\t' -v titlesFile="$TITLE_INFO" '
        FILENAME == titlesFile { row[$1] = $0; next }
        ($1 in row) && !seen[$1]++ { print row[$1] }
    ' "$TITLE_INFO" "$ALLOWED_ROLES" |
        sort -f -t$'\t' --key=3,3 >"$FINAL_RESULTS"

    if [[ ! -s $FINAL_RESULTS ]]; then
        printf "\n==> There aren't ${RED}any${NO_COLOR} $nconstName titles to add.\n"
        continue
    fi

    numlines=$(sed -n '$=' "$FINAL_RESULTS")

    printf "\n==> Filmography for $nconstName ($numlines titles)\n"
    cat "$TMPFILE"

    # Two prompts, as on live-fetch. They have different audiences -- the .md
    # is the readable artifact, the .tconst is a corpus edit -- and bundling
    # them meant answering yes to both to get either.
    printf "\n"
    if waitUntil "$YN_PREF" -Y \
        "==> Save filmography to ${BLUE}$filmographyMd${NO_COLOR}?"; then
        _generate_filmography_md "$FINAL_RESULTS" "$ALLOWED_ROLES" \
            "$EPISODE_COUNTS" "$nconstName" "$nconstID" >"$filmographyMd"
        printf "==> Saved.\n"
        savedAnything="yes"
    fi

    # Written as bare tconst IDs, then augmented in place to add the Type,
    # Primary Title, Original Title and Date columns.
    #
    # A corpus edit rather than a read, so -N. generateXrefData.sh reads this
    # file, so the .csv offer is nested rather than asked when there would be
    # nothing to read.
    printf "\n==> This filmography includes %s unique titles.\n" "$numlines"
    if waitUntil "$YN_PREF" -N \
        "==> Shall I save them to ${BLUE}$filmographyFile${NO_COLOR}?"; then
        cut -f 1 "$FINAL_RESULTS" | sort -u >"$TCONST_FILE"
        # Augmented right away rather than leaving bare IDs and printing the
        # command. On this branch that is a local .gz lookup taking seconds,
        # it matches every other .tconst in the corpus, and it seeds
        # augment_tconstFiles.sh's own cache for later runs. Live-fetch prints
        # the hint instead because there it means one scrape per title.
        ./augment_tconstFiles.sh -y "$TCONST_FILE"
        printf "==> Saved.\n"
        savedAnything="yes"
        waitUntil "$YN_PREF" -N \
            "\n==> Shall I generate ${BLUE}$filmographyDB${NO_COLOR}?" &&
            ./generateXrefData.sh -q -f "$filmographyDB" "$filmographyFile"
    fi

    # Nothing was written, so offer a look at what would have been.
    # Exploring in $PAGER beats saving a file just to delete it later.
    if [[ -z $savedAnything ]]; then
        if waitUntil "$YN_PREF" -N "==> Would you like to view it instead?"; then
            _generate_filmography_md "$FINAL_RESULTS" "$ALLOWED_ROLES" \
                "$EPISODE_COUNTS" "$nconstName" "$nconstID" | ${PAGER:-less}
        fi
    fi
done <"$NCONST_TERMS"

# Do we really want to quit?
loopOrExitP
