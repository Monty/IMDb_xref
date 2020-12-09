#!/usr/bin/env bash
# Download needed files from IMDb, even if they already exist
#
# See https://www.imdb.com/interfaces/ for a description of IMDb Datasets

printf "==> Downloading new IMDb .gz files.\n"

# Make sure we can execute curl.
if [ ! -x "$(which curl 2>/dev/null)" ]; then
    printf "[Error] Can't run curl. Install curl and rerun this script.\n" >&2
    printf "        To test, type:  curl -Is https://github.com/ | head -5\n\n" >&2
    exit 1
fi

for file in name.basics.tsv.gz title.basics.tsv.gz title.episode.tsv.gz title.principals.tsv.gz; do
    source="https://datasets.imdbws.com/$file"
    printf "Downloading $source\n"
    curl -O $source
    printf "\n"
done
