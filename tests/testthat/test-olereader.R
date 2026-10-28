path <- system.file("extdata", "example.cfb", package = "olereader")

test_that("ole_streams lists streams depth-first and sorted", {
  ole <- ole_open(path)
  expect_identical(ole_streams(ole),
                   list(data = "data", `notes/readme` = c("notes", "readme")))
})

test_that("ole_read follows a FAT chain that is not contiguous", {
  ole <- ole_open(path)
  expect_identical(ole_read(ole, "data"), as.raw(rep_len(0:255, 5000)))
  expect_identical(ole_size(ole, "data"), 5000)
})

test_that("ole_read reads streams from the mini stream", {
  ole <- ole_open(path)
  readme <- ole_read(ole, c("notes", "readme"))
  expect_match(rawToChar(readme), "^This is the readme stream")
  expect_length(readme, ole_size(ole, c("notes", "readme")))
})

test_that("paths can be strings and match case-insensitively", {
  ole <- ole_open(path)
  expect_identical(ole_read(ole, "NOTES/ReadMe"),
                   ole_read(ole, c("notes", "readme")))
})

test_that("missing streams and storages give NULL and size 0", {
  ole <- ole_open(path)
  expect_null(ole_read(ole, "missing"))
  expect_identical(ole_size(ole, "missing"), 0)
  expect_null(ole_read(ole, "notes"))
  expect_identical(ole_size(ole, "notes"), 0)
})

test_that("every function also takes a path", {
  ole <- ole_open(path)
  expect_identical(ole_streams(path), ole_streams(ole))
  expect_identical(ole_size(path, "data"), ole_size(ole, "data"))
  expect_identical(ole_read(path, "notes/readme"), ole_read(ole, "notes/readme"))
  dir <- withr::local_tempdir()
  expect_identical(basename(ole_extract(path, dir, "data")), "data")
})

test_that("ole_open rejects files that are not compound files", {
  tmp <- tempfile()
  on.exit(unlink(tmp))
  writeBin(charToRaw("not an OLE file"), tmp)
  expect_error(ole_open(tmp), "not an OLE compound file")
})

test_that("version 4 files with 4096-byte sectors are read", {
  tmp <- tempfile()
  on.exit(unlink(tmp))
  ole <- ole_open(make_cfb(tmp, version = 4))
  expect_identical(ole$sector_size, 4096)
  expect_identical(ole_read(ole, "data"), as.raw(rep_len(0:255, 5000)))
  expect_identical(rawToChar(ole_read(ole, "notes/readme")), README_TEXT)
})

test_that("FAT sectors listed in a chain of DIFAT sectors are found", {
  tmp <- tempfile()
  on.exit(unlink(tmp))
  make_cfb(tmp, data_size = 16e6)
  header <- readBin(tmp, "raw", 512)
  expect_identical(readBin(header[73:76], "integer", endian = "little"), 2L)
  ole <- ole_open(tmp)
  expect_identical(ole_read(ole, "data"), as.raw(rep_len(0:255, 16e6)))
  expect_identical(rawToChar(ole_read(ole, "notes/readme")), README_TEXT)
})

test_that("ole_extract writes every stream, one folder per storage", {
  ole <- ole_open(path)
  dir <- tempfile()
  on.exit(unlink(dir, recursive = TRUE))
  files <- ole_extract(ole, dir)
  expect_named(files, c("data", "notes/readme"))
  expect_setequal(list.files(dir, recursive = TRUE), c("data", "notes/readme"))
  expect_identical(readBin(files[["data"]], "raw", 1e4), ole_read(ole, "data"))
  expect_identical(readLines(files[["notes/readme"]], warn = FALSE), README_TEXT)
})

test_that("ole_extract takes a subset as strings or as ole_streams paths", {
  ole <- ole_open(path)
  dir <- tempfile()
  on.exit(unlink(dir, recursive = TRUE))
  ole_extract(ole, dir, streams = "NOTES/readme")
  expect_identical(list.files(dir, recursive = TRUE), "notes/readme")
  ole_extract(ole, dir, streams = ole_streams(ole)["data"])
  expect_setequal(list.files(dir, recursive = TRUE), c("data", "notes/readme"))
})

test_that("ole_extract checks streams and existing files before writing", {
  ole <- ole_open(path)
  dir <- tempfile()
  on.exit(unlink(dir, recursive = TRUE))
  expect_error(ole_extract(ole, dir, streams = c("data", "missing", "notes")),
               "not found: .missing., .notes.")
  expect_false(dir.exists(dir))
  ole_extract(ole, dir, streams = "data")
  expect_error(ole_extract(ole, dir), "already exist")
  expect_false(file.exists(file.path(dir, "notes", "readme")))
  expect_no_error(ole_extract(ole, dir, overwrite = TRUE))
})

test_that("entry names are made safe as file names on every platform", {
  expect_identical(
    ole_file_name(c("..", ".", "\005SummaryInformation", "a<b>?", "CON",
                    "nul.txt", "a. ", "console")),
    c("_", "_", "_SummaryInformation", "a_b__", "_CON", "_nul.txt", "a",
      "console"))
})

test_that("left siblings are followed and streams sorted whatever the entry IDs", {
  ole <- ole_open(make_cfb(withr::local_tempfile(), layout = "left"))
  expect_identical(names(ole_streams(ole)), c("data", "notes/readme"))
  expect_identical(ole_read(ole, "data"), as.raw(rep_len(0:255, 5000)))
  expect_identical(rawToChar(ole_read(ole, "notes/readme")), README_TEXT)
})

test_that("a stream of exactly 4096 bytes is read from the FAT", {
  ole <- ole_open(make_cfb(withr::local_tempfile(), data_size = 4096))
  expect_identical(ole_read(ole, "data"), as.raw(rep_len(0:255, 4096)))
})

test_that("ole_read and ole_size take one path in a list", {
  ole <- ole_open(path)
  streams <- ole_streams(ole)
  expect_identical(ole_read(ole, streams[2]), ole_read(ole, streams[[2]]))
  expect_identical(ole_size(ole, streams["data"]), 5000)
  expect_error(ole_read(ole, streams), "one stream at a time")
  expect_identical(ole_size(ole, ""), 0)
})

test_that("the high 32 bits of a size count only in version 4", {
  bytes <- c(cfb_entry("Root Entry", 5, child = 1),
             cfb_entry("big", 2, size = 5000, size_high = 1))
  expect_identical(ole_directory(bytes, 4)$size[2], 5000 + 2^32)
  expect_identical(ole_directory(bytes, 3)$size[2], 5000)
})

test_that("damaged names are decoded without failing", {
  long <- cfb_entry("data", 2)
  long[65] <- as.raw(64)
  odd <- cfb_entry("data", 2)
  odd[65] <- as.raw(9)
  surrogate <- cfb_entry("", 2, utf16 = as.raw(c(0x00, 0xD8, 0x61, 0x00)))
  over <- cfb_entry(strrep("x", 32), 2)
  over[65] <- as.raw(200)
  dir <- ole_directory(c(cfb_entry("Root Entry", 5), long, odd, surrogate,
                         over), 3)
  expect_identical(dir$name[2:3], c("data", "data"))
  expect_identical(dir$name[5], strrep("x", 31))
  expect_false(is.na(dir$name[4]))
  expect_match(dir$name[4], "a$")
})

test_that("storages may nest 64 deep but no deeper", {
  nest <- function(depth){
    storages <- lapply(seq_len(depth), function(k){
      cfb_entry(paste0("s", k), 1, child = k + 1)
    })
    c(cfb_entry("Root Entry", 5, child = 1), unlist(storages),
      cfb_entry("leaf", 2))
  }
  ole <- list(dir = ole_directory(nest(64), 3))
  expect_identical(ole_streams(ole)[[1]], c(paste0("s", 1:64), "leaf"))
  expect_error(ole_directory(nest(65), 3), "nested more than 64")
})

test_that("damaged headers and allocation tables give errors", {
  expect_error(ole_open(patch_cfb(path, 30, cfb_u16(7))), "sector size")
  expect_error(ole_open(patch_cfb(path, 44, cfb_i32(.Machine$integer.max))),
               "header .* is corrupt")
  ole <- ole_open(patch_cfb(path, 528, cfb_i32(4)))
  expect_error(ole_read(ole, "data"), "loops back")
  ole <- ole_open(patch_cfb(path, 1272, cfb_i32(1e6)))
  expect_error(ole_read(ole, "data"), "larger than the file")
  ole <- ole_open(patch_cfb(path, truncate = 4000))
  expect_error(ole_read(ole, "data"), "larger than the file")
  ole <- ole_open(patch_cfb(path, truncate = 7880))
  expect_error(ole_read(ole, "data"), "truncated")
  expect_error(ole_open(patch_cfb(path, 32, cfb_u16(7))), "sector size")
  expect_error(ole_open(patch_cfb(path, 44, cfb_i32(0))), "header .* is corrupt")
  expect_error(ole_open(patch_cfb(path, 44, as.raw(c(0, 0, 0, 0x80)))),
               "header .* is corrupt")
  expect_error(ole_open(patch_cfb(path, 76, cfb_i32(15))),
               "sector allocation table .* is corrupt")
  expect_error(ole_open(patch_cfb(path, 1090, as.raw(1))),
               "directory .* is corrupt")
})

test_that("a loop in the DIFAT chain gives an error", {
  tmp <- make_cfb(withr::local_tempfile(), data_size = 16e6)
  header <- readBin(tmp, "raw", 512)
  first <- readBin(header[69:72], "integer", endian = "little")
  looped <- patch_cfb(tmp, (first + 1) * 512 + 508, cfb_i32(first))
  expect_error(ole_open(looped), "sector allocation table .* is corrupt")
  expect_error(ole_open(patch_cfb(tmp, 68, cfb_i32(-2))),
               "sector allocation table .* is corrupt")
})

test_that("the mini stream cutoff in the header is ignored", {
  ole <- ole_open(patch_cfb(path, 56, cfb_i32(0)))
  expect_identical(rawToChar(ole_read(ole, "notes/readme")), README_TEXT)
})

test_that("ole_extract refuses streams that share sectors", {
  shared <- patch_cfb(path, 1524, c(cfb_i32(4), cfb_i32(5000)))
  ole <- ole_open(shared)
  dir <- withr::local_tempfile()
  expect_error(ole_extract(ole, dir), "share sectors")
  expect_false(dir.exists(dir))
})

test_that("ole_extract stops when a file stands where a folder must go", {
  ole <- ole_open(path)
  dir <- withr::local_tempfile()
  dir.create(dir)
  file.create(file.path(dir, "notes"))
  expect_error(ole_extract(ole, dir), "Could not create the folder")
})

test_that("ole_extract treats a dangling link as an existing file", {
  ole <- ole_open(path)
  dir <- withr::local_tempfile()
  dir.create(dir)
  skip_if_not(file.symlink(withr::local_tempfile(), file.path(dir, "data")))
  expect_error(ole_extract(ole, dir), "already exists")
})

test_that("ole_extract extracts nothing when given no streams", {
  ole <- ole_open(path)
  dir <- withr::local_tempfile()
  expect_length(ole_extract(ole, dir, streams = character(0)), 0)
  expect_false(dir.exists(dir))
})
test_that("a file written by Microsoft Word is read like olefile reads it", {
  expected <- data.frame(
    stream = c(
      "\001CompObj", "\005DocumentSummaryInformation", "\005SummaryInformation",
      "1Table", "Data", "ObjectPool/_1854656354/\001CompObj",
      "ObjectPool/_1854656354/\001Ole", "ObjectPool/_1854656354/\003ObjInfo",
      "ObjectPool/_1854656354/\003PRINT",
      "ObjectPool/_1854656354/\005DocumentSummaryInformation",
      "ObjectPool/_1854656354/\005SummaryInformation",
      "ObjectPool/_1854656354/Workbook", "WordDocument"),
    size = c(114, 3928, 420, 10522, 28554, 101, 20, 6, 10783, 244, 228, 16018,
             28206),
    md5 = c("367e9d6e505ece35eba2c1469c5cd664", "ef8e6029fe056ed60c18022598fd173e",
            "5a3e7ad92c511a6dc38fd44dcb429864", "d2813c9ebaa627b5b68ea1d46bf32a06",
            "c3aea66db1801cf0e4b44f5f9b939130", "ccb6f29232875b258c29f32b47a67a4f",
            "d7cb3e7f1923e4e95708b4d8a7fab3db", "44d70a3aab3b791c1ac931080aefecea",
            "122f6dcb392fa5c4a64d958073aae9ba", "dad2cbb019056fc050a82aa41347a635",
            "0fb1cc9684a1d84e3a2fa0193d9cb935", "2646ffa2fcef86ccef73e603bca97539",
            "c49ce3ca429fe5c0dea96e8b1ca3aac4"))
  ole <- ole_open(test_path("fixtures", "carmen.doc"))
  streams <- ole_streams(ole)
  expect_identical(names(streams), expected$stream)
  expect_identical(unname(vapply(streams, ole_size, 0, ole = ole)), expected$size)
  files <- ole_extract(ole, withr::local_tempfile())
  expect_identical(unname(tools::md5sum(files[expected$stream])), expected$md5)
})

test_that("ole_extract refuses sibling streams whose names differ only in case", {
  name <- cfb_pad(iconv("DATA", "UTF-8", "UTF-16LE", toRaw = TRUE)[[1]], 64)
  twins <- patch_cfb(path, 1280, c(name, cfb_u16(10), as.raw(2)))
  twins <- patch_cfb(twins, 1396, c(cfb_i32(0), cfb_i32(101)))
  ole <- ole_open(twins)
  expect_identical(names(ole_streams(ole)), c("DATA", "data"))
  dir <- withr::local_tempfile()
  expect_error(ole_extract(ole, dir), "same file as another stream")
  expect_false(dir.exists(dir))
})


test_that("chains that leave the file or end early give errors", {
  ole <- ole_open(patch_cfb(path, 544, cfb_i32(100)))
  expect_error(ole_read(ole, "data"), "points outside the file")
  ole <- ole_open(patch_cfb(path, 544, cfb_i32(-1)))
  expect_error(ole_read(ole, "data"), "ends before the stream does")
})

test_that("a directory cut short gives an error", {
  bytes <- c(cfb_entry("Root Entry", 5, child = 1),
             cfb_entry("data", 2, right = 2))
  expect_error(ole_directory(bytes, 3), "past the end of the directory")
  cut <- patch_cfb(test_path("fixtures", "carmen.doc"),
                   truncate = 175 * 512 + 256)
  expect_error(ole_open(cut), "past the end of the directory")
})

test_that("a loop among siblings lists each stream once", {
  ole <- ole_open(patch_cfb(path, 1352, cfb_i32(1)))
  expect_identical(names(ole_streams(ole)), c("data", "notes/readme"))
})

test_that("a name containing / is reached only through a list", {
  bytes <- c(cfb_entry("Root Entry", 5, child = 1),
             cfb_entry("a/b", 2, right = 2, size = 1),
             cfb_entry("a", 1, child = 3),
             cfb_entry("b", 2, size = 2))
  ole <- list(dir = ole_directory(bytes, 3))
  expect_identical(unname(ole_streams(ole)), list(c("a", "b"), "a/b"))
  expect_identical(ole_size(ole, "a/b"), 2)
  expect_identical(ole_size(ole, list("a/b")), 1)
  expect_identical(ole_size(ole, ole_streams(ole)[2]), 1)
})

test_that("only the letters A to Z are matched ignoring case", {
  bytes <- c(cfb_entry("Root Entry", 5, child = 1),
             cfb_entry("\u00e9", 2, size = 1))
  ole <- list(dir = ole_directory(bytes, 3))
  expect_identical(ole_size(ole, "\u00e9"), 1)
  expect_identical(ole_size(ole, "\u00c9"), 0)
})

test_that("ole_size gives 0 for a storage with a recorded size", {
  ole <- ole_open(patch_cfb(path, 1400, cfb_i32(10)))
  expect_identical(ole_size(ole, "notes"), 0)
})

test_that("paths must be character vectors without NA", {
  ole <- ole_open(path)
  expect_error(ole_read(ole, character(0)), "must be a character vector")
  expect_error(ole_size(ole, NA_character_), "must be a character vector")
  expect_error(ole_read(ole, c("notes", NA)), "must be a character vector")
})

test_that("a broken mini stream does not stop FAT streams being read", {
  ole <- ole_open(patch_cfb(path, 1144, cfb_i32(1e6)))
  expect_identical(ole_read(ole, "data"), as.raw(rep_len(0:255, 5000)))
  expect_error(ole_read(ole, "notes/readme"), "mini stream .* larger")
  ole <- ole_open(patch_cfb(patch_cfb(path, 1144, cfb_i32(1e6)), 1528,
                            cfb_i32(0)))
  expect_identical(ole_read(ole, "notes/readme"), raw(0))
  ole <- ole_open(patch_cfb(path, 1524, cfb_i32(c(8, 50))))
  expect_error(ole_read(ole, "notes/readme"), "truncated")
  past <- patch_cfb(path, 1524, cfb_i32(c(8, 50)))
  ole <- ole_open(patch_cfb(past, 524, cfb_i32(4)))
  expect_error(ole_read(ole, "notes/readme"), "truncated")
})

test_that("empty streams and files without a mini stream are read", {
  empty <- patch_cfb(path, 1528, cfb_i32(0))
  expect_identical(ole_read(ole_open(empty), "notes/readme"), raw(0))
  nomini <- patch_cfb(empty, 60, cfb_i32(c(-2, 0)))
  nomini <- patch_cfb(nomini, 1140, cfb_i32(c(-2, 0)))
  ole <- ole_open(nomini)
  expect_length(ole$minifat, 0)
  expect_identical(ole_read(ole, "data"), as.raw(rep_len(0:255, 5000)))
  expect_identical(ole_read(ole, "notes/readme"), raw(0))
  ole <- ole_open(patch_cfb(patch_cfb(path, 60, cfb_i32(c(-2, 0))), 1140,
                            cfb_i32(c(-2, 0))))
  expect_error(ole_read(ole, "notes/readme"), "larger than the file")
})

test_that("a file cut short after it was opened gives an error", {
  tmp <- withr::local_tempfile()
  file.copy(path, tmp)
  ole <- ole_open(tmp)
  writeBin(readBin(tmp, "raw", 7000), tmp)
  expect_error(ole_read(ole, "data"), "truncated")
})

test_that("ole_extract writes a stream named twice only once", {
  ole <- ole_open(path)
  files <- ole_extract(ole, withr::local_tempfile(), streams = c("data", "DATA"))
  expect_named(files, "data")
})
