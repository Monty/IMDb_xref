#!/usr/bin/env bash

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME"/.. || exit

source functions/define_colors
source functions/define_files
source functions/load_functions
ensurePrerequisites

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    unset NO_MENUS
    mkdir -p "$cacheDirectory"
    exit 130
}

export NO_MENUS="yes"

function cacheSize() {
    numFiles="$(find "$cacheDirectory" -maxdepth 1 -mindepth 1 | sed -n '$=')"
    if [ -z "$numFiles" ]; then
        printf "\n==> There are no cached files.\n"
        return
    fi
    if [ "$numFiles" -eq 1 ]; then
        printf "\n==> There is %d cached file.\n" "$numFiles"
        du -sh "$cacheDirectory"/* | sed -e s+"$cacheDirectory"/++
    else
        printf "\n==> There are %d cached files.\n" "$numFiles"
        du -shc "$cacheDirectory"/* | sort -n | sed -e s+"$cacheDirectory"/++
    fi
}

printf "==> Testing ${RED}cache timing${NO_COLOR}.\n\n"
printf "==> First, delete any cache files..."

rm -rf "$cacheDirectory"
mkdir -p "$cacheDirectory"
cacheSize
waitUntil -k

printf "\n==> augment_tconstFiles without cache should be slow...\n"
time ./augment_tconstFiles.sh -ay Contrib/*tconst
cacheSize
waitUntil -k

printf "\n==> augment_tconstFiles with cache should be faster...\n"
time ./augment_tconstFiles.sh -ay Contrib/*tconst
cacheSize

printf "\n==> findCastOf without cache should be slow...\n"
printf "    Hit <cr> 4 times to respond to prompts before times are reported.\n"
time ./findCastOf.sh "The Durrells" tt1399664 >/dev/null
cacheSize
waitUntil -k

printf "\n==> findCastOf with cache should be faster...\n"
printf "    Hit <cr> 4 times to respond to prompts before times are reported.\n"
time ./findCastOf.sh "The Durrells" tt1399664 >/dev/null
cacheSize

printf "\n==> End of test.\n\n"

unset NO_MENUS
