#!/usr/bin/env bash
#
# List other shows all principal cast members are in
# Uses the Playwright-based scraper instead of .gz database files.

DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
findOtherShows.sh -- List other shows that principal cast members are found in.

Search IMDb titles for one show name or tconst ID. List principal cast members
who appear in more than one cached show. Use -n to limit number of results.

USAGE:
    ./findOtherShows.sh [TCONST] [SHOW TITLE]

OPTIONS:
    -h      Print this message.
    -l      Use $PAGER to list results a page at a time.
    -m      Maximum matches for a show title allowed in menu, defaults to 25.
    -n      Number of principal cast members to process, 0 = all, defaults to 15.
    -e      Minimum episodes for cast members in the source show, defaults to 1.
    -r      Maximum rank of cast members in other shows to list, 0 = all, defaults to 50

EXAMPLES:
    ./findOtherShows.sh
    ./findOtherShows.sh "The Crown"
    ./findOtherShows.sh tt1399664
    ./findOtherShows.sh -n 10 Broadchurch
    ./findOtherShows.sh -n 50 -e 10 Broadchurch
EOF
}

trap terminate EXIT
TMPFILE=""
ALL_TERMS=""
TCONST_LIST=""
SHOW_NAMES=""
CAST_CSV=""
OTHERS_CSV=""
RESULTS=""
SCRAPER_ERR=""

function terminate() {
    trimHistory -m 20 "$favoritesFile"
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
    else
        rm -f "$ALL_TERMS" "$TCONST_LIST" "$SHOW_NAMES"
        rm -f "$CAST_CSV" "$OTHERS_CSV" "$RESULTS" "$TMPFILE" "$SCRAPER_ERR"
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

while getopts ":hlm:n:e:r:" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    l) usePager=1 ;;
    m) maxMenuSize="$OPTARG" ;;
    n) maxCast="$OPTARG" ;;
    e) minEpisodesSource="$OPTARG" ;;
    r) maxRank="$OPTARG" ;;
    \?) printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2 ;;
    :)
        printf "Option -$OPTARG requires an argument.\n" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

maxCast="${maxCast:-15}"
maxRank="${maxRank:-50}"
minEpisodesSource="${minEpisodesSource:-1}"

ALL_TERMS=$(mktemp)
TCONST_LIST=$(mktemp)
SHOW_NAMES=$(mktemp)
CAST_CSV=$(mktemp)
OTHERS_CSV=$(mktemp)
RESULTS=$(mktemp)
TMPFILE=$(mktemp)
SCRAPER_ERR=$(mktemp)

# Make sure a search term is supplied
if [[ $# -eq 0 ]]; then
    read -r -p "Enter a show name or tconst ID: " searchTerm </dev/tty
    tr -ds '"' '[:space:]' <<<"$searchTerm" >"$ALL_TERMS"
    if [[ ! -s $ALL_TERMS ]]; then
        loopOrExitP
    fi
    printf "\n"
else
    printf "%s\n" "$1" >"$ALL_TERMS"
fi

printf "==> Searching for:\n"
cat "$ALL_TERMS"

_scraper rebuild-index >/dev/null 2>&1

# Process search term to get tconst
tconst=""
while IFS= read -r searchTerm; do
    [[ -z $searchTerm ]] && continue

    # Reset per term. needConfirm gates the "Does that look correct?" prompt:
    # set on the two paths that resolve a tconst with no user interaction -- a
    # typed tconst ID, or a name with exactly one match. The multi-match menu is
    # its own confirmation. Resetting tconst also stops a menu "Skip" from
    # reusing the previous term's tconst.
    needConfirm=""
    tconst=""

    if [[ $searchTerm =~ ^tt[0-9]{7,8}$ ]]; then
        tconst="$searchTerm"
        needConfirm="yes"
    else
        printf "==> Searching IMDb for \"%s\"...\n" "$searchTerm"
        # Capture stderr so a scraper failure (e.g. a WAF challenge) is
        # reported instead of being silently reinterpreted as "no matches".
        if ! searchResults=$(_scraper --delay 1 search-title "$searchTerm" 2>"$SCRAPER_ERR"); then
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
            if [[ $matchCount -ge ${maxMenuSize:-25} ]]; then
                if waitUntil "$YN_PREF" -Y "Found $matchCount matches. Skip?"; then
                    continue
                fi
            fi
            printf "\nI found %s matches for \"%s\"\n" "$matchCount" "$searchTerm"

            jq -r '.[] | "\(.tconst)\t\(.title)\t\(.year // "n/a")\t\(.types | join(", "))"' <<<"$searchResults" >"$TMPFILE"
            pickOptions=()
            tabbedOptions=()
            while IFS= read -r line; do
                pickOptions+=("$line")
            done < <(tsvPrint "$TMPFILE")
            pickOptions+=("Skip \"$searchTerm\"" "Quit")

            while IFS= read -r line; do
                tabbedOptions+=("$line")
            done < <(jq -r '.[] | "\(.tconst)\t\(.title)\t\(.year // "n/a")\t\(.types | join(", "))"' <<<"$searchResults")

            PS3="Select a number from 1-${#pickOptions[@]}, or type 'q(uit)': "
            COLUMNS=40
            select pickMenu in "${pickOptions[@]}"; do
                if [[ $REPLY -ge 1 ]] 2>/dev/null && [[ $REPLY -le ${#pickOptions[@]} ]]; then
                    case "$pickMenu" in
                    Skip*) break ;;
                    Quit) loopOrExitP ;;
                    *)
                        tconst=$(cut -f1 <<<"${tabbedOptions[REPLY - 1]}")
                        break
                        ;;
                    esac
                else
                    case "$REPLY" in [Qq]*) loopOrExitP ;; esac
                fi
            done </dev/tty
        else
            tconst=$(jq -r '.[0].tconst' <<<"$searchResults")
            needConfirm="yes"
        fi
    fi

    # Ensure we have full credits with cast data
    # Check both title info AND cast — title-basics populates the index without cast
    castCheck=$(_scraper cast-for-show "$tconst" 2>/dev/null)
    titleInfo=$(_scraper title-info "$tconst" 2>/dev/null)
    if [[ -z $titleInfo ]] || [[ $titleInfo == *"not found"* ]] || [[ -z $castCheck ]] || [[ $castCheck == "[]" ]]; then
        printf "==> Fetching full credits...\n"
        _scraper --delay 1 full-credits "$tconst" >/dev/null 2>&1
        _scraper rebuild-index >/dev/null 2>&1
    fi

    titleInfo=$(_scraper title-info "$tconst" 2>/dev/null)
    showName=$(jq -r '.title' <<<"$titleInfo")

    # Confirm the resolved title before using it, mirroring big_IMDb_xref's gate.
    # The multi-match menu already confirmed via selection, so it skips this.
    if [[ -n $needConfirm ]]; then
        printf "imdb.com/title/%s\t%s\t%s\t%s\t%s\n" \
            "$tconst" \
            "$(jq -r '.types[0] // ""' <<<"$titleInfo")" \
            "$showName" \
            "$(jq -r '.original_title // ""' <<<"$titleInfo")" \
            "$(jq -r '.year // ""' <<<"$titleInfo")" >"$TMPFILE"
        printf "\nThese are the results I can process:\n"
        tsvPrint "$TMPFILE"
        if ! waitUntil "$YN_PREF" -Y "Does that look correct?"; then
            continue
        fi
    fi

    printf "%s\t%s\n" "$tconst" "$showName" >>"$SHOW_NAMES"
    printf "%s\n" "$tconst" >>"$TCONST_LIST"
done <"$ALL_TERMS"

if [[ -z $tconst ]]; then
    printf "\n==> I didn't find ${RED}any${NO_COLOR} matching shows.\n"
    loopOrExitP
fi

# Get cast for the show
castArgs=("cast-for-show" "$tconst" "--actors-only" "--min-episodes" "$minEpisodesSource")
[[ $maxCast -gt 0 ]] && castArgs+=("--limit" "$maxCast")
castData=$(_scraper "${castArgs[@]}" 2>/dev/null)

castCount=$(jq 'length' <<<"$castData")
if [[ $castCount -eq 0 ]]; then
    printf "==> No cast found for this show.\n"
    loopOrExitP
fi

# For each cast member, find their other shows
true >"$RESULTS"
while IFS= read -r actorLine; do
    actorNconst=$(jq -r '.nconst' <<<"$actorLine")

    # Get all shows for this actor from the index
    actorShows=$(_scraper shows-for-person "$actorNconst" 2>/dev/null)
    # Other cached shows they're in (excluding the one we searched)
    otherShows=$(jq --arg tc "$tconst" '[.[] | select(.tconst != $tc) | select(.job == "actor")]' <<<"$actorShows")
    otherCount=$(jq 'length' <<<"$otherShows")

    if [[ $otherCount -gt 0 ]]; then
        # Anchor each person on the show you searched (linked to the person),
        # then their other shows (linked to each title) -- mirrors big_IMDb_xref.
        {
            jq -r --arg tc "$tconst" \
                '[.[] | select(.tconst == $tc) | select(.job == "actor")][0] // empty
                 | "\(.name)\t\(.job)\t\(.title)\t\(.episodes | tostring)\t\(.character // "")\timdb.com/name/\(.nconst)"' \
                <<<"$actorShows"
            jq -r '.[] | "\(.name)\t\(.job)\t\(.title)\t\(.episodes | tostring)\t\(.character // "")\timdb.com/title/\(.tconst)"' \
                <<<"$otherShows"
            printf '%s\n' "---"
        } >>"$RESULTS"
    fi
done < <(jq -c '.[]' <<<"$castData")

# Check if we found anything
rg -v "^---" "$RESULTS" >"$TMPFILE" 2>/dev/null || true
if [[ ! -s $TMPFILE ]]; then
    if [[ $maxCast -gt 0 ]]; then
        printf "==> None of the top $maxCast cast members appear in other cached shows.\n"
    else
        printf "==> None of the cast members appear in other cached shows.\n"
    fi
    loopOrExitP
fi

showName=$(cut -f2 <"$SHOW_NAMES")
CAST_SPREADSHEET="ShowsWithActorsFrom-${showName//[[:space:]]/_}.csv"
printf "==> The shared cast list will be saved in ${BLUE}$CAST_SPREADSHEET${NO_COLOR}\n"

# Build the table once (header + data rows, no --- separators) and use it for
# both the .csv and the on-screen listing, so they match and carry the header.
{
    printf "Person\tJob\tShow Title\tEpisodes\tCharacter Name\tLink\n"
    rg -v '^---' "$RESULTS"
} >"$CAST_SPREADSHEET"

if [[ $maxCast -gt 0 ]]; then
    printf "==> Top $maxCast cast members that appear in other cached shows:\n"
else
    printf "==> Cast members that appear in other cached shows:\n"
fi

if [[ -n $usePager ]]; then
    tsvPrint -c 1 "$CAST_SPREADSHEET" | ${PAGER:-less}
else
    tsvPrint -c 1 "$CAST_SPREADSHEET"
fi

loopOrExitP
