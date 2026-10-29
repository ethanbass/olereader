# olereader <img src="man/figures/logo.png" align="right" height="139" alt="olereader hex logo: an engraving of a dancer with raised arms holding castanets" />

<!-- badges: start -->
[![olereader status badge](https://ethanbass.r-universe.dev/badges/olereader)](https://ethanbass.r-universe.dev/olereader)
[![Last commit](https://img.shields.io/github/last-commit/ethanbass/olereader)](https://github.com/ethanbass/olereader/commits/main)
<!-- badges: end -->

olereader reads Microsoft compound files, also called OLE2 or structured
storage files, in pure R. A compound file works like a small file system
inside a single file: *storages* act as folders and *streams* hold the data.
Older Office documents (`.doc`, `.xls`, `.ppt`), Outlook messages (`.msg`)
and many instrument and application formats use this container.

olereader lists the streams in a file, reads them into raw vectors and
extracts them to disk. It has no dependencies beyond base R and does not
write compound files.

## Installation

Install the development version from GitHub:

``` r
# install.packages("pak")
pak::pak("ethanbass/olereader")
```

or install a binary from R-universe:

``` r
install.packages("olereader",
                 repos = c("https://ethanbass.r-universe.dev",
                           "https://cloud.r-project.org"))
```

## Usage

`ole_open()` reads a file's header and directory. Stream contents are only
read when you ask for them.

``` r
library(olereader)

ole <- ole_open(system.file("extdata", "example.cfb", package = "olereader"))
ole
#> <ole_file> .../olereader/extdata/example.cfb
#>   version 3, 512-byte sectors, 2 streams
```

The other functions also take a path in place of `ole`, as in
`ole_read("file.doc", "WordDocument")`. They then reopen and parse the file on
every call, so use `ole_open()` when you read several streams.

`ole_streams()` lists the streams, named by their path within the file:

``` r
str(ole_streams(ole))
#> List of 2
#>  $ data        : chr "data"
#>  $ notes/readme: chr [1:2] "notes" "readme"
```

`ole_read()` returns a stream as a raw vector, which you can decode with
`readBin()` or `rawToChar()`. Give the path as a vector of names or as one
string separated by `/`. Names match ignoring the case of the letters A to Z.

``` r
ole_size(ole, "data")
#> [1] 5000

rawToChar(ole_read(ole, c("notes", "readme")))
#> [1] "This is the readme stream of the olereader example file. It is short enough to be in the mini stream."
```

`ole_extract()` writes streams to files, with one folder for each storage.
It extracts every stream by default, or only the ones you name in `streams`:

``` r
ole_extract(ole, "example")
list.files("example", recursive = TRUE)
#> [1] "data"         "notes/readme"

ole_extract(ole, "example", streams = "notes/readme", overwrite = TRUE)
```

## Format

olereader is written from Microsoft's
[MS-CFB specification](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/).
It reads version 3 (512-byte sectors) and version 4 (4096-byte sectors)
files. `ole_streams()` lists streams in the same order as `listdir()` in the
Python package [olefile](https://github.com/decalage2/olefile), and
[`dev/compare_olefile.R`](https://github.com/ethanbass/olereader/blob/HEAD/dev/compare_olefile.R)
in the source repository checks that the two packages return the same
streams, sizes and bytes for any files you give it.

## Logo

The logo shows the dancer Pepita de Oliva, from the cover of the sheet music
[*El olé*](https://commons.wikimedia.org/wiki/File:El_ol%C3%A9_(NYPL_b12149002-5247020).jpg)
(Vienna: H. F. Müller's Witwe, 1850s), held by the New York Public Library's
Jerome Robbins Dance Division. The print is in the public domain.
