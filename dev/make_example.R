# Writes inst/extdata/example.cfb with the generator the tests use.

source("tests/testthat/helper-make-cfb.R")
dir.create("inst/extdata", recursive = TRUE, showWarnings = FALSE)
make_cfb("inst/extdata/example.cfb")
