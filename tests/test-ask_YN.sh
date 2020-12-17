#!/usr/bin/env bash

# Make sure we are in the correct directory
cd ..

. functions/define_colors
. functions/ask_YN.function

printf "==> Testing ask_YN.function.\n\n"

printf "==> First, let's test ${RED}[y/n]${NO_COLOR} prompts. Valid responses are Y, y, N, or n.\n"
printf "==> Only the first character is tested, so 'yes' works as well as 'y'.\n"
printf "==> It should not proceed if you hit any other character, inclucing <cr>.\n\n"

printf "\n==> Some tests to check basic functionality using the default prompt.\n"
printf "==> A simple 'ask_YN' with no prompt supplied should prompt 'Does that look correct?'\n"
if ask_YN; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "==> A simple 'ask_YN' with maxchars=6. Type an answer with less than 6 characters.\n"
if ask_YN -m 6; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "==> A second simple 'ask_YN' with maxchars=6. Type an answer more than 6 characters..\n"
if ask_YN -m 6; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "==> A simple 'ask_YN' with maxchars=1. Type a y or n.\n"
if ask_YN -m 1; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "==> A second simple 'ask_YN' with maxchars=1. Type any other character.\n"
if ask_YN -m 1; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "==> With a prompt: 'ask_YN \"Can you set a custom prompt?\"'\n"
if ask_YN "Can you set a custom prompt?"; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "==> With a prompt and hidden keystrokes: 'ask_YN -s \"Can you hide my keystrokes with -s?\"'\n"
if ask_YN -s "Can you hide my keystrokes with -s?"; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "==> With a prompt: 'ask_YN \"Can you set a custom prompt and clear the screen with -c?\"'\n"
ask_YN -c "Can you set a custom prompt and clear the screen with -c?"

printf "==> Show what is displayed if a bad param -x is sent.\n"
if ask_YN -x "Fooey. I have a bad parameter in my suorce code."; then
    printf "Yes\n"
else
    printf "No\n"
fi


printf "\n==> Four tests to check possible responses to ${RED}[y/n]${NO_COLOR} prompts.\n"
if ask_YN "1. Enter any string starting with y."; then
    printf "Yes\n"
else
    printf "No\n"
fi

if ask_YN "2. Enter any string starting with n."; then
    printf "Yes\n"
else
    printf "No\n"
fi

if ask_YN "3. Enter <cr>. Should loop waiting for y or n."; then
    printf "Yes\n"
else
    printf "No\n"
fi

if ask_YN "4. Enter a different character. Should loop waiting for y or n."; then
    printf "Yes\n"
else
    printf "No\n"
fi


printf "\n==> Now let's test ${RED}[Y/n]${NO_COLOR} and ${RED}[y/N]${NO_COLOR} prompts. "
printf "Valid responses are Y, y, N, n, or <cr>.\n"
printf "==> A <cr> should be the same as entering the capitalized letter.\n"
printf "==> It should not proceed if you enter any other character than Y, y, N, n, or <cr>.\n"

# Default to Yes [Y/n] if the user presses enter without giving an answer:
printf "\n==> Four tests to check possible responses to ${RED}[Y/n]${NO_COLOR} prompts.\n"
if ask_YN -Y "1. Enter any string starting with y." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi
if ask_YN -Y "2. Enter any string starting with n." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi
if ask_YN -Y "3. Enter <cr>." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi
if ask_YN -Y "4. Enter a different character. Should loop until Y, y, N, n, or <cr>." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi

# Default to No [y/N] if the user presses enter without giving an answer:
printf "\n==> Four tests to check possible responses to ${RED}[y/N]${NO_COLOR} prompts.\n"
if ask_YN -N "1. Enter any string starting with y." N; then
    printf "Yes\n"
else
    printf "No\n"
fi
if ask_YN -N "2. Enter any string starting with n." N; then
    printf "Yes\n"
else
    printf "No\n"
fi
if ask_YN -N "3. Enter <cr>." N; then
    printf "Yes\n"
else
    printf "No\n"
fi
if ask_YN -N "4. Enter a different character. Should loop until Y, y, N, n, or <cr>." N; then
    printf "Yes\n"
else
    printf "No\n"
fi
