#!/usr/bin/env bash

# Expand initial tconst IDs in a .tconst file. Add the IMDb Primary Title,
# Original Title, and Date. Sort by Primary Title
#
# Preserve all non-tconst lines, place in the header

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME"
export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

function help() {
    cat <<EOF
augment_tconstFiles.sh -- Modify .tconst files. Add Type, Primary Title, Original Title, Date

      For example, expand:
          tt1606375
          tt1399664
          tt3351208

      To:
          tt1606375   tvSeries      Downton Abbey       Downton Abbey       2010
          tt1399664   tvMiniSeries  The Night Manager   The Night Manager   2016
          tt3582458   tvSeries      Acquitted           Frikjent            2014

USAGE:
    ./augment_tconstFiles.sh [OPTIONS] FILE [FILE...]

OPTIONS:
    -h      Print this message.
    -a      Allow tvEpisodes -- normally they are filtered out
    -i      In place -- overwrite original file
    -y      Yes -- overwrite without asking "OK to overwrite...

EXAMPLES:
    ./augment_tconstFiles.sh Contrib/OPB.tconst
    ./augment_tconstFiles.sh -i Contrib/*.tconst
    ./augment_tconstFiles.sh -iy Contrib/*.tconst
EOF
}

# Don't leave tempfiles around
trap terminate EXIT
#
function terminate() {
    if [ -n "$DEBUG" ]; then
        printf "\nTerminating: $(basename $0)\n" >&2
        printf "Not removing:\n" >&2
        printf "$RESULT $TCONSTS\n" >&2
    else
        rm -rf $RESULT $TCONSTS
    fi
}

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

while getopts ":haiy" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    a)
        ALLOW_EPISODES="yes"
        ;;
    i)
        INPLACE="yes"
        ;;
    y)
        INPLACE="yes"
        DONT_ASK="yes"
        ;;
    \?)
        printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2
        ;;
    esac
done
shift $((OPTIND - 1))

# Make sure prerequisites are satisfied
ensurePrerequisites

# Need some tempfiles
RESULT=$(mktemp)
TCONSTS=$(mktemp)

# Make sure a file was supplied
if [ $# -eq 0 ]; then
    printf "==> [${RED}Error${NO_COLOR}] Please supply a tconst filename on the command line.\n\n" >&2
    exit 1
fi

function copyResults() {
    if [ -n "$ALLOW_EPISODES" ]; then
        cat $RESULT
    else
        rg -wNv "tvEpisode" $RESULT
    fi
}

for file in "$@"; do
    [ -z "$INPLACE" ] && printf "==> $file\n"

    # Gather and preserve all non-tconst lines
    rg -Nv "^tt" "$file" >$RESULT

    # Gather all the lines with tconsts in column 1
    rg -N "^tt" "$file" | cut -f 1 >$TCONSTS

    # Look them up, get fields 1-4,6 and sort by Primary Title
    rg -wNz -f "$TCONSTS" title.basics.tsv.gz | cut -f 1-4,6 |
        perl -p -e 's+\\N++g;' | sort -f -t$'\t' --key=3,3 \
        >>$RESULT

    # Either overwrite or print on stdout
    if [ -z "$INPLACE" ]; then
        copyResults
        printf "\n"
    else
        if [ -z "$DONT_ASK" ]; then
            waitUntil $ynPref -N "OK to overwrite $file?" && copyResults >$file
        else
            copyResults >$file
        fi
    fi
done
