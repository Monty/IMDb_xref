#!/usr/bin/env bash

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME"/.. || exit

export LC_COLLATE="C"
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
    if waitUntil "$YN_PREF" -Y 'Run ./findShowsWith.sh nm0000233'; then
        ./findShowsWith.sh nm0000233
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh -y "Olivia Colman"'; then
        ./findShowsWith.sh -y "Olivia Colman"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh nm0000123'; then
        ./findShowsWith.sh nm0000123
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh "George Clooney"'; then
        ./findShowsWith.sh "George Clooney"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh nm0000123 "Quentin Tarantino"'; then
        ./findShowsWith.sh nm0000123 "Quentin Tarantino"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh nm0000123 "Alfred Hitchcock"'; then
        ./findShowsWith.sh nm0000123 "Alfred Hitchcock"
    fi

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./findShowsWith.sh nm0000123 "Quentin Tarantino" nm0000233 "Alfred Hitchcock"'; then
        ./findShowsWith.sh nm0000123 "Quentin Tarantino" nm0000233 "Alfred Hitchcock"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh "Robert Downey"'; then
        ./findShowsWith.sh "Robert Downey"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh'; then
        ./findShowsWith.sh
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./findShowsWith.sh nm9999999'; then
        ./findShowsWith.sh nm9999999
    fi

    ! waitUntil "$YN_PREF" -Y '\nTests completed. Run again?' && break
    printf "\n"

done

unset NO_MENUS
