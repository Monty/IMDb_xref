#!/usr/bin/env bash

# EXAMPLE USAGE

. ../functions/define_colors
. ../functions/read_YN.function

printf "==> Testing read_YN.function.\n\n"
printf "==> First, lets test [y/n] prompts. Type a Y, y, N, or n.\n"
printf "==> They should not proceed if you hit any other character, including <cr>.\n\n"

if read_YN "Testing no default. Hit y."; then
    printf "Yes\n"
else
    printf "No\n"
fi
if read_YN "Testing no default. Hit n."; then
    printf "Yes\n"
else
    printf "No\n"
fi

if read_YN "Testing no default. Hit <cr>. Should loop waiting for y or n."; then
    printf "Yes\n"
else
    printf "No\n"
fi

if read_YN "Testing no default. Hit a different character. Should loop waiting for y or n."; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "\n\n==> Now lets test [Y/n] and [y/N] prompts Answer Y, y, N, n, or <cr>.\n"
printf "==> A <cr> should be the same as hitting the capitalized letter.\n"
printf "==> They should not proceed if you hit any other character than Y, y, N, n, or <cr>.\n"

# Default to Yes [Y/n] if the user presses enter without giving an answer:
if read_YN "Testing Y default. Hit y." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi
if read_YN "Testing Y default. Hit n." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi

if read_YN "Testing Y default. Hit <cr>." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi
if read_YN "Testing N default. Hit <cr>." N; then
    printf "Yes\n"
else
    printf "No\n"
fi

if read_YN "Hit a different character. Should loop until Y, y, N, n, or <cr>." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi

if read_YN "Hit a different character. Should loop until Y, y, N, n, or <cr>." N; then
    printf "Yes\n"
else
    printf "No\n"
fi
