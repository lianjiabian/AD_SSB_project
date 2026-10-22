# Minimal lossless PDF object reader used only for an existing legend-text edit.
# Scientific graphics are retained; no data or plotting objects are evaluated.
raw_slice <- function(x, a, b) if (b < a) raw() else x[seq.int(a, b)]
raw_text <- function(x) rawToChar(x)
ascii <- function(x) charToRaw(enc2utf8(x))
read_raw <- function(path) readBin(path, "raw", n = file.info(path)$size)
pdf_header <- function(x) {
  k <- grepRaw(ascii("stream\n"), x, all = FALSE)
  if (length(k)) raw_text(raw_slice(x, 1L, k - 1L)) else raw_text(x)
}
pdf_stream <- function(x, resolve = NULL) {
  k <- grepRaw(ascii("stream\n"), x, all = FALSE)
  stopifnot(length(k) == 1L)
  h <- pdf_header(x)
  ref <- regmatches(h, regexpr("/Length [0-9]+ 0 R", h))
  if (length(ref) && nzchar(ref)) {
    stopifnot(!is.null(resolve))
    id <- as.integer(strsplit(ref, " ", fixed = TRUE)[[1]][2])
    n <- as.integer(trimws(raw_text(resolve(id))))
  } else n <- as.integer(sub(".*?/Length ([0-9]+).*", "\\1", h))
  z <- raw_slice(x, k + 7L, k + 6L + n)
  if (grepl("/FlateDecode", h, fixed = TRUE)) memDecompress(z, "gzip") else z
}
read_pdf <- function(path) {
  bytes <- read_raw(path)
  sx <- tail(grepRaw(ascii("startxref"), bytes, all = TRUE), 1L)
  off <- as.integer(strsplit(raw_text(bytes[sx:length(bytes)]), "\n")[[1]][2])
  tail_obj <- bytes[seq.int(off + 1L, length(bytes))]
  h <- pdf_header(tail_obj)
  stopifnot(grepl("/Type /XRef", h, fixed = TRUE))
  size <- as.integer(sub(".*?/Size ([0-9]+).*", "\\1", h))
  widths <- as.integer(strsplit(sub(".*?/W \\[([^]]+)\\].*", "\\1", h), " +")[[1]])
  widths <- widths[!is.na(widths)]
  stopifnot(length(widths) == 3L)
  xr <- matrix(as.integer(pdf_stream(tail_obj)), nrow = sum(widths))
  stopifnot(ncol(xr) == size)
  pos <- cumsum(c(0L, widths))
  val <- sapply(1:3, function(k) colSums(xr[seq.int(pos[k] + 1L, pos[k + 1L]), , drop = FALSE] *
                  256^rev(seq.int(0L, widths[k] - 1L))))
  direct_offsets <- sort(unique(c(val[val[, 1] == 1L, 2], off, length(bytes))))
  cache <- new.env(parent = emptyenv())
  get_obj <- function(id) {
    key <- as.character(id)
    if (exists(key, cache, inherits = FALSE)) return(get(key, cache))
    row <- val[id + 1L, ]
    if (row[1] == 1L) {
      end <- min(direct_offsets[direct_offsets > row[2]])
      z <- bytes[seq.int(row[2] + 1L, end)]
      a <- grepRaw(ascii("obj\n"), z, all = FALSE) + 4L
      b <- tail(grepRaw(ascii("endobj"), z, all = TRUE), 1L) - 1L
      body <- raw_slice(z, a, b)
    } else if (row[1] == 2L) {
      container <- get_obj(row[2])
      ch <- pdf_header(container)
      first <- as.integer(sub(".*?/First ([0-9]+).*", "\\1", ch))
      content <- pdf_stream(container, get_obj)
      table <- as.integer(strsplit(trimws(raw_text(content[seq_len(first)])), "\\s+")[[1]])
      tab <- matrix(table, ncol = 2L, byrow = TRUE)
      idx <- match(id, tab[, 1])
      end <- if (idx == nrow(tab)) length(content) else first + tab[idx + 1L, 2]
      body <- raw_slice(content, first + tab[idx, 2] + 1L, end)
    } else stop("Unused PDF object requested: ", id)
    assign(key, body, cache)
    body
  }
  root <- as.integer(sub(".*?/Root ([0-9]+) 0 R.*", "\\1", h))
  info <- as.integer(sub(".*?/Info ([0-9]+) 0 R.*", "\\1", h))
  list(bytes = bytes, size = size, xref = off, rows = val, get = get_obj,
       root = root, info = info)
}
replace_pdf_refs <- function(x, offset) {
  h <- pdf_header(x)
  hits <- gregexpr("[0-9]+ 0 R", h)[[1]]
  if (hits[1] > 0L) for (i in rev(seq_along(hits))) {
    n <- attr(hits, "match.length")[i]
    old <- substr(h, hits[i], hits[i] + n - 1L)
    repl <- paste(as.integer(strsplit(old, " ", fixed = TRUE)[[1]][1]) + offset, "0 R")
    h <- paste0(substr(h, 1L, hits[i] - 1L), repl, substr(h, hits[i] + n, nchar(h)))
  }
  k <- grepRaw(ascii("stream\n"), x, all = FALSE)
  if (length(k)) c(ascii(h), x[seq.int(k, length(x))]) else ascii(h)
}
stream_object <- function(content) {
  z <- memCompress(ascii(content), "gzip")
  c(ascii(sprintf("<< /Length %d /Filter /FlateDecode >>\nstream\n", length(z))),
    z, ascii("\nendstream\n"))
}
append_pdf_revision <- function(src, objects, file) {
  ids <- sort(as.integer(names(objects)))
  con <- file(file, "wb")
  on.exit(close(con))
  writeBin(src$bytes, con)
  writeBin(ascii("\n% Legend-only incremental revision\n"), con)
  offsets <- setNames(numeric(length(ids)), ids)
  for (id in ids) {
    offsets[as.character(id)] <- seek(con)
    writeBin(ascii(sprintf("%d 0 obj\n", id)), con)
    writeBin(objects[[as.character(id)]], con)
    writeBin(ascii("\nendobj\n"), con)
  }
  xref <- seek(con)
  writeBin(ascii("xref\n0 1\n0000000000 65535 f \n"), con)
  runs <- split(ids, cumsum(c(TRUE, diff(ids) != 1L)))
  for (v in runs) {
    writeBin(ascii(sprintf("%d %d\n", min(v), length(v))), con)
    for (id in v) writeBin(ascii(sprintf("%010.0f 00000 n \n", offsets[as.character(id)])), con)
  }
  footer <- sprintf(paste0("trailer\n<< /Size %d /Root %d 0 R /Info %d 0 R /Prev %d >>\n",
                           "startxref\n%.0f\n%%%%EOF\n"),
                    max(c(src$size - 1L, ids)) + 1L, src$root, src$info, src$xref, xref)
  writeBin(ascii(footer), con)
}
