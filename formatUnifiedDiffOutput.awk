/@@/ {
    gsub (/[+-]/,"")
    old = $2
    numFields  =  split (old,fld,",")
    oldLineNum = fld[1]
    numFields == 1 ? oldSize = 1: oldSize = fld[2]

    new = $3
    numFields  =  split (new,fld,",")
    newLineNum = fld[1]
    numFields == 1 ? newSize = 1: newSize = fld[2]

    # printf ("old: %-10s new: %s\n",old,new)
    # printf ("oldLineNum: %-6s newLineNum: %-6s\n",oldLineNum,newLineNum)
    # printf ("oldSize: %-6s newSize: %-6s\n",oldSize,newSize)

    if (oldSize == 0) {
        newSize == 1 ? pluralLines = "line" : pluralLines = "lines"
        printf ("==> added %d %s after line %s\n",newSize,pluralLines,oldLineNum)
    } else if (newSize == 0) {
        oldSize == 1 ? pluralLines = "line" : pluralLines = "lines"
        printf ("==> deleted %d %s at line %s\n",oldSize,pluralLines,oldLineNum)
    } else {
        oldSize == 1 ? pluralLines = "line" : pluralLines = "lines"
        printf ("==> changed %d %s at line %s\n",oldSize,pluralLines,oldLineNum)
    }

    next
}

/--- / {next}
/\+\+\+ / {next}

/=HYPERLINK/ {
    sub (/-.*=HYPERLINK.*;"/,"-")
    sub (/\+.*=HYPERLINK.*;"/,"+")
    sub (/"\)/,"")
}

{ print }
