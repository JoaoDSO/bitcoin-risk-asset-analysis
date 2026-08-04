source("R/utils.R")
ensure_project_root()
ensure_dirs()

library(readr)
library(dplyr)
library(tibble)

series_map <- tibble::tribble(
  ~series_id, ~variable, ~description,
  "CBBTCUSD", "btc_price", "Coinbase Bitcoin price in U.S. dollars",
  "SP500", "sp500", "S&P 500 index",
  "NASDAQCOM", "nasdaq", "Nasdaq Composite index",
  "VIXCLS", "vix", "CBOE Volatility Index: VIX",
  "DGS10", "dgs10", "10-year U.S. Treasury constant maturity yield",
  "DTWEXBGS", "dollar_index", "Nominal broad U.S. dollar index"
)

fred_url <- function(series_id) {
  paste0("https://fred.stlouisfed.org/graph/fredgraph.csv?id=", series_id)
}

download_one_series <- function(series_id) {
  url <- fred_url(series_id)
  dest <- file.path("data", "raw", paste0(series_id, ".csv"))
  message("Downloading ", series_id, " from ", url)
  utils::download.file(url = url, destfile = dest, mode = "wb", quiet = FALSE)
  dest
}

downloaded_files <- vapply(series_map$series_id, download_one_series, character(1))

metadata <- series_map %>%
  mutate(
    source = "FRED, Federal Reserve Bank of St. Louis",
    url = fred_url(series_id),
    raw_file = downloaded_files,
    downloaded_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )

readr::write_csv(metadata, file.path("data", "raw", "fred_metadata.csv"))

message("Raw data and metadata saved in data/raw.")

