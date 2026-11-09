#!/usr/bin/env Rscript

## Read Google spreadsheet and generate csv file for ERDDAP

# Required libraries
# install.packages(c("googlesheets4", "gargle", "readr", "stringr", "lubridate"))
suppressPackageStartupMessages({
  library(googlesheets4)
  library(gargle)
  library(readr)
  library(stringr)
  library(lubridate)
})

# File paths
out_file <- "/data/FED/thiamine/FED_salmon_thiamine.csv"
tmp_out_file <- "/data/FED/thiamine/thiamine_tmp.csv"
client_secret_path <- file.path(getwd(), "client_secret.json")
token_cache_dir <- path.expand("~/.credentials")

# Target Google Sheet
file_id <- "1ST2HrakqMt_LjBa4ApcQQbRL-JE5MRqcNLWilMQEDII"
sheet_name <- "thiamine database"

# Configure OAuth authentication
# Pointing to the client_secret.json and token caching directory
if (file.exists(client_secret_path)) {
  gs4_auth_configure(path = client_secret_path)
}

# Authenticate (requests OAuth scope for read-only access and caches token)
gs4_auth(
  scopes = "https://www.googleapis.com/auth/spreadsheets.readonly",
  cache = token_cache_dir
)

# Read the sheet as raw text to preserve formats for date manipulation
# (col_types = "c" ensures everything loads as character strings)
df <- tryCatch({
  data <- read_sheet(
    ss = file_id,
    sheet = sheet_name,
    col_types = "c"
  )
  
  valid_cols <- !is.na(names(data)) & 
                names(data) != "" & 
                !grepl("^\\.\\.\\.[0-9]+$", names(data))
  
  data[, valid_cols, drop = FALSE]
}, error = function(e) {
  stop("Failed to read Google Sheet: ", e$message)
})
# Print column indices and names (matches PHP: print($i." ".$content[0][$i]."\n"))
for (i in seq_along(names(df))) {
  cat((i - 1), names(df)[i], "\n")
}

# Helper function to convert M/D/Y to YYYY-MM-DD (matches PHP logic)
format_date_col <- function(col_values) {
  sapply(col_values, function(val) {
    if (!is.na(val) && str_detect(val, "/")) {
      parts <- str_split(val, "/")[[1]]
      if (length(parts) == 3) {
        month <- str_pad(parts[1], 2, pad = "0")
        day   <- str_pad(parts[2], 2, pad = "0")
        year  <- parts[3]
        return(paste(year, month, day, sep = "-"))
      }
    }
    return(val)
  }, USE.NAMES = FALSE)
}

# PHP 0-indexed column 7  -> R 1-indexed column 8  (collection_date)
# PHP 0-indexed column 31 -> R 1-indexed column 32 (release_date)
timecol <- 8
rtimecol <- 32

if (ncol(df) >= timecol) {
  df[[timecol]] <- format_date_col(df[[timecol]])
}

if (ncol(df) >= rtimecol) {
  df[[rtimecol]] <- format_date_col(df[[rtimecol]])
}

# Ensure destination directory exists
dir.create(dirname(tmp_out_file), recursive = TRUE, showWarnings = FALSE)

# Write out the CSV file
write_csv(df, file = tmp_out_file, na = "")

# File move/cleanup logic (matches PHP filesize check > 2 bytes)
if (file.exists(tmp_out_file) && file.info(tmp_out_file)$size > 2) {
  file.rename(tmp_out_file, out_file)
} else if (file.exists(tmp_out_file)) {
  file.remove(tmp_out_file)
}

