#!/usr/bin/env bash
#
# Save a filmography for a named person in IMDb
# Uses the Playwright-based scraper.

DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
saveFilmography.sh -- Save a filmography for a named person in IMDb.

Search IMDb for person names or nconst IDs. An nconst ID should be unique,
but a person name can have several or even many matches. Allow user to
select one match or skip if there are too many.

Filmographies are saved as Markdown in secondary/filmographies/. You'll have
the opportunity to review results before committing.

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

trap terminate EXIT
ALL_TERMS=""
PERSON_RESULTS=""
NCONST_TERMS=""
TMPFILE=""
FILMOGRAPHY_JSON=""
SCRAPER_ERR=""

function terminate() {
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
    else
        rm -f "$ALL_TERMS" "$PERSON_RESULTS" "$NCONST_TERMS" "$TMPFILE" "$FILMOGRAPHY_JSON" "$SCRAPER_ERR"
    fi
}

trap cleanup INT
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

_scraper() {
    uv run --directory scraper python cli.py "$@"
}

# Replacement for _generate_filmography_md() in saveFilmography.sh
#
# Fixes over the original:
#
#   1. The whitelist filter was a no-op. It read
#        map(select(. as $j | $allowed | any(test(.; "i"))))
#      Inside any(), "." is each allowed string and the pattern is also
#      ".", so every entry was tested against itself and always matched;
#      $j was bound but never used. Every category got through, including
#      Self, Thanks and Archive Footage. Now matched whole-string against
#      $j, so "editor" no longer pulls in "editorial department" either.
#
#   2. select(.character != "" and .character != null) dropped every
#      non-acting section. Directors and writers have no character, so
#      filteredRoles came back empty and the loop hit continue -- there
#      was no way to ever emit a Director table. Removed.
#
#   3. tonumber // 0 does not catch errors -- "//" only handles null and
#      false. An ongoing series year like "2024- " splits to " ", and
#      " " | tonumber throws, aborting the whole jq call. Replaced with
#      scan(), which cannot throw.
#
#   4. The acting separator row was missing its trailing pipe.
#
#   5. ${DIRNAME}/rg_sections.rgx was evaluated after the script already
#      did cd "$DIRNAME", so it was double-relative. Uses the bare name.
#
# Also: the large startswith() noise filter is gone. It existed to strip
# credit text that leaked into the character field because every role was
# being labelled "actor"; with get_filmography() fixed, the categories are
# real and rg_sections.rgx does the filtering.
#
# Unreleased titles sort to the top of every section, above the newest
# released one, in the order IMDb lists them. Their Year cell shows the
# production status instead ("Post-production", "Pre-production (2026)").
# Set SKIP_UNRELEASED=yes to leave them out entirely.
#
# A title counts as unreleased when it carries a status other than
# "Released" -- IMDb marks some released titles with an explicit
# "Released", so the presence of a status is not enough on its own.
#
# Requires the matching models.py field:
#     status: str = ""
# Without it every row reports an empty status, nothing is treated as
# unreleased, and the output is the same as it would have been before.
#
# Bash 3.2 compatible: no mapfile, no associative arrays.

# Generate a markdown filmography file from JSON data
_generate_filmography_md() {
    local jsonData="$1"
    local outputFile="$2"

    # Set SKIP_UNRELEASED=yes to omit titles that have not been released.
    local skipUnreleased="${SKIP_UNRELEASED:-no}"

    # Job categories to include, one per line, "#" for comments. Missing or
    # empty file means include everything.
    local allowedJobs
    allowedJobs=$(rg -N '^[^#]' rg_sections.rgx 2>/dev/null | tr '\n' '|')
    allowedJobs="${allowedJobs%|}"
    [[ -z $allowedJobs ]] && allowedJobs=".*"

    # Header: name as an IMDb link, disambiguation suffix stripped
    jq -r '"# [" + (.name | gsub(" ?\\([IVX]+\\)"; "")) +
           "](https://www.imdb.com/name/" + .nconst + "/)"' \
        <<<"$jsonData" >"$outputFile"

    # Job sections present in the data, whitelisted, acting first
    local jobs
    jobs=$(jq -r --arg whitelist "$allowedJobs" '
        ($whitelist | split("|") | map(select(length > 0))) as $allowed
        | [.roles[].job // empty]
        | unique
        | map(select(. as $j | $allowed | any(. as $a | $j | test("^" + $a + "$"; "i"))))
        | map(
            if . == "actor" or . == "actress" then "0_"
            elif . == "director" then "1_"
            elif . == "writer"   then "2_"
            elif . == "producer" then "3_"
            else "4_" end + .
          )
        | sort
        | map(.[2:])
        | .[]
    ' <<<"$jsonData")

    local job jobTitle consolidated count hasEps charHeader

    while IFS= read -r job; do
        [[ -z $job ]] && continue

        # One entry per title. Unreleased first in IMDb's own order, then
        # released newest first, ties broken by position on the page.
        consolidated=$(jq --arg j "$job" --arg skip "$skipUnreleased" '
            [ .roles[]
              | select(.job == $j)
              | { tconst,
                  title:      (.title // "Unknown"),
                  year:       (.year // ""),
                  title_type: (.title_type // ""),
                  status:     (.status // ""),
                  character:  (.character // ""),
                  episodes:   (.episodes // 0) }
            ]
            | to_entries
            | map(.value + { idx: .key })
            | map(. + { upcoming: (.status != ""
                                   and (.status | ascii_downcase) != "released") })
            | if $skip == "yes" then map(select(.upcoming | not)) else . end
            | group_by(.tconst)
            | map({
                tconst:     .[0].tconst,
                title:      .[0].title,
                year:       ([.[].year       | select(. != "")] | if length > 0 then .[0] else "" end),
                title_type: ([.[].title_type | select(. != "")] | if length > 0 then .[0] else "" end),
                status:     ([.[].status     | select(. != "")] | if length > 0 then .[0] else "" end),
                character:  ([.[].character  | select(. != "")] | unique | join(" / ")),
                episodes:   ([.[].episodes] | max),
                upcoming:   ([.[].upcoming] | any),
                idx:        ([.[].idx] | min)
              })
            | sort_by([
                (if .upcoming then 0 else 1 end),
                (if .upcoming then 0
                 else -( .year
                         | [scan("[0-9]{4}")]
                         | if length > 0 then (.[-1] | tonumber) else 0 end )
                 end),
                .idx
              ])
        ' <<<"$jsonData")

        count=$(jq 'length' <<<"$consolidated")
        [[ -z $count || $count -eq 0 ]] && continue

        # Episode counts are not just an acting thing -- Self and Archive
        # Footage carry them too. Show the column when there is data for it.
        hasEps=$(jq '[.[] | select(.episodes > 0)] | length' <<<"$consolidated")

        charHeader="Credit"
        if [[ $job == "actor" || $job == "actress" ]]; then
            charHeader="Character"
        fi

        jobTitle=$(printf '%s\n' "$job" |
            awk '{for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2)} 1')

        printf '\n## %s (%s)\n\n' "$jobTitle" "$count" >>"$outputFile"

        if [[ $hasEps -gt 0 ]]; then
            printf '| Year | Title | Type | %s | Episodes |\n' "$charHeader" >>"$outputFile"
            printf '|------|-------|------|-----------|---------:|\n' >>"$outputFile"
        else
            printf '| Year | Title | Type | %s |\n' "$charHeader" >>"$outputFile"
            printf '|------|-------|------|-----------|\n' >>"$outputFile"
        fi

        jq -r --argjson withEps "$hasEps" '
            def esc: gsub("\\|"; "&#124;");
            .[]
            | (if .upcoming
               then .status + (if .year != "" then " (" + .year + ")" else "" end)
               elif .year == "" then "-"
               else .year end) as $when
            | "| " + $when
              + " | [" + (.title | esc) + "](https://www.imdb.com/title/" + .tconst + "/)"
              + " | " + (if .title_type == "" then "-" else (.title_type | esc) end)
              + " | " + (if .character  == "" then "-" else (.character  | esc) end)
              + (if $withEps > 0
                 then " | " + (if .episodes > 0 then (.episodes | tostring) else "-" end)
                 else "" end)
              + " |"
        ' <<<"$consolidated" >>"$outputFile"

    done <<<"$jobs"
}

while getopts ":hm:" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    m) maxMenuSize="$OPTARG" ;;
    \?) printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2 ;;
    :)
        printf "==> Option -$OPTARG requires an argument.\n" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

ALL_TERMS=$(mktemp)
PERSON_RESULTS=$(mktemp)
NCONST_TERMS=$(mktemp)
TMPFILE=$(mktemp)
FILMOGRAPHY_JSON=$(mktemp)
SCRAPER_ERR=$(mktemp)

# Make sure a search term is supplied
if [[ $# -eq 0 ]]; then
    cat <<EOF
==> I can generate a filmography based on a person's name or nconst ID,
    such as nm0000123 for George Clooney:
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

for param in "$@"; do
    printf "%s\n" "$param" >>"$ALL_TERMS"
done

printf "==> Searching for:\n"
cat "$ALL_TERMS"

# Process each search term
while IFS= read -r searchTerm; do
    [[ -z $searchTerm ]] && continue

    # needConfirm gates the "Does that look correct?" prompt: set on the paths
    # that resolve a person with no user interaction (an nconst ID, or a name
    # with exactly one match). The multi-match menu is its own confirmation.
    needConfirm=""
    nconst=""
    nconstName=""
    professions=""
    knownFor=""

    if [[ $searchTerm =~ ^nm[0-9]{7,8}$ ]]; then
        nconst="$searchTerm"
        personInfo=$(_scraper person-info "$nconst" 2>/dev/null)
        if [[ -n $personInfo ]] && [[ $personInfo != *"not found"* ]]; then
            nconstName=$(jq -r '.name // empty' <<<"$personInfo")
            printf "%s\t%s\n" "$nconst" "$nconstName" >>"$PERSON_RESULTS"
            needConfirm="yes"
        fi
    else
        # Search for the person on IMDb
        printf "==> Searching IMDb for \"%s\"...\n" "$searchTerm"
        # Capture stderr so a scraper failure (e.g. a WAF challenge) is
        # reported instead of being silently reinterpreted as "no matches".
        if ! searchResults=$(_scraper --delay 1 search-person "$searchTerm" 2>"$SCRAPER_ERR"); then
            reportSearchError "$searchTerm" "$SCRAPER_ERR"
            # A CAPTCHA blocks every later search too; repeating it for each
            # remaining term just prints the same error N times and keeps
            # hitting IMDb. Stop here.
            if isWAFChallenge "$SCRAPER_ERR"; then
                printf "    Skipping any remaining search terms.\n"
                break
            fi
            continue
        fi
        matchCount=$(jq 'length' <<<"$searchResults" 2>/dev/null)
        matchCount=${matchCount:-0}

        if [[ $matchCount -eq 0 ]]; then
            printf "==> No matches found for \"%s\"\n" "$searchTerm"
            continue
        fi

        if [[ $matchCount -ge 2 ]]; then
            if [[ $matchCount -ge ${maxMenuSize:-10} ]]; then
                if waitUntil "$YN_PREF" -Y "Found $matchCount matches. Skip?"; then
                    continue
                fi
            fi
            printf "\nI found %s people named \"%s\"\n" "$matchCount" "$searchTerm"

            jq -r '.[] | "\(.nconst)\t\(.name)\t\(.professions // "")\t\(.known_for_title // "")"' <<<"$searchResults" >"$TMPFILE"
            pickOptions=()
            tabbedOptions=()
            while IFS= read -r line; do
                pickOptions+=("$line")
            done < <(tsvPrint "$TMPFILE")
            pickOptions+=("Skip \"$searchTerm\"" "Quit")

            while IFS= read -r line; do
                tabbedOptions+=("$line")
            done < <(jq -r '.[] | "\(.nconst)\t\(.name)\t\(.professions // "")\t\(.known_for_title // "")"' <<<"$searchResults")

            PS3="Select (1-${#pickOptions[@]}): "
            COLUMNS=40
            select pickMenu in "${pickOptions[@]}"; do
                if [[ $REPLY -ge 1 ]] 2>/dev/null && [[ $REPLY -le ${#pickOptions[@]} ]]; then
                    case "$pickMenu" in
                    Skip*) break ;;
                    Quit) loopOrExitP ;;
                    *)
                        nconst=$(cut -f1 <<<"${tabbedOptions[REPLY - 1]}")
                        nconstName=$(cut -f2 <<<"${tabbedOptions[REPLY - 1]}")
                        professions=$(cut -f3 <<<"${tabbedOptions[REPLY - 1]}")
                        knownFor=$(cut -f4 <<<"${tabbedOptions[REPLY - 1]}")
                        break
                        ;;
                    esac
                else
                    case "$REPLY" in [Qq]*) loopOrExitP ;; esac
                fi
            done </dev/tty
            [[ -z $nconst ]] && continue
            printf "%s\t%s\n" "$nconst" "$nconstName" >>"$PERSON_RESULTS"
        else
            nconst=$(jq -r '.[0].nconst' <<<"$searchResults")
            nconstName=$(jq -r '.[0].name' <<<"$searchResults")
            professions=$(jq -r '.[0].professions // ""' <<<"$searchResults")
            knownFor=$(jq -r '.[0].known_for_title // ""' <<<"$searchResults")
            printf "%s\t%s\n" "$nconst" "$nconstName" >>"$PERSON_RESULTS"
            needConfirm="yes"
        fi
    fi

    # Confirm the resolved person before using it, mirroring big_IMDb_xref's
    # gate. Skipped for the multi-match menu path, which already confirmed via
    # selection. Answering "no" skips this person.
    if [[ -n $needConfirm ]] && [[ -n $nconst ]]; then
        printf "%s\t%s\t%s\t%s\n" "$nconst" "$nconstName" "$professions" "$knownFor" >"$TMPFILE"
        printf "\nThese are the results I can process:\n"
        tsvPrint "$TMPFILE"
        if ! waitUntil "$YN_PREF" -Y "Does that look correct?"; then
            continue
        fi
    fi

    # Fetch filmography. The scraper serves from .xref_live_cache when present and
    # scrapes on a miss, so one call is enough -- retrying here just doubled
    # the request rate against IMDb's WAF. Errors are surfaced rather than
    # discarded; a failed scrape is not the same as a person with no credits.
    printf "==> Fetching filmography for %s...\n" "$nconst"
    if ! fgData=$(_scraper filmography "$nconst" 2>"$SCRAPER_ERR"); then
        printf "\n==> Could not fetch filmography for %s:\n" "$nconstName"
        tail -n 2 "$SCRAPER_ERR" | sed 's/^/    /'
        continue
    fi

    roleCount=$(jq '.roles | length' <<<"$fgData" 2>/dev/null)
    roleCount=${roleCount:-0}

    if [[ $roleCount -eq 0 ]]; then
        printf "\n==> No filmography found for %s.\n" "$nconstName"
        continue
    fi

    # Display summary — use name from filmography data (more accurate than search)
    fgName=$(jq -r '.name // empty' <<<"$fgData")
    [[ -n $fgName ]] && nconstName="$fgName"
    # Strip an IMDb disambiguation suffix like "(I)", "(II)" from the
    # filename. A person's own credits page (h1) has a clean name, so this is
    # a no-op when searching by nconst; the suffix only arrives via name
    # search, where IMDb tags same-named people. Cosmetic -- the nconst in the
    # filename already prevents collisions.
    cleanName=$(sd ' *\(I[IVX]*\)$' '' <<<"$nconstName")
    noSpaceName="${cleanName//[[:space:]]/_}"
    filmographyDir="secondary/filmographies"
    mkdir -p "$filmographyDir"

    printf "\n==> Filmography for %s (%s roles)\n" "$nconstName" "$roleCount"

    # Group by job
    jobs=$(jq -r '[.roles[].job // empty] | unique | .[]' <<<"$fgData")
    while IFS= read -r job; do
        [[ -z $job ]] && continue
        jobCount=$(jq --arg j "$job" '[.roles[] | select(.job == $j)] | length' <<<"$fgData")
        [[ $jobCount -eq 0 ]] && continue
        printf "  %-20s %s titles\n" "$job:" "$jobCount"
    done <<<"$jobs"

    # Offer to save
    filmographyMd="$filmographyDir/${noSpaceName}-${nconst}.md"
    printf "\n==> Save to ${BLUE}$filmographyMd${NO_COLOR}?\n"
    if waitUntil "$YN_PREF" -Y "==> Save filmography?"; then
        _generate_filmography_md "$fgData" "$filmographyMd"
        printf "==> Saved.\n"
    fi

    # Offer to add titles to tconst file
    tconsts=$(jq -r '[.roles[].tconst] | unique | .[]' <<<"$fgData")
    tconstCount=$(echo "$tconsts" | rg -c "^tt")
    printf "\n==> This filmography includes %s unique titles.\n" "$tconstCount"

done <"$ALL_TERMS"

loopOrExitP
