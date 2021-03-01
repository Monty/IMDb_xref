# Generate an awk format string that emulates "elastic tabs" using spaces
# for use when xsv is not installed.
#
# It would be equivalent to 'xsv table' except that the length of strings
# containing non-English characters is not always handled correctly by awk.
#
# Take the maximum field width of any column in a file and add two spaces.

{
    if (NR != 1) {
        for ( i = 1; i <= numFields;  i++ ) {
            if ( length($i) > w[i] )
                w[i] = length($i)
        }
    } else {
        numFields = NF
        for ( i = 1; i <= numFields;  i++ ) {
            w[i] = length($i)
        }
    }
}

END {
    for ( i = 1; i <= numFields;  i++ ) {
        pfmt = pfmt "%-" w[i] + 2 "s"
    }
    print pfmt "\\n"
}
