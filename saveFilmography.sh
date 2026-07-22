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

Filmographies are saved as JSON in secondary/filmographies/. You'll have the
opportunity to review results before committing.

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

function terminate() {
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
    else
        rm -f "$ALL_TERMS" "$PERSON_RESULTS" "$NCONST_TERMS" "$TMPFILE" "$FILMOGRAPHY_JSON"
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

# Generate a markdown filmography file from JSON data
_generate_filmography_md() {
    local jsonData="$1"
    local outputFile="$2"

    # Noise patterns to filter from character field (case-insensitive)
    cat >"$outputFile" <<'HEADER'
# Filmography

HEADER

    # Add person name as IMDb link (strip disambiguation suffix from display)
    jq -r '"# [" + (.name | gsub(" ?\\([IVX]+\\)"; "")) + "](https://www.imdb.com/name/" + .nconst + "/)\n"' <<<"$jsonData" >>"$outputFile"

    # Get unique jobs, filtered by rg_sections.rgx whitelist, sorted with actor/actress first
    local allowedJobs
    allowedJobs=$(rg -N '^[^#]' "${DIRNAME}/rg_sections.rgx" 2>/dev/null | tr '\n' '|' | sed 's/|$//')
    jobs=$(jq -r --arg whitelist "$allowedJobs" '
        ($whitelist | split("|")) as $allowed |
        [.roles[].job // empty]
        | unique
        | map(select(. as $j | $allowed | any(test(.; "i"))))
        | map(
            if . == "actor" or . == "actress" then "0_."
            elif . == "director" then "1_."
            elif . == "writer" then "2_."
            elif . == "producer" then "3_."
            else "4_."
            end + .
          )
        | sort
        | map(. [3:])
        | .[]
    ' <<<"$jsonData")

    while IFS= read -r job; do
        [[ -z $job ]] && continue

        local jobCapital
        jobCapital="$(echo "$job" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"

        local isActing=0
        [[ $job == "actor" || $job == "actress" ]] && isActing=1

        # Filter roles for this job, exclude noise
        local filteredRoles
        filteredRoles=$(jq --arg j "$job" '
            .roles[]
            | select(.job == $j)
            | select(.character != "" and .character != null)
            | (.character | ascii_downcase) as $cl |
            # Filter out noise in character field
            select(
              ($cl | startswith("self") | not) and
              ($cl | startswith("special") | not) and
              ($cl | startswith("archive") | not) and
              ($cl | startswith("thanks") | not) and
              ($cl | startswith("gratuitude") | not) and
              ($cl | startswith("appearance") | not) and
              ($cl | startswith("himself") | not) and
              ($cl | startswith("herself") | not) and
              ($cl | startswith("presentator") | not) and
              ($cl | startswith("presenter") | not) and
              ($cl | startswith("tv ") | not) and
              ($cl | startswith("movie") | not) and
              ($cl | startswith("documentary") | not) and
              ($cl | startswith("completed") | not) and
              ($cl | startswith("video") | not) and
              ($cl | startswith("short") | not) and
              ($cl | startswith("uncredited") | not) and
              ($cl | startswith("director") | not) and
              ($cl | startswith("producer") | not) and
              ($cl | startswith("executive") | not) and
              ($cl | startswith("written by") | not) and
              ($cl | startswith("writer") | not) and
              ($cl | startswith("editor") | not) and
              ($cl | startswith("cinematographer") | not) and
              ($cl | startswith("composer") | not) and
              ($cl | startswith("costume") | not) and
              ($cl | startswith("sound") | not) and
              ($cl | startswith("performer") | not)
            )
            | {
                tconst,
                title: (.title // "Unknown"),
                year: (.year // "-"),
                title_type: (.title_type // ""),
                character: (.character // ""),
                episodes: (.episodes // 0)
              }
        ' -r -c <<<"$jsonData")

        [[ -z $filteredRoles ]] && continue

        # Group by tconst to consolidate multiple characters
        local consolidated
        consolidated=$(echo "$filteredRoles" | jq -s '
            group_by(.tconst)
            | map({
                tconst: .[0].tconst,
                title: .[0].title,
                year: ([.[].year | select(. != null and . != "" and . != "-")] | if length > 0 then .[0] else "-" end),
                title_type: .[0].title_type,
                character: ([.[].character] | unique | join(" / ")),
                episodes: ([.[].episodes] | add // 0)
              })
            | sort_by(-(.year | if . == "-" then 0 else (. | split("–")[-1] | split("-")[-1] | tonumber // 0) end))
        ')

        [[ -z $consolidated ]] && continue

        local count
        count=$(echo "$consolidated" | jq 'length')

        # Write section header
        printf "\n## %s (%s)\n\n" "$jobCapital" "$count" >>"$outputFile"

        # Write table
        if [[ $isActing -eq 1 ]]; then
            printf "| Year | Title | Type | Character | Episodes |\n" >>"$outputFile"
            printf "|------|-------|------|-----------|----------:\n" >>"$outputFile"
            echo "$consolidated" | jq -r --arg dash "-" '.[] |
                .episodes as $ep |
                ($ep | if . > 0 then tostring else $dash end) as $epStr |
                "| \(.year) | [\(.title)](https://www.imdb.com/title/\(.tconst)/) | \(.title_type) | \(.character) | \($epStr) |"
            ' >>"$outputFile"
        else
            printf "| Year | Title | Type | Credit |\n" >>"$outputFile"
            printf "|------|-------|------|--------|\n" >>"$outputFile"
            echo "$consolidated" | jq -r --arg dash "-" '.[] |
                .character as $cr |
                ($cr | if . == "" or . == null then $dash else . end) as $crStr |
                "| \(.year) | [\(.title)](https://www.imdb.com/title/\(.tconst)/) | \(.title_type) | \($crStr) |"
            ' >>"$outputFile"
        fi

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
printf "\n"

# Process each search term
while IFS= read -r searchTerm; do
    [[ -z $searchTerm ]] && continue

    if [[ $searchTerm =~ ^nm[0-9]{7,8}$ ]]; then
        nconst="$searchTerm"
        personInfo=$(_scraper person-info "$nconst" 2>/dev/null)
        if [[ -n $personInfo ]] && [[ $personInfo != *"not found"* ]]; then
            nconstName=$(jq -r '.name // empty' <<<"$personInfo")
            printf "%s\t%s\n" "$nconst" "$nconstName" >>"$PERSON_RESULTS"
        fi
    else
        # Search for the person on IMDb
        printf "==> Searching IMDb for \"%s\"...\n" "$searchTerm"
        searchResults=$(_scraper --delay 1 search-person "$searchTerm" 2>/dev/null)
        matchCount=$(jq 'length' <<<"$searchResults")

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

            jq -r '.[] | "\(.nconst)\t\(.name)"' <<<"$searchResults" >"$TMPFILE"
            pickOptions=()
            tabbedOptions=()
            while IFS= read -r line; do
                pickOptions+=("$line")
            done < <(tsvPrint "$TMPFILE")
            pickOptions+=("Skip \"$searchTerm\"" "Quit")

            while IFS= read -r line; do
                tabbedOptions+=("$line")
            done < <(jq -r '.[] | "\(.nconst)\t\(.name)"' <<<"$searchResults")

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
            printf "%s\t%s\n" "$nconst" "$nconstName" >>"$PERSON_RESULTS"
        fi
    fi

    # Fetch filmography if not cached
    fgData=$(_scraper filmography "$nconst" 2>/dev/null)
    roleCount=$(jq '.roles | length' <<<"$fgData")

    if [[ $roleCount -eq 0 ]]; then
        printf "==> Fetching filmography from IMDb...\n"
        _scraper --delay 1 filmography "$nconst" >/dev/null 2>&1
        fgData=$(_scraper filmography "$nconst" 2>/dev/null)
        roleCount=$(jq '.roles | length' <<<"$fgData")
    fi

    if [[ $roleCount -eq 0 ]]; then
        printf "\n==> No filmography found for %s.\n" "$nconstName"
        continue
    fi

    # Display summary — use name from filmography data (more accurate than search)
    fgName=$(jq -r '.name // empty' <<<"$fgData")
    [[ -n $fgName ]] && nconstName="$fgName"
    # Strip IMDb disambiguation suffix like (I), (II), (III)
    cleanName=$(echo "$nconstName" | sed 's/ *(I[IVX]*)$//')
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
    filmographyFile="$filmographyDir/${noSpaceName}-${nconst}.json"
    printf "\n==> Save to ${BLUE}$filmographyFile${NO_COLOR}?\n"
    if waitUntil "$YN_PREF" -Y "==> Save filmography?"; then
        echo "$fgData" >"$filmographyFile"
        printf "==> Saved.\n"

        # Generate markdown
        filmographyMd="$filmographyDir/${noSpaceName}-${nconst}.md"
        _generate_filmography_md "$fgData" "$filmographyMd"
        printf "==> Also saved ${BLUE}$filmographyMd${NO_COLOR}\n"
    fi

    # Offer to add titles to tconst file
    tconsts=$(jq -r '[.roles[].tconst] | unique | .[]' <<<"$fgData")
    tconstCount=$(echo "$tconsts" | rg -c "^tt")
    printf "\n==> This filmography includes %s unique titles.\n" "$tconstCount"

done <"$ALL_TERMS"

loopOrExitP
