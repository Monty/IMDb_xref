#!/usr/bin/env bash
# Download needed files from IMDb, even if they already exist
#
# See https://www.imdb.com/interfaces/ for a description of IMDb Datasets

# Keep track of elapsed time
SECONDS=0

# Need some configuration variables
scriptName="$(basename $0)"
durationFile=".xref_durations"
configFile=".xref_config"
touch $durationFile $configFile

# Function to save execution time and duration
. functions/saveDurations.function
# Function to limit the number of durations kept
. functions/trimDurations.function

# Save the duration of this script in a tab separated file and exit.
#    Script Name          Timestamp            Date String               Duration
# generateXrefData.sh   201210.202416   Thu Dec 10 20:24:16 PST 2020    16 seconds.
function terminate() {
    saveDurations $scriptName $durationFile $SECONDS
    # Only keep 3 duration lines for this script
    trimDurations $scriptName $durationFile 3
    exit
}

# Make sure we can execute curl.
if [ ! -x "$(which curl 2>/dev/null)" ]; then
    printf "[Error] Can't run curl. Install curl and rerun this script.\n" >&2
    printf "        To test, type:  curl -Is https://github.com/ | head -5\n\n" >&2
    exit 1
fi

printf "==> Downloading new IMDb .gz files.\n"

if [ $(rg -c "^$scriptName\t" $durationFile) ]; then
    printf "\n==> Previously, this took "
    rg "^$scriptName\t" $durationFile | tail -1 | cut -f 4
    printf "\n"
fi

for file in name.basics.tsv.gz title.basics.tsv.gz title.episode.tsv.gz title.principals.tsv.gz; do
    source="https://datasets.imdbws.com/$file"
    printf "Downloading $source\n"
    curl -O $source
    printf "\n"
done

# Save durations and exit
terminate
