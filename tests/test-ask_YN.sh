#!/usr/bin/env bash

# Make sure we are in the correct directory
cd ..

. functions/define_colors
. functions/ask_YN.function

printf "==> Testing the ${RED}ask_YN.function${NO_COLOR}.\n\n"
printf "First, print the help file...\n"
ask_YN -h
printf "\n"

printf "==> Section 1. Test waiting for any key to be pressed. Hit any key.\n"
ask_YN -w

printf "==> Same with custom prompt. Hit any key.\n"
ask_YN -w "Custom prompt."

printf "==> Test waiting for any key to be pressed to clear screen. Hit any key.\n"
ask_YN -wc

printf "==> Same with custom prompt & clear screen. Hit any key.\n"
ask_YN -wc "Custom prompt."

printf "==> Done with Section 1.\n\n"

printf "==> Section 2. Test ${RED}[y/n]${NO_COLOR} prompts. Valid responses are Y, y, N, or n.\n"
printf "==> It should not proceed if you hit any other character, including <cr>.\n\n"
printf "==> It will return as soon as you type one character. It doesn't wait for a <cr>.\n"

printf "\n==> Some tests to check basic functionality using the default prompt.\n"
printf "==> An 'ask_YN' with no prompt supplied should prompt 'Does that look correct?'\n"
if ask_YN; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "==> A simple 'ask_YN' that only accepts 1 character. Type a y.\n"
if ask_YN; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "==> A second simple 'ask_YN' that only accepts 1 character. Type an n.\n"
if ask_YN; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "==> A third simple 'ask_YN' that only accepts 1 character. Hit any key.\n"
printf "==> It should loop waiting for y or n.\n"
if ask_YN; then
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

printf "==> With a prompt: 'ask_YN \"Can you set a custom prompt and clear the screen with -c?\"'\n"
ask_YN -c "Can you set a custom prompt and clear the screen with -c?"

printf "==> Show what is displayed if a bad param -x is sent.\n"
if ask_YN -x "Phooey. I have a bad parameter in my source code."; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "==> Done with Section 2.\n\n"

printf "==> Section 3. Test longer form answers that require a <cr> before proceeding.\n"
printf "==> Only the first character is tested, so 'yes' works as well as 'y'.\n"

printf "\n==> Four tests to check long responses to ${RED}[y/n]${NO_COLOR} prompts.\n"
if ask_YN -l "1. Enter any string starting with y."; then
    printf "Yes\n"
else
    printf "No\n"
fi

if ask_YN -l "2. Enter any string starting with n."; then
    printf "Yes\n"
else
    printf "No\n"
fi

if ask_YN -l "3. Enter <cr>. Should loop waiting for y or n."; then
    printf "Yes\n"
else
    printf "No\n"
fi

if ask_YN -l "4. Enter a different character. Should loop waiting for y or n."; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "==> Done with Section 3.\n\n"

printf "==> Section 4. Test ${RED}[Y/n]${NO_COLOR} and ${RED}[y/N]${NO_COLOR} prompts. "
printf "Valid responses are Y, y, N, n, or <cr>.\n"
printf "==> A <cr> should be the same as entering the capitalized letter.\n"
printf "==> It should not proceed if you enter any other character than Y, y, N, n, or <cr>.\n"

# Default to Yes [Y/n] if the user presses enter without giving an answer:
printf "\n==> Four tests to check possible responses to ${RED}[Y/n]${NO_COLOR} prompts.\n"
if ask_YN -lY "1. Enter any string starting with y." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi
if ask_YN -lY "2. Enter any string starting with n." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi
if ask_YN -lY "3. Enter <cr>." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi
if ask_YN -lY "4. Enter a different character. Should loop until Y, y, N, n, or <cr>." Y; then
    printf "Yes\n"
else
    printf "No\n"
fi

# Default to No [y/N] if the user presses enter without giving an answer:
printf "\n==> Four tests to check possible responses to ${RED}[y/N]${NO_COLOR} prompts.\n"
if ask_YN -lN "1. Enter any string starting with y." N; then
    printf "Yes\n"
else
    printf "No\n"
fi
if ask_YN -lN "2. Enter any string starting with n." N; then
    printf "Yes\n"
else
    printf "No\n"
fi
if ask_YN -lN "3. Enter <cr>." N; then
    printf "Yes\n"
else
    printf "No\n"
fi
if ask_YN -lN "4. Enter a different character. Should loop until Y, y, N, n, or <cr>." N; then
    printf "Yes\n"
else
    printf "No\n"
fi

printf "==> Done with Section 4. End of test.\n\n"
