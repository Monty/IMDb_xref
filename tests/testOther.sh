#!/usr/bin/env bash
#
# testOther.sh -- Non-interactive report of findOtherShows.sh title searches

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME"/.. || exit

source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
testOther.sh -- Report on findOtherShows.sh searches without any interaction.

Reads the .tsv files given as arguments, takes the search strings from the column
named by -f, and searches title.basics.tsv.gz the way findOtherShows.sh does.
Instead of offering menus it writes one report row per input row, so the results
can be inspected in a spreadsheet.

All search strings are looked up in a single pass over title.basics.tsv.gz, then
each hit is attributed back to the rows whose search string equals the hit's
primary or original title. That is the same comparison ripgrep just made, so the
counts match what findOtherShows.sh would have offered -- but 400 rows cost one
search instead of 400.

A search string that looks like a tconst bypasses rg_types.rgx, exactly as it does
in findOtherShows.sh, so it can return a tvEpisode or short. Those types have no
column of their own, so the type name is reported in the Failed column instead of
Y/N. Title searches keep the type filter, so they only ever report Y or N.

USAGE:
    ./tests/testOther.sh -f FIELD [TSV_FILE...]

OPTIONS:
    -h          Print this message.
    -f FIELD    Source column to search on, 1-4. Required.
                    1  Title
                    2  tconst        (bypasses rg_types.rgx)
                    3  Primary Title
                    4  Alternate Title
    -o FILE     Write the report to FILE. Defaults to testOther-fieldN.tsv

If no files are given, all *_episode_count.tsv in this directory are used.

OUTPUT COLUMNS:
    Fields 1-4  Copied from the source row
    Failed      'N' if the tconst in field 2 was among the matches, else 'Y'.
                A type name when a tconst search returned a type not listed in
                rg_types.rgx.
    Total Hits  Count of matches that were not filtered out
    <types>     One column per type in rg_types.rgx, in the order listed there.
                Adding or removing types changes the report.
    Notes       What the type filter removed, e.g. "4 tvEpisode, 20 short"

EXAMPLES:
    ./tests/testOther.sh -f 4
    ./tests/testOther.sh -f 4 Acorn_episode_count.tsv
    ./tests/testOther.sh -f 3 Acorn_episode_count.tsv BBox_episode_count.tsv
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
ROWS $ROWS
TCONST_TERMS $TCONST_TERMS
TCONST_PATTERNS $TCONST_PATTERNS
TCONST_HITS $TCONST_HITS
SHOWS_TERMS $SHOWS_TERMS
SHOWS_PATTERNS $SHOWS_PATTERNS
SHOWS_RAW $SHOWS_RAW
KEPT $KEPT
FILTERED $FILTERED
EOT
    else
        rm -f "$ROWS" "$TCONST_TERMS" "$TCONST_PATTERNS" "$TCONST_HITS"
        rm -f "$SHOWS_TERMS" "$SHOWS_PATTERNS" "$SHOWS_RAW"
        rm -f "$KEPT" "$FILTERED"
    fi
}

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

while getopts ":hf:o:" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    f)
        fieldNum="$OPTARG"
        ;;
    o)
        outFile="$OPTARG"
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

# The column choice determines the whole report, so insist on being told.
if [[ -z $fieldNum ]]; then
    printf "==> ${RED}Missing${NO_COLOR} -f FIELD: which column holds the search strings?\n\n" >&2
    help
    exit 1
fi
if [[ ! $fieldNum =~ ^[1-4]$ ]]; then
    printf "==> ${RED}Invalid${NO_COLOR} -f %s. FIELD must be 1-4.\n\n" "$fieldNum" >&2
    exit 1
fi

# Make sure prerequisites are satisfied
ensurePrerequisites

# Default to every episode count file in this directory
[[ $# -eq 0 ]] && set -- *_episode_count.tsv

for file in "$@"; do
    if [[ ! -r $file ]]; then
        printf "==> ${RED}Can't${NO_COLOR} read %s. Skipping it.\n" "$file" >&2
    fi
done

outFile="${outFile:-testOther-field${fieldNum}.tsv}"

# Need some tempfiles
ROWS=$(mktemp)
TCONST_TERMS=$(mktemp)
TCONST_PATTERNS=$(mktemp)
TCONST_HITS=$(mktemp)
SHOWS_TERMS=$(mktemp)
SHOWS_PATTERNS=$(mktemp)
SHOWS_RAW=$(mktemp)
KEPT=$(mktemp)
FILTERED=$(mktemp)

# Collect one line per input row: the four source fields, plus the search string
# taken from field $fieldNum. Each file's header row is dropped. The search
# string travels in a 6th column so the join below uses exactly the value that
# was searched for, rather than re-reading the source field and hoping it agrees.
true >"$ROWS"
for file in "$@"; do
    [[ -r $file ]] || continue
    awk -F"\t" -v n="$fieldNum" '
        { gsub(/\r/, "") }
        FNR == 1 { next }
        {
            for (i = 1; i <= 4; i++) f[i] = (i <= NF ? $i : "")
            s = (n <= NF ? $n : "")
            gsub(/^[[:space:]]+/, "", s)
            gsub(/[[:space:]]+$/, "", s)
            printf "%s\t%s\t%s\t%s\t%s\n", f[1], f[2], f[3], f[4], s
        }
    ' "$file" >>"$ROWS"
done

numRows=$(sed -n '$=' "$ROWS")
if [[ $numRows -eq 0 ]]; then
    printf "==> ${RED}No${NO_COLOR} data rows found in: %s\n" "$*" >&2
    exit 1
fi

# Get title.basics.tsv.gz file size - should already exist but make sure...
num_TB="$(rg -N title.basics.tsv.gz "$numRecordsFile" 2>/dev/null | cut -f 2)"
[[ -z $num_TB ]] && num_TB="$(rg -cz "^t" title.basics.tsv.gz)"

# Split into two groups so we can process them differently, exactly as
# findOtherShows.sh does. Repeated search strings collapse into one pattern, so
# every row that asked for the same title shares the resulting set of hits.
#
# Empty search strings are dropped rather than searched. An empty term would
# become the pattern "\t\t", which matches any record with two adjacent tabs,
# so a blank cell would report hits for a show it has nothing to do with. The
# row still appears in the report, with no hits and Failed set to Y.
cut -f 5 "$ROWS" | rg -v '^$' | rg -wN "^tt[0-9]{7,8}" | sort -fu >"$TCONST_TERMS"
cut -f 5 "$ROWS" | rg -v '^$' | rg -wNv "^tt[0-9]{7,8}" | sort -fu >"$SHOWS_TERMS"

printf "==> Searching %s records for %s show titles and %s tconst IDs, from %s rows:\n" \
    "$num_TB" "$(wc -l <"$SHOWS_TERMS" | tr -d ' ')" \
    "$(wc -l <"$TCONST_TERMS" | tr -d ' ')" "$numRows" >&2

# Reconstitute the search patterns with column guards, keeping the two kinds in
# separate files -- they are filtered differently below. The escaping matches
# findOtherShows.sh so this report reflects what that script really matches.
perl -p -e 's/^/^/; s/$/\\t/;' "$TCONST_TERMS" >"$TCONST_PATTERNS"
perl -p -e 's/^/\\t/; s/$/\\t/;' "$SHOWS_TERMS" | sed 's+[()?]+\\&+g' >"$SHOWS_PATTERNS"

# One pass over the dataset for each kind of pattern.
if [[ -s $TCONST_PATTERNS ]]; then
    rg -NzSI -f "$TCONST_PATTERNS" title.basics.tsv.gz >"$TCONST_HITS" || true
else
    true >"$TCONST_HITS"
fi

if [[ -s $SHOWS_PATTERNS ]]; then
    rg -NzSI -f "$SHOWS_PATTERNS" title.basics.tsv.gz >"$SHOWS_RAW" || true
    # A tconst names one exact title, so it bypasses rg_types.rgx. A show title
    # is a guess that can match thousands of episode rows, so it keeps the
    # filter. The filter tests field 2 rather than the whole line, so a title
    # such as "Home Video" can't pass itself off as a type.
    awk -F"\t" 'NR == FNR { types[$0]; next } $2 in types' \
        rg_types.rgx "$SHOWS_RAW" >"$KEPT"
    awk -F"\t" 'NR == FNR { types[$0]; next } !($2 in types)' \
        rg_types.rgx "$SHOWS_RAW" >"$FILTERED"
else
    true >"$SHOWS_RAW"
    true >"$KEPT"
    true >"$FILTERED"
fi

# Reduce to the columns the join needs: tconst, type, primary, original, year
for file in "$KEPT" "$FILTERED"; do
    cut -f 1-4,6 "$file" | perl -p -e 's+\\N++g;' >"$file.trim"
    mv "$file.trim" "$file"
done
cut -f 1,2 "$TCONST_HITS" >"$TCONST_HITS.trim"
mv "$TCONST_HITS.trim" "$TCONST_HITS"

# Join the hits back onto the source rows. A hit belongs to a row when that
# row's search string equals the hit's primary or original title, which is the
# same comparison ripgrep made -- -S keeps the search case sensitive.
#
# A search string that is a tconst is answered from its own single row, which
# never went through the type filter, so an unlisted type has nowhere to be
# counted and gets named in the Failed column instead.
awk -F"\t" -v OFS="\t" \
    -v TF="rg_types.rgx" -v SF="$SHOWS_TERMS" -v CF="$TCONST_TERMS" \
    -v KF="$KEPT" -v FF="$FILTERED" -v THF="$TCONST_HITS" -v RF="$ROWS" '
    # Types define the report columns and the order they appear in.
    FILENAME == TF { if (length($0) > 0) { order[++nt] = $0; isType[$0] = nt } next }

    # Which search strings were asked for, so hits can be attributed.
    FILENAME == SF { showTerm[$0] = 1; next }
    FILENAME == CF { tconstTerm[$0] = 1; next }

    # Hits that survived the type filter. A hit whose primary and original title
    # were both asked for is counted once for each, since each row searched for
    # its own string and would have been offered this same result.
    FILENAME == KF {
        if ($3 in showTerm) { kept[$3]++; typeHits[$3, $2]++; found[$3, $1] = 1 }
        if ($4 != $3 && $4 in showTerm) {
            kept[$4]++; typeHits[$4, $2]++; found[$4, $1] = 1
        }
        if (!($3 in showTerm) && !($4 in showTerm)) orphans++
        next
    }

    # Hits the type filter removed, tallied per search string in the order the
    # types first appear, since awk for-in order is unspecified.
    FILENAME == FF {
        if ($3 in showTerm) tally($3, $2)
        if ($4 != $3 && $4 in showTerm) tally($4, $2)
        if (!($3 in showTerm) && !($4 in showTerm)) orphans++
        next
    }

    # A tconst bypassed the filter, so keep its type whatever it is.
    FILENAME == THF { tconstType[$1] = $2; next }

    FILENAME == RF {
        if (!headerPrinted) {
            line = "Title\ttconst\tPrimary Title\tAlternate Title\tFailed\tTotal Hits"
            for (i = 1; i <= nt; i++) line = line "\t" order[i]
            print line "\tNotes"
            headerPrinted = 1
        }

        s = $5
        failed = "Y"
        total = 0
        for (i = 1; i <= nt; i++) cnt[i] = 0

        if (s in tconstTerm) {
            # Answered by its own record, so it cannot be missed unless IMDb
            # has no such tconst. Its type may be one the report has no
            # column for, which is worth naming rather than leaving blank.
            if (s in tconstType) {
                total = 1
                failed = "N"
                if (tconstType[s] in isType) cnt[isType[tconstType[s]]] = 1
                else failed = tconstType[s]
            }
        } else {
            total = (s in kept ? kept[s] : 0)
            for (i = 1; i <= nt; i++) {
                key = s SUBSEP order[i]
                if (key in typeHits) cnt[i] = typeHits[key]
            }
            if (total > 0 && ((s SUBSEP $2) in found)) failed = "N"
            notes = filteredOut(s)
        }

        line = $1 OFS $2 OFS $3 OFS $4 OFS failed OFS total
        for (i = 1; i <= nt; i++) line = line OFS (cnt[i] > 0 ? cnt[i] : "")
        print line OFS notes
        next
    }

    END {
        if (orphans > 0)
            printf "==> Warning: %s hits matched no search string exactly. " \
                "The report may under-count them.\n", orphans >"/dev/stderr"
    }

    function tally(title, type) {
        filteredCount[title, type]++
        if (!((title, type) in filteredTallied)) {
            filteredTallied[title, type] = ++filteredKinds[title]
            filteredKind[title, filteredKinds[title]] = type
        }
    }

    function filteredOut(title,    i, k, t, out) {
        k = filteredKinds[title]
        if (k == 0) return ""
        for (i = 1; i <= k; i++) {
            t = filteredKind[title, i]
            out = out (i > 1 ? ", " : "") filteredCount[title, t] " " t
        }
        return out "."
    }
' rg_types.rgx "$SHOWS_TERMS" "$TCONST_TERMS" "$KEPT" "$FILTERED" "$TCONST_HITS" "$ROWS" \
    >"$outFile"

numFailed=$(awk -F"\t" 'NR > 1 && $5 == "Y"' "$outFile" | wc -l | tr -d ' ')
printf "==> Wrote %s rows to ${BLUE}%s${NO_COLOR}. %s failed to find their tconst.\n" \
    "$numRows" "$outFile" "${numFailed:-0}" >&2
