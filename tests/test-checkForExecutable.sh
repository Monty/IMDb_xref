#!/usr/bin/env bash

# Make sure we are in the correct directory
DIRNAME=$(dirname "$0")
cd $DIRNAME/..

. ../functions/checkForExecutable.function

printf "==> Should find an executable for cat\n"
if checkForExecutable cat quietly; then
    printf "Found an executable for cat\n"
else
    printf "Didn't find an executable for cat\n"
fi

printf "\n==> Should not find an executable for eee\n"
if checkForExecutable eee quietly; then
    printf "Found an executable for eee\n"
else
    printf "Didn't find an executable for eee\n"
fi
