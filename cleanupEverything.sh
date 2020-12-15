#!/usr/bin/env bash
#
# Remove all files and directories created by running scripts

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd $DIRNAME
export LC_COLLATE="C"
. functions/define_colors
. functions/define_files
. functions/load_functions

function deleteFiles() {
    printf "Deleting ...\n"
    # Don't quote $@. Globbing needs to take place here.
    rm -rf $ASK $TELL $@
    printf "\n"
}

# Allow switches -v or -i to be passed to the rm command
while getopts ":iv" opt; do
    case $opt in
    i)
        ASK="-i"
        ;;
    v)
        TELL="-v"
        ;;
    \?)
        printf "Ignoring invalid option: -$OPTARG\n\n" >&2
        ;;
    esac
done
shift $((OPTIND - 1))

# Quote filenames so globbing takes place in the "deleteFiles" function,
# i.e. the function is passed the number of parameters seen below, not
# the expanded list which could be quite long.
if ask_YN "Delete primary spreadsheets that contain information on credits, shows, and episodes?" N; then
    deleteFiles "Shows-*.csv" "Credits-*.csv" "Persons-KnownFor*.csv" "AssociatedTitles*.csv"
else
    printf "Skipping...\n"
fi

if ask_YN "Delete smaller files that only contain lists of persons and shows?" N; then
    deleteFiles "LinksToPersons*.csv" "LinksToTitles*.csv" "uniq*.txt"
else
    printf "Skipping...\n"
fi

if ask_YN "Delete all files generated during debugging?" N; then
    deleteFiles "secondary" "diffs*.txt" "baseline" "test_results"
else
    printf "Skipping...\n"
fi

if ask_YN "Delete all the .gz files downloaded from IMDb?" N; then
    deleteFiles "*.tsv.gz"
else
    printf "Skipping...\n"
fi

printf "\n[${RED}Warning${NO_COLOR}] The following files are usually manually created. They are ignored by git.\n\n"

if ask_YN "Delete all manually maintained .tconst and .xlate files?" N; then
    deleteFiles "*.tconst" "*.xlate"
else
    printf "Skipping...\n"
fi
