#!/usr/bin/env bash
# Save the current days "generateXrefData.sh -v" debug results as a baseline
# so we can check for changes in the future
#
# -d DATE picks a different date
# -v does verbose copying

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd $DIRNAME
export LC_COLLATE="C"
source functions/define_colors
source functions/define_files
source functions/load_functions

# Create a timestamp
DATE="$(date +%y%m%d)"

# Allow user to override DATE
while getopts ":d:v" opt; do
    case $opt in
    d)
        DATE="$OPTARG"
        ;;
    v)
        VERBOSE="-v"
        ;;
    \?)
        printf "Ignoring invalid option: -$OPTARG\n\n" >&2
        ;;
    :)
        printf "Option -$OPTARG requires a 'date' argument such as $DATE\n\n" >&2
        exit 1
        ;;
    esac
done

WORK="secondary"
BASE="baseline"
mkdir -p $WORK $BASE

if [ ! -e "$WORK/tconst-$DATE.txt" ]; then
    printf '==> Missing debug files. Run "./generateXrefData.sh -v" then re-run this script.\n'
    exit 1
fi

# Manually maintained skip episodes file
cp -p $VERBOSE skipEpisodes.example $BASE/skipEpisodes.example

# Copy  files
cp -p $VERBOSE $WORK/tconst-$DATE.txt $BASE/tconst.txt
cp -p $VERBOSE $WORK/nconst-$DATE.txt $BASE/nconst.txt
cp -p $VERBOSE $WORK/raw_shows-$DATE.csv $BASE/raw_shows.csv
cp -p $VERBOSE $WORK/raw_persons-$DATE.csv $BASE/raw_persons.csv
cp -p $VERBOSE $WORK/tconst_known-$DATE.txt $BASE/tconst_known.txt
cp -p $VERBOSE $WORK/tconst-episodes-$DATE.txt $BASE/tconst-episodes.csv

cp -p $VERBOSE uniqTitles-$DATE.txt $BASE/uniqTitles.txt
cp -p $VERBOSE uniqCharacters-$DATE.txt $BASE/uniqCharacters.txt
cp -p $VERBOSE uniqPersons-$DATE.txt $BASE/uniqPersons.txt

cp -p $VERBOSE Shows-Episodes-$DATE.csv $BASE/Shows.csv
cp -p $VERBOSE Credits-Show-$DATE.csv $BASE/Credits-Show.csv
cp -p $VERBOSE Credits-Person-$DATE.csv $BASE/Credits-Person.csv
cp -p $VERBOSE Persons-KnownFor-$DATE.csv $BASE/Persons-KnownFor.csv
cp -p $VERBOSE LinksToPersons-$DATE.csv $BASE/LinksToPersons.csv
cp -p $VERBOSE LinksToTitles-$DATE.csv $BASE/LinksToTitles.csv
cp -p $VERBOSE AssociatedTitles-$DATE.csv $BASE/AssociatedTitles.csv
