#!/usr/bin/env bash

# EXAMPLE USAGE

. ../functions/define_colors
. ../functions/ask_YN.function

printf "==> Testing ask_YN.function.\n"
printf "==> Hit ${RED}<cr>${NO_COLOR} to submit an answer.\n\n"
printf "==> First, lets test [y/n] prompts. Type a Y, y, N, or n.\n"
printf "==> They should not proceed if you enter any other character, including <cr>.\n\n"

if ask_YN "Testing no default. Enter any string starting with y."; then
    printf "Yes\n"
else
    printf "No\n"
fi
if ask_YN "Testing no default. Enter any string starting with n."; then
    printf "Yes\n"
else
    printf "No\n"
fi

if ask_YN "Testing no default. Enter <cr>. Should loop waiting for y or n."; then
    printf "Yes\n"
else
    printf "No\n"
fi

if ask_YN "Testing no default. Enter a different character. Should loop waiting for y or n."; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "\n\n==> Now lets test [Y/n] and [y/N] prompts Answer Y, y, N, n, or <cr>.\n"
printf "==> A <cr> should be the same as hitting the capitalized letter.\n"
printf "==> They should not proceed if you hit any other character than Y, y, N, n, or <cr>.\n"

# Default to Yes [Y/n] if the user presses enter without giving an answer:
if ask_YN "Testing Y default. Enter y." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi
if ask_YN "Testing Y default. Enter n." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi

if ask_YN "Testing Y default. Enter <cr>." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi
if ask_YN "Testing N default. Enter <cr>." N; then
    printf "Yes\n"
else
    printf "No\n"
fi

if ask_YN "Enter a different character. Should loop until Y, y, N, n, or <cr>." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi

if ask_YN "Enter a different character. Should loop until Y, y, N, n, or <cr>." N; then
    printf "Yes\n"
else
    printf "No\n"
fi
