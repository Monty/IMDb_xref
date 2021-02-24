#!/usr/bin/env bash

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd "$DIRNAME"/.. || exit

export LC_COLLATE="C"
source functions/define_colors
source functions/checkForExecutable.function

printf "==> Should find an executable for cat\n"
if checkForExecutable -q cat; then
    printf "Found an executable for cat\n"
else
    printf "I didn't find an executable for cat\n"
fi

printf "\n==> Should not find an executable for aaa\n"
if checkForExecutable -q aaa; then
    printf "Found an executable for aaa\n"
else
    printf "I didn't find an executable for aaa\n"
fi

printf "\n==> If there is no executable for bbb, print an error and exit.\n"
checkForExecutable bbb
