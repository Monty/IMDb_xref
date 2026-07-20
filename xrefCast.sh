#!/usr/bin/env bash
#
# Find common cast & crew members between multiple shows
# Uses the scraper index instead of .gz-based CSV files.

DIRNAME=$(dirname "$0")
cd "$DIRNAME" || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
xrefCast.sh -- Cross-reference shows, actors, and characters using scraper data.

If you don't enter a search term on the command line, you'll be prompted for one.

USAGE:
    ./xrefCast.sh [OPTIONS] [-f SEARCH_FILE] [SEARCH_TERM ...]

OPTIONS:
    -h      Print this message.
    -p      Principal -- Only print principal cast section.
    -d      Duplicates -- Only list cast & crew found in more than one show
    -f      File -- Query a specific file rather than the index.
    -i      Print info about any files that are searched.
    -n      No menu - don't bring up the top-level menu upon exiting.

EXAMPLES:
    ./xrefCast.sh "Olivia Colman"
    ./xrefCast.sh "Queen Elizabeth II" "Princess Diana"
    ./xrefCast.sh "The Crown"
    ./xrefCast.sh -d "The Night Manager" "The Crown" "The Durrells"
    ./xrefCast.sh -dn "Elizabeth Debicki"
EOF
}

trap terminate EXIT
TMPFILE=""
SEARCH_TERMS=""
ALL_NAMES=""
MULTIPLE_NAMES=""

function terminate() {
    if [[ -n $DEBUG ]]; then
        printf "\nTerminating: $(basename "$0")\n" >&2
    else
        rm -f "$TMPFILE" "$SEARCH_TERMS" "$ALL_NAMES" "$MULTIPLE_NAMES"
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
    [[ -n $noLoop ]] || [[ -n $NO_MENUS ]] && exit
    exec ./start.command
}

_scraper() {
    uv run --directory scraper python cli.py "$@"
}

while getopts ":f:hpdin" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    p) PRINCIPAL_CAST_ONLY="yes" ;;
    d) MULTIPLE_NAMES_ONLY="yes" ;;
    f) SEARCH_FILE="$OPTARG" ;;
    i) INFO="yes" ;;
    n) noLoop="yes" ;;
    \?) printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2 ;;
    :)
        printf "==> Option -$OPTARG requires an argument.\n\n" >&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

TMPFILE=$(mktemp)
SEARCH_TERMS=$(mktemp)
ALL_NAMES=$(mktemp)
MULTIPLE_NAMES=$(mktemp)

# If a SEARCH_FILE was specified, use it directly
if [[ -n $SEARCH_FILE ]]; then
    if [[ ! -e $SEARCH_FILE ]]; then
        printf "==> [${RED}Error${NO_COLOR}] Missing search file: $SEARCH_FILE\n\n" >&2
        loopOrExitP
    fi
    USE_FILE="yes"
else
    USE_FILE="no"
    # Ensure index exists
    _scraper rebuild-index >/dev/null 2>&1
fi

# Make sure a search term is supplied
if [[ $# -eq 0 ]]; then
    if [[ -n $USE_FILE ]]; then
        cat <<EOF
==> Cross-reference using: $SEARCH_FILE

Only one search term per line. Enter a blank line to finish.
EOF
    else
        cat <<EOF
==> I can cross-reference shows, actors, and the characters they portray
    using the local IMDb cache. Use ./scraper rebuild-index to update it.

Only one search term per line. Enter a blank line to finish.
EOF
    fi
    while read -r -p "Enter a show, actor, or character: " searchTerm; do
        [[ -z $searchTerm ]] && break
        tr -d '"' <<<"$searchTerm" >>"$TMPFILE"
    done </dev/tty
    if [[ ! -s $TMPFILE ]]; then
        if [[ -z $USE_FILE ]]; then
            if waitUntil "$YN_PREF" -N \
                "Would you like to search for Money Heist cast as an example?"; then
                printf "Money Heist\n" >>"$TMPFILE"
                printf "\n"
            else
                loopOrExitP
            fi
        else
            loopOrExitP
        fi
    else
        printf "\n"
    fi
else
    for a in "$@"; do
        printf "%s\n" "$a" >>"$TMPFILE"
    done
fi

sort -fu "$TMPFILE" >"$SEARCH_TERMS"

# Let us know what we're searching for
printf "==> Searching for:\n"
cat "$SEARCH_TERMS"
printf "\n"

# Search the index or file
true >"$TMPFILE"

if [[ $USE_FILE == "yes" ]]; then
    # Search the provided file (legacy compatibility)
    PTAB='%s\t%s\t%s\t%s\n'
    if [[ -n "$(rg -wNzSI -c -f "$SEARCH_TERMS" "$SEARCH_FILE")" ]]; then
        awk -F "\t" -v PF="$PTAB" '{printf(PF, $1,$5,$2,$6)}' "$SEARCH_FILE" |
            rg -wNzSI --color always -f "$SEARCH_TERMS" |
            perl -p -e 's+\tactress\t+\tactor\t+;' |
            sort -f -t$'\t' --key=2,2 --key=1,1 --key=3,3 -fu >"$TMPFILE"
    fi
else
    # Search the index
    while IFS= read -r term; do
        [[ -z $term ]] && continue
        queryArgs=("query" "$term" "--index-file" "cast-by-person.jsonl")
        # FULLCAST: if numeric, limit results per term
        if [[ -n $FULLCAST ]] && [[ $FULLCAST -eq $FULLCAST ]] 2>/dev/null; then
            queryArgs+=("--limit" "$FULLCAST")
        fi
        _scraper "${queryArgs[@]}" 2>/dev/null |
            jq -r '.[] | "\(.name)\t\(.job)\t\(.title)\t\(.character)"' >>"$TMPFILE"
    done <"$SEARCH_TERMS"
    sort -fu "$TMPFILE" -o "$TMPFILE"
fi

# Any results?
if [[ ! -s $TMPFILE ]]; then
    printf "==> I didn't find ${RED}any${NO_COLOR} matching records.\n"
    printf "    Check the \"Searching for:\" section above.\n"
    loopOrExitP
fi

numAll=$(cut -f1 "$TMPFILE" | sort -fu | sed -n '$=')

# Save ALL_NAMES
cp "$TMPFILE" "$ALL_NAMES"

# Find duplicates — names appearing in more than one show
awk -F "\t" '{if($1==f[1]&&$3!=f[3]) {print f[0]; print $0} split($0,f)}' "$TMPFILE" |
    sort -fu | sort -f -t$'\t' -k 2,2 -k 1,1 -k 3,3 >"$MULTIPLE_NAMES"

if [[ ! -s $MULTIPLE_NAMES ]]; then
    numMultiple="0"
else
    numMultiple=$(cut -f1 "$TMPFILE" | sort -f | uniq -d | sed -n '$=')
fi

# If interactive and we have duplicates, ask user
if [[ -z $noLoop ]] && [[ -z $MULTIPLE_NAMES_ONLY ]] &&
    [[ -z $PRINCIPAL_CAST_ONLY ]] && [[ $numMultiple -ne 0 ]]; then
    printf "\n==> I found $numAll results. $numMultiple are in more than one show.\n"
    waitUntil "$YN_PREF" -N "Should I only print those $numMultiple?" &&
        MULTIPLE_NAMES_ONLY="yes"
fi

# Print all results unless duplicates-only
if [[ -z $MULTIPLE_NAMES_ONLY ]]; then
    printf "\n==> Results in alphabetical order (Name|Job|Show|Role):\n"
    tsvPrint -n "$ALL_NAMES"
fi

[[ -n $PRINCIPAL_CAST_ONLY ]] && loopOrExitP

# Print duplicates
if [[ $numMultiple -eq 0 ]]; then
    if [[ -n $MULTIPLE_NAMES_ONLY ]]; then
        printf "\n==> No cast or crew members listed in more than one show.\n"
    fi
else
    printf "\n==> Cast & crew listed in more than one show (Name|Job|Show|Role):\n"
    tsvPrint -n "$MULTIPLE_NAMES"
fi

loopOrExitP
