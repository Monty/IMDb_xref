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

printf "==> Testing ${RED}createTconstFile.sh${NO_COLOR}.\n\n"
printf "First, print the help file...\n"
./createTconstFile.sh -h
waitUntil -k
clear

if waitUntil -Y 'Run ./createTconstFile.sh tt1606375'; then
    ./createTconstFile.sh tt1606375
fi

if waitUntil -Y '\nRun ./createTconstFile.sh tt1606375 tt1399664 "Broadchurch"'; then
    ./createTconstFile.sh tt1606375 tt1399664 "Broadchurch"
fi

if waitUntil -Y '\nRun ./createTconstFile.sh "The Crown"'; then
    ./createTconstFile.sh "The Crown"
fi

if waitUntil -Y '\nRun ./createTconstFile.sh tt1606375 tt1399664 broadchurch "the crown"'; then
    ./createTconstFile.sh tt1606375 tt1399664 broadchurch "the crown"
fi

if waitUntil -Y '\nRun ./createTconstFile.sh "The Crown" River'; then
    ./createTconstFile.sh "The Crown" River
fi

if waitUntil -Y '\nRun ./createTconstFile.sh -f Dramas.tconst tt1606375'; then
    ./createTconstFile.sh -f Dramas.tconst tt1606375
fi
if waitUntil -Y '\nRun ./createTconstFile.sh aaa'; then
    ./createTconstFile.sh aaa
fi
