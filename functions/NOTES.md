## Functions

Common functions used by more than one script.

They enable changes and additions to all scripts' functionality by simply
modifying or adding to these files.

They are standard bash code. Load them into any script by using
`source function/<function>.function`

### Definition functions

**define_colors** -- Defines names for eight standard terminal colors.  It
enables the use of named color variables instead of escape codes. For example:
`printf "Do you prefer ${RED}Red${NO_COLOR} or ${BLUE}Blue${NO_COLOR}?\n"`.  
Loading **define_colors** will render that text with colors. Not loading
**define_colors** will render that same text without colors.

**define_files** -- Defines standard files required by other scripts, and
creates them if they don't exist. For example: `configFile=".xref_config"`and
`durationFile=".xref_durations"`

### Standard functions

**load_functions** -- loads all files in this directory that end in
**.function**  
Loading **load_functions** at the start of any script enables you to use all
other functions without explicitly loading them, including ones you write at a
later time. You would only have to invoke the new function.

**ask_YN.function** -- a general-purpose function to ask Yes/No questions in Bash, or simply
wait for any keystroke. It takes an optional prompt string.
: