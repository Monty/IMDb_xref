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

printf "==> Testing ${RED}findShowsWith.sh${NO_COLOR}.\n\n"
printf "First, print the help file...\n"
./findShowsWith.sh -h
waitUntil -k
clear

while true; do
    if waitUntil "$YN_PREF" -Y 'Run ./findShowsWith.sh nm0022261 (Pedro Alonso, cached)'; then
        ./findShowsWith.sh nm0022261
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh -y "Olivia Colman" (cached, name search)'; then
        ./findShowsWith.sh -y "Olivia Colman"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh "Claire Foy" (cached)'; then
        ./findShowsWith.sh "Claire Foy"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh nm0022261 "Claire Foy" (mixed nconst + name)'; then
        ./findShowsWith.sh nm0022261 "Claire Foy"
    fi

    printf "\n==> Verify a person not in the index reports the pointer message,\n"
    printf "    not an error, and does not scrape (findShowsWith is local).\n"

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh nm0000123 (George Clooney, NOT cached)'; then
        ./findShowsWith.sh nm0000123
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh "Quentin Tarantino" (NOT cached, name search)'; then
        ./findShowsWith.sh "Quentin Tarantino"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh'; then
        ./findShowsWith.sh
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh nm9999999 (invalid nconst)'; then
        ./findShowsWith.sh nm9999999
    fi

    ! waitUntil "$YN_PREF" -Y '\nTests completed. Run again?' && break
    printf "\n"

done

unset NO_MENUS
