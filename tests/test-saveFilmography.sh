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
    exit 130
}

export NO_MENUS="yes"

printf "==> Testing ${RED}saveFilmography.sh${NO_COLOR}.\n\n"
printf "First, print the help file...\n"
./saveFilmography.sh -h
waitUntil -k
clear

while true; do
    if waitUntil "$YN_PREF" -Y 'Run ./saveFilmography.sh nm0000233'; then
        ./saveFilmography.sh nm0000233
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./saveFilmography.sh nm0000123'; then
        ./saveFilmography.sh nm0000123
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./saveFilmography.sh "George Clooney"'; then
        ./saveFilmography.sh "George Clooney"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./saveFilmography.sh nm0000123 "Quentin Tarantino"'; then
        ./saveFilmography.sh nm0000123 "Quentin Tarantino"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./saveFilmography.sh nm0000123 "Alfred Hitchcock"'; then
        ./saveFilmography.sh nm0000123 "Alfred Hitchcock"
    fi

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./saveFilmography.sh nm0000123 "Quentin Tarantino" nm0000233 "Alfred Hitchcock"'; then
        ./saveFilmography.sh nm0000123 "Quentin Tarantino" nm0000233 "Alfred Hitchcock"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./saveFilmography.sh "Robert Downey"'; then
        ./saveFilmography.sh "Robert Downey"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./saveFilmography.sh'; then
        ./saveFilmography.sh
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./saveFilmography.sh nm9999999'; then
        ./saveFilmography.sh nm9999999
    fi

    ! waitUntil "$YN_PREF" -Y '\nTests completed. Run again?' && break
    printf "\n"

done

unset NO_MENUS
