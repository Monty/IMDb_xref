#!/usr/bin/env bash

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME"/..

source functions/define_colors
source functions/define_files
source functions/load_functions

# trap ctrl-c and call cleanup
trap cleanup INT
#
function cleanup() {
    exit 130
}

printf "==> Testing ${RED}createFilmography.sh${NO_COLOR}.\n\n"
printf "First, print the help file...\n"
./createFilmography.sh -h
waitUntil -k
clear

while true; do
    if waitUntil -Y 'Run ./createFilmography.sh nm0000233'; then
        ./createFilmography.sh nm0000233
    fi

    if waitUntil -Y '\nRun ./createFilmography.sh nm0000123'; then
        ./createFilmography.sh nm0000123
    fi

    if waitUntil -Y '\nRun ./createFilmography.sh "George Clooney"'; then
        ./createFilmography.sh "George Clooney"
    fi

    if waitUntil -Y '\nRun ./createFilmography.sh nm0000123 "Quentin Tarantino"'; then
        ./createFilmography.sh nm0000123 "Quentin Tarantino"
    fi

    if waitUntil -Y '\nRun ./createFilmography.sh nm0000123 "Alfred Hitchcock"'; then
        ./createFilmography.sh nm0000123 "Alfred Hitchcock"
    fi

    if waitUntil -Y \
        '\nRun ./createFilmography.sh nm0000123 "Quentin Tarantino" nm0000233 "Alfred Hitchcock"'; then
        ./createFilmography.sh nm0000123 "Quentin Tarantino" nm0000233 "Alfred Hitchcock"
    fi

    if waitUntil -Y '\nRun ./createFilmography.sh'; then
        ./createFilmography.sh
    fi

    if waitUntil -Y '\nRun ./createFilmography.sh nm9999999'; then
        ./createFilmography.sh nm9999999
    fi

    ! waitUntil -Y '\nTests completed. Run again?' && break
    printf "\n"

done
