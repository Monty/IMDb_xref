## IMDb_xref

Command line utilities to quickly cross-reference and query shows, actors, and the characters they portray using data downloaded from IMDb.

[![MIT License](https://img.shields.io/github/license/Monty/IMDb_xref)](LICENSE)
[![Code](https://tokei.rs/b1/github/Monty/IMDb_xref?category=code)](https://github.com/Monty/IMDb_xref)
[![Lines](https://tokei.rs/b1/github/Monty/IMDb_xref?category=lines)](https://github.com/Monty/IMDb_xref)
[![Files](https://tokei.rs/b1/github/Monty/IMDb_xref?category=files)](https://github.com/Monty/IMDb_xref)
[![Commits](https://badgen.net/github/commits/Monty/IMDb_xref/main/)](https://github.com/Monty/IMDb_xref)
[![Last Commit](https://img.shields.io/github/last-commit/Monty/IMDb_xref)](https://github.com/Monty/IMDb_xref)

- [Motivation](#motivation)
- [Installation](#installation)
- [Usage](#usage)
- [Contributing](#contributing)
- [License](#license)

## Motivation

When watching a TV show or movie, have you ever spotted a familiar face but
can't remember the actor's name or what other shows you've seen them in?

To solve this I used to go to the IMDb website; find the show; click on "See full
cast & crew"; find the character; click on the actor's name; then scroll through
their "Filmography" to see if I recognized any other shows I'd watched. This was both
time-consuming and difficult -- even more so if I wanted to know if two shows had
actors in common.

I wrote **IMDb_xref** to answer such questions simply and quickly. Now I have even more
fun learning about actors and shows.

You can run simple queries to instantly answer questions about your favorites, such
as these I came up with after watching the PBS show "The Crown".

* Who stars in "The Crown"?
* What actresses have played Queen Elisabeth II and Princess Diana?
* What other shows I've seen were they in?
* Did anyone play in both "The Crown" and "The Durrells in Corfu"?

Click on the query screenshot below to see a short demo video.

[![IMDb_xref query demo video](docs/Screenshots/Query.png)](http://www.youtube.com/watch?v=91h3mnvV7Ug "IMDb_xref query demo")

**IMDb_xref** also creates comprehensive lists and spreadsheets of shows, actors,
and the characters they portray. They're useful as an overview or for discovering
actors and shows you may want to know more about.

The data used is extracted from downloaded IMDb .gz files. See
[https://www.imdb.com/interfaces/](https://www.imdb.com/interfaces/) for details of the data in those files.

## Installation

### Compatibility

Tested on macOS and Linux. May work in Windows 10 if [Windows Subsystem for Linux](https://docs.microsoft.com/en-us/windows/wsl/faq) is installed.

### Install prerequisites

Install **ripgrep** to get acceptable performance because searching 700 MB of
compressed data with zgrep is 15x slower. See
[https://crates.io/crates/ripgrep](https://crates.io/crates/ripgrep). (*If
anyone wants to rewrite this to use zgrep or another search engine, be my
guest.*)

While it's not required, **xsv** greatly improves table layout, especially for
non-English names, by using "elastic tabs". See
[https://crates.io/crates/xsv](https://crates.io/crates/xsv).

### Install IMDb_xref
Either **[download an IMDb_xref release](https://github.com/Monty/IMDb_xref/releases)** or type these commands into a terminal window:

```sh
git clone https://github.com/Monty/IMDb_xref.git
cd IMDb_xref
```

## Usage

### Generate some data

Run **./generateXrefData.sh** to download the IMDb data files and generate lists
and spreadsheets containing cast members, characters portrayed, alternate
titles, and other details from IMDb. This takes 40 seconds on my 2014 iMac
(*Note: I have a fast internet connection.*)

<details><summary><b>Show output</b></summary>

    $ ./generateXrefData.sh
    ==> Downloading new IMDb .gz files.
    Downloading https://datasets.imdbws.com/name.basics.tsv.gz
    Downloading https://datasets.imdbws.com/title.basics.tsv.gz
    Downloading https://datasets.imdbws.com/title.episode.tsv.gz
    Downloading https://datasets.imdbws.com/title.principals.tsv.gz
    
    ==> Creating an example translation file: PBS.xlate
    
    ==> Creating an example tconst file: PBS.tconst
    
    ==> Using all .xlate files for IMDb title translation.
    
    ==> Searching all .tconst files for IMDb title identifiers.
    
    ==> Processing 3 shows found in *.tconst:
    	The Crown; The Durrells in Corfu; The Night Manager

    ==> Show types in Shows-201201.csv:
    	  92 tvEpisode
    	   2 tvSeries
    	   1 tvMiniSeries
    
    ==> Stats from processing Credits-Person-201201.csv:
          90 people credited -- some in more than one job function
               34 as actor
               26 as actress
               15 as writer
               13 as director
    
    ==> Stats from processing IMDb data:
    uniqTitles-201201.txt                           50B   Dec 1 15:09        3 lines
    Shows-Episodes-201201.csv                      6.3K   Dec 1 15:10       95 lines
    uniqPersons-201201.txt                         1.3K   Dec 1 15:10       90 lines
    Persons-KnownFor-201201.csv                    6.8K   Dec 1 15:10       90 lines
    Credits-Show-201201.csv                         45K   Dec 1 15:10      704 lines
    Credits-Person-201201.csv                       45K   Dec 1 15:10      704 lines
    associatedTitles-201201.csv                     26K   Dec 1 15:10      282 lines
</details>

Re-running **./generateXrefData.sh** doesn't download the IMDb data files again.
This reduces the run time to 20 seconds. It will overwrite any files
produced earlier that day but not those from any previous day.

<details><summary><b>Show output</b></summary>

    $ ./generateXrefData.sh
    ==> Using existing IMDb .gz files.
    
    ==> Using all .xlate files for IMDb title translation.
    
    ==> Searching all .tconst files for IMDb title identifiers.
    
    ==> Processing 3 shows found in *.tconst:
    	The Crown; The Durrells in Corfu; The Night Manager
    
    ==> Show types in Shows-201201.csv:
    	  92 tvEpisode
    	   2 tvSeries
    	   1 tvMiniSeries
    
    ==> Stats from processing Credits-Person-201201.csv:
          90 people credited -- some in more than one job function
               34 as actor
               26 as actress
               15 as writer
               13 as director
    
    ==> Stats from processing IMDb data:
    uniqTitles-201201.txt                           50B   Dec 1 15:09        3 lines
    Shows-Episodes-201201.csv                      6.3K   Dec 1 15:10       95 lines
    uniqPersons-201201.txt                         1.3K   Dec 1 15:10       90 lines
    Persons-KnownFor-201201.csv                    6.8K   Dec 1 15:10       90 lines
    Credits-Show-201201.csv                         45K   Dec 1 15:10      704 lines
    Credits-Person-201201.csv                       45K   Dec 1 15:10      704 lines
    associatedTitles-201201.csv                     26K   Dec 1 15:10      282 lines
</details>

Since **./generateXrefData.sh** displays statistics as it runs, you probably
noticed that it only produced data on 3 shows with 92 episodes -- crediting 90
people with 704 lines of credits.

If you run **./generateXrefData.sh -td**, you'll get 98 shows with 2159 episodes
-- crediting 3605 people with 17276 lines of credits. Running this takes about
45 seconds. However, queries should still take less than one second.

<details><summary><b>Show output</b></summary>

	$ ./generateXrefData.sh -td
    ==> Using existing IMDb .gz files.
    
    ==> Using xlate.example for IMDb title translation.
    
    ==> Searching tconst.example for IMDb title identifiers.
    
    ==> diffs-201201.151325.txt contains diffs between generated files and files saved in test_results
    
    ==> Processing 98 shows found in tconst.example:
    	800 Words; A Man Called Ove; A Touch of Frost; Acquitted; American Experience;
    	An Inspector Calls; Arde Madrid; Art of Crime; Ashes to Ashes; Beck; Black
    	Widows; Black Widows (2014); Blood of the Vine; Broadchurch; Bulletproof Heart;
    	Captain Marleau; Cranford; Deadwind; Death in Paradise; Death of a Pilgrim;
    	Detective Ellen Lucas; Detective Montalbano; Doc Martin; Downton Abbey;
    	Endeavour; Fargo; Father Brown; Foyle's War; Gasmamman; Grantchester; Imma
    	Tataranni - Deputy Prosecutor; In the Loop; Inspector Dupin; Inspector George
    	Gently; Inspector Manara; Inspector Morse; Jo Nesbø's Headhunters; Kennedy's
    	Brain; Kieler Street; Lark Rise to Candleford; Last Tango in Halifax; Life on
    	Mars; Line of Duty; McDonald & Dodds; MI-5; Money Murder Zurich; Mr Selfridge;
    	Mr. Holmes; Mrs. Wilson; Murder by the Lake; Murdoch Mysteries; My Life Is
    	Murder; Mystery Road; No Offence; Perfect Murders; Poirot; Prime Suspect;
    	Rebecka Martinsson; River; Roadkill; Rosemary and Thyme; Scott & Bailey;
    	Sebastian Bergman; Shetland; Silent Witness; Spiral; Spring Tide; The Bastards
    	of Pizzofalcone; The Brokenwood Mysteries; The Crown; The Doctor Blake
    	Mysteries; The Durrells in Corfu; The Fourth Man; The Girl Who Kicked the
    	Hornet's Nest; The Girl Who Played with Fire; The Girl with the Dragon Tattoo;
    	The Gulf; The Hidden Child; The Hunters; The Mallorca Files; The Night Manager;
    	The Sandhamn Murders; The Secret Agent; The Sommerdahl Murders; The Sounds; The
    	Team; The Valhalla Murders; The Young Montalbano; Trapped; Twin; Unforgotten;
    	Van der Valk; Vera; Waking the Dead; Wallander: The Original Episodes; Winter;
    	Wire in the Blood; Young Wallander
    
    ==> Show types in Shows-Episodes-201201.csv:
    	2159 tvEpisode
    	  76 tvSeries
    	  12 tvMiniSeries
    	   8 movie
    	   2 tvMovie
    
    ==> Stats from processing Credits-Person-201201.csv:
        3605 people credited -- some in more than one job function
             1434 as actor
             1030 as actress
              625 as writer
              428 as director
    
    ==> Stats from processing IMDb data:
    uniqTitles-201201.txt                          1.5K   Dec 4 15:03       98 lines
    Shows-Episodes-201201.csv                      161K   Dec 4 15:04     2257 lines
    uniqPersons-201201.txt                          52K   Dec 4 15:04     3605 lines
    Persons-KnownFor-201201.csv                    277K   Dec 4 15:04     3612 lines
    Credits-Show-201201.csv                        1.1M   Dec 4 15:04    17226 lines
    Credits-Person-201201.csv                      1.1M   Dec 4 15:04    17226 lines
    associatedTitles-201201.csv                    694K   Dec 4 15:03     7378 lines
</details>

Data can grow quite large. If you use all the files in /Contrib, you'll generate
over 7.5 MB of data, including two 46,000 line Credits spreadsheets.

### Run some queries

Run **./xrefCast.sh -h** to see some example queries. Experiment making up other
queries. One may lead to another...

<details><summary><b>Show output</b></summary>

    $ ./xrefCast.sh -h
    Cross-reference shows, actors, and the characters they portray using data from IMDB.
    
    USAGE:
        ./xrefCast.sh [OPTIONS] [-f SEARCH_FILE] SEARCH_TERM [SEARCH_TERM ...]
    
    OPTIONS:
        -h      Print this message.
        -a      All -- Only print 'All names' section.
        -f      File -- Query a specific file rather than "Credits-Person*csv".
        -s      Summarize -- Only print 'Duplicated names' section.
        -i      Print info about any files that are searched.
    
    EXAMPLES:
        ./xrefCast.sh 'Olivia Colman'
        ./xrefCast.sh 'Queen Elizabeth II' 'Princess Diana'
        ./xrefCast.sh 'The Crown'
        ./xrefCast.sh -s 'The Night Manager' 'The Crown' 'The Durrells in Corfu'
</details>

Run **./demo.sh** to see the information returned from these queries and more.
Each query should take less than one second.

***Protip***: typing **alias xr="${PWD}/xrefCast.sh \\"\\$@\\""** while in this
directory will allow you to type **xr 'Princess Diana'** instead of
**./xrefCast.sh 'Princess Diana'** -- and, **xr** can be run from anywhere.

### Go further

You can select different shows by using one or more of the .tconst files in the
Contrib directory or creating your own .tconst file. You can even translate
non-English titles to their English equivalents by using a .xlate file.

The default for **./generateXrefData.sh** is to use all .tconst and all .xlate
files in the top level directory. So put whatever files you want there.  (*Your
contributions are welcome. Start your own lists: broad genres such as Comedies,
Sci-Fi, Musicals, Historical Dramas - or more specific lists like "TV shows with
Robots")

Until I find time to produce more documentation, you can learn a lot from the
descriptive comments in the shell scripts and *.example files.

## Contributing

Feel free to dive in! [Open an issue](hhttps://github.com/Monty/IMDb_xref/issues/new) or submit PRs.

## License

[MIT](LICENSE) © Monty Williams

