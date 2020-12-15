#!/usr/bin/env bash
#
# Expand the IDs in a .tconst file to add IMDb Primary and Original Titles and sort by Primary Title
#
# Preserve all non-tconst lines into a header

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd $DIRNAME
export LC_COLLATE="C"
. functions/define_colors
. functions/define_files
. functions/load_functions

function help() {
    cat <<EOF
Expand the IDs in .tconst files to add Type, Primary Title, and Original Title

      For example, expand:
          tt1606375
          tt1399664
          tt3351208

      To:
          tt1606375	tvSeries	Downton Abbey	Downton Abbey
          tt1399664	tvMiniSeries	The Night Manager	The Night Manager
          tt3351208	tvMovie	Two Little Girls in Blue	Deux petites filles en bleu

USAGE:
    ./augment_tconstFiles.sh [OPTIONS] FILE [FILE...]

OPTIONS:
    -h      Print this message.
    -i      In place -- overwrite original file
    -y      Yes -- skip asking "OK to overwrite...

EXAMPLES:
    ./augment_tconstFiles.sh Contrib/OPB.tconst
    ./augment_tconstFiles.sh -i Contrib/*.tconst
    ./augment_tconstFiles.sh -iy Contrib/*.tconst

EOF
}

# Don't leave tempfiles around
trap "rm -rf $TMPFILE $SEARCH_TERMS" EXIT

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    printf "\nCtrl-C detected. Exiting.\n" >&2
    exit 130
}

while getopts ":hiy" opt; do
    case $opt in
    h)
        help
        exit
        ;;
    i)
        INPLACE="yes"
        ;;
    y)
        SKIP="yes"
        ;;
    \?)
        printf "==> Ignoring invalid option: -$OPTARG\n\n" >&2
        ;;
    esac
done
shift $((OPTIND - 1))

# Need some tempfiles
RESULT=$(mktemp)
TCONSTS=$(mktemp)

# Make sure a file was supplied
if [ $# -eq 0 ]; then
    printf "==> [Error] Please supply a tconst filename on the command line.\n\n" >&2
    exit 1
fi

for file in "$@"; do
    [ -z "$INPLACE" ] && printf "==> $file\n"

    # Gather and preserve all non-tconst lines
    rg -Nv "^tt" "$file" >$RESULT

    # Gather all the lines with tconsts in column 1
    rg -Ne "^tt" "$file" | cut -f 1 >$TCONSTS

    # Look them up, get fields 1-4, and sort by Primary Title
    rg -wNz -f "$TCONSTS" title.basics.tsv.gz | cut -f 1-4 |
        sort -f --field-separator=$'\t' --key=3,3 >>$RESULT

    # Either overwrite or print on stdout
    if [ -n "$INPLACE" ]; then
        if [ -n "$SKIP" ]; then
            cp $RESULT $file
        else
            read -r -p "OK to overwrite $file? [y/N] " YESNO
            if [ "$YESNO" == "y" ]; then
                cp $RESULT $file
            fi
        fi
    else
        cat $RESULT
        printf "\n"
    fi
done
