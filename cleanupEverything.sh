#!/usr/bin/env bash
# Remove all files and directories created by running scripts

printf "Answer y to delete, anything else to skip. Deletion cannot be undone!\n"
printf "\n"

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
        printf "Ignoring invalid option: -$OPTARG\n" >&2
        ;;
    esac
done
shift $((OPTIND - 1))

# Ask $1 first, shift, then rm $@
function yesnodelete() {
    read -r -p "Delete $1? [y/N] " YESNO
    shift
    if [ "$YESNO" != "y" ]; then
        printf "Skipping...\n"
    else
        printf "Deleting ...\n"
        # Don't quote $@. Globbing needs to take place here.
        rm -rf $ASK $TELL $@
    fi
    printf "\n"
}

# Quote filenames so globbing takes place in the "rm" command itself,
# i.e. the function is passed the number of parameters seen below, not
# the expanded list which could be quite long.
yesnodelete "all Shows spreadsheets" "Shows-*.csv"
yesnodelete "all Credits spreadsheets" "Credits-*.csv" "Persons-KnownFor*.csv" "LinksToPersons*.csv" \
    "LinksToTitles*.csv" "AssociatedTitles*.csv"
yesnodelete "all uniq files" "uniq*.txt"
yesnodelete "all secondary spreadsheet files" "secondary"
yesnodelete "all diff results" "diffs*.txt"
yesnodelete "all diff baselines" "baseline" "test_results"
yesnodelete "all downloaded IMDB .gz files" "title.basics.tsv.gz" "title.episode.tsv.gz" \
    "title.principals.tsv.gz" "name.basics.tsv.gz"

printf "[Warning] The following files are usually manually created. They are ignored by git.\n\n"

yesnodelete "all user-created .tconst files" "*.tconst"
yesnodelete "all user-created .xlate files" "*.xlate"
