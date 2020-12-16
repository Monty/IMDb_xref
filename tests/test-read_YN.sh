#!/usr/bin/env bash

# EXAMPLE USAGE

. ../functions/define_colors
. ../functions/read_YN.function

printf "==> Testing read_YN.function.\n\n"

printf "==> First, let's test ${RED}[y/n]${NO_COLOR} prompts. Valid responses are Y, y, N, or n.\n"
printf "==> It should not proceed if you hit any other character, inclucing <cr>.\n\n"

printf "==> One test to show what is displayed if no question is supplied.\n"
if read_YN; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "\n==> Four tests to check possible responses to ${RED}[y/n]${NO_COLOR} prompts.\n"
if read_YN "1. Hit y."; then
    printf "Yes\n"
else
    printf "No\n"
fi

if read_YN "2. Hit n."; then
    printf "Yes\n"
else
    printf "No\n"
fi

if read_YN "3. Hit <cr>. Should loop waiting for y or n."; then
    printf "Yes\n"
else
    printf "No\n"
fi

if read_YN "4. Hit a different character. Should loop waiting for y or n."; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "\n==> Now let's test ${RED}[Y/n]${NO_COLOR} and ${RED}[y/N]${NO_COLOR} prompts. "
printf "Valid responses are Y, y, N, n, or <cr>.\n"
printf "==> A <cr> should be the same as hitting the capitalized letter.\n"
printf "==> It should not proceed if you hit any other character than Y, y, N, n, or <cr>.\n"

# Default to Yes [Y/n] if the user presses enter without giving an answer:
printf "\n==> Four tests to check possible responses to ${RED}[Y/n]${NO_COLOR} prompts.\n"
if read_YN "1. Hit y." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi
if read_YN "2. Hit n." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi
if read_YN "3. Hit <cr>." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi
if read_YN "4. Hit a different character. Should loop until Y, y, N, n, or <cr>." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi

# Default to No [y/N] if the user presses enter without giving an answer:
printf "\n==> Four tests to check possible responses to ${RED}[y/N]${NO_COLOR} prompts.\n"
if read_YN "1. Hit y." N; then
    printf "Yes\n"
else
    printf "No\n"
fi
if read_YN "2. Hit n." N; then
    printf "Yes\n"
else
    printf "No\n"
fi
if read_YN "3. Hit <cr>." N; then
    printf "Yes\n"
else
    printf "No\n"
fi
if read_YN "4. Hit a different character. Should loop until Y, y, N, n, or <cr>." N; then
    printf "Yes\n"
else
    printf "No\n"
fi
