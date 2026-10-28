# Compares olereader with the Python package 'olefile' on every file given:
# the stream list (including its order), each stream's size and its bytes.
#   Rscript dev/compare_olefile.R file1 file2 ...
# Needs reticulate and a Python with olefile installed.

devtools::load_all(quiet = TRUE)
olefile <- reticulate::import("olefile")
bi <- reticulate::import_builtins()

for (f in commandArgs(trailingOnly = TRUE)){
  py <- olefile$OleFileIO(f)
  t_open <- system.time(ole <- ole_open(f), gcFirst = FALSE)[["elapsed"]]
  streams <- py$listdir()
  t_read <- system.time(bytes <- lapply(streams, function(s) ole_read(ole, s)),
                        gcFirst = FALSE)[["elapsed"]]
  bad <- 0
  for (k in seq_along(streams)){
    s <- streams[[k]]
    ref <- as.raw(bi$list(py$openstream(s)$read()))
    if (!identical(bytes[[k]], ref) || ole_size(ole, s) != py$get_size(s)) bad <- bad + 1
  }
  py$close()
  cat(sprintf("%-45s %6.1f MB  streams=%4d  order_match=%s  mismatches=%d  open=%.2fs read=%.2fs\n",
              basename(f), file.size(f) / 1e6, length(streams),
              identical(unname(ole_streams(ole)), streams), bad, t_open, t_read))
}
