# Read an OLE stream

Read an OLE stream

## Usage

``` r
ole_read(ole, stream)
```

## Arguments

- ole:

  An `ole_file` object from
  [`ole_open()`](https://ethanbass.github.io/olereader/reference/ole_open.md),
  or the path to a compound file, which is opened and parsed again on
  every call.

- stream:

  Path to the stream: a character vector of names, such as
  `c("storage", "stream")`, a single string separating them with `/`, or
  a list holding one such path, such as `ole_streams(ole)[1]`. A string
  in a list is not split at `/`, so a list also reaches streams whose
  names contain `/`. Names are matched ignoring the case of the letters
  A to Z.
  [`ole_extract()`](https://ethanbass.github.io/olereader/reference/ole_extract.md)
  reads a character vector differently: each element is a separate
  stream.

## Value

A raw vector, or `NULL` if the stream does not exist.

## Examples

``` r
ole <- ole_open(system.file("extdata", "example.cfb", package = "olereader"))
rawToChar(ole_read(ole, c("notes", "readme")))
#> [1] "This is the readme stream of the olereader example file. It is short enough to be in the mini stream."
```
