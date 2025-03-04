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

printf "==> Testing ${RED}xrefCast.sh${NO_COLOR}.\n\n"
printf "First, print the help file...\n"
./xrefCast.sh -h
waitUntil -k
clear

while true; do

    if waitUntil "$YN_PREF" -Y '\nRun ./xrefCast.sh "Olivia Colman"'; then
        ./xrefCast.sh "Olivia Colman"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./xrefCast.sh "Olivia Colman" "Elizabeth Debicki"'; then
        ./xrefCast.sh "Olivia Colman" "Elizabeth Debicki"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./xrefCast.sh -pi "Olivia Colman" "Elizabeth Debicki"'; then
        ./xrefCast.sh -pi "Olivia Colman" "Elizabeth Debicki"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./xrefCast.sh "Olivia Colman" "Princess Diana"'; then
        ./xrefCast.sh "Olivia Colman" "Princess Diana"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./xrefCast.sh "Queen Elizabeth II" "Princess Diana"'; then
        ./xrefCast.sh "Queen Elizabeth II" "Princess Diana"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./xrefCast.sh "Olivia Colman" "The Night Manager"'; then
        ./xrefCast.sh "Olivia Colman" "The Night Manager"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./xrefCast.sh "the durrells in corfu" "the night manager"'; then
        ./xrefCast.sh "the durrells in corfu" "the night manager"
    fi

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./xrefCast.sh "The Night Manager" ""The Durrells"'; then
        ./xrefCast.sh "The Night Manager" "The Durrells"
    fi

    printf "==> Verify -d only lists cast members who are in more than one show.\n"

    if waitUntil "$YN_PREF" -Y \
        '\nRun ./xrefCast.sh -d "The Night Manager" "The Crown" "The Durrells"'; then
        ./xrefCast.sh -d "The Night Manager" "The Crown" "The Durrells"
    fi

    if waitUntil "$YN_PREF" -Y '\nRun ./xrefCast.sh'; then
        ./xrefCast.sh
    fi
    if waitUntil "$YN_PREF" -Y '\nRun ./xrefCast.sh aaa'; then
        ./xrefCast.sh aaa
    fi

    ! waitUntil "$YN_PREF" -Y '\nTests completed. Run again?' && break
    printf "\n"

done

unset NO_MENUS
