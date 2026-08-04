source("R/utils.R")
ensure_project_root()
ensure_dirs()

library(readr)
library(dplyr)
library(tidyr)
library(lubridate)
library(purrr)

sample_start <- as.Date("2017-01-01")

series_map <- tibble::tribble(
  ~series_id, ~variable,
  "CBBTCUSD", "btc_price",
  "SP500", "sp500",
  "NASDAQCOM", "nasdaq",
  "VIXCLS", "vix",
  "DGS10", "dgs10",
  "DTWEXBGS", "dollar_index"
)

read_fred_series <- function(series_id, variable) {
  path <- file.path("data", "raw", paste0(series_id, ".csv"))
  if (!file.exists(path)) {
    stop("Missing raw file: ", path, ". Run R/01_download_data.R first.")
  }

  data <- readr::read_csv(path, na = c(".", ""), show_col_types = FALSE)
  names(data) <- c("date", variable)

  data %>%
    mutate(
      date = as.Date(date),
      across(-date, as.numeric)
    )
}

level_data <- purrr::map2(series_map$series_id, series_map$variable, read_fred_series) %>%
  purrr::reduce(full_join, by = "date") %>%
  arrange(date) %>%
  filter(date >= sample_start)

readr::write_csv(level_data, file.path("data", "processed", "fred_levels_daily.csv"))

core_data <- level_data %>%
  filter(!is.na(btc_price), !is.na(sp500), !is.na(vix), !is.na(dgs10)) %>%
  arrange(date)

return_data <- core_data %>%
  mutate(
    btc_return = 100 * (log(btc_price) - log(lag(btc_price))),
    sp500_return = 100 * (log(sp500) - log(lag(sp500))),
    nasdaq_return = 100 * (log(nasdaq) - log(lag(nasdaq))),
    dollar_index_return = 100 * (log(dollar_index) - log(lag(dollar_index))),
    vix_change = vix - lag(vix),
    dgs10_change = dgs10 - lag(dgs10)
  ) %>%
  filter(!is.na(btc_return), !is.na(sp500_return), !is.na(vix_change), !is.na(dgs10_change))

readr::write_csv(return_data, file.path("data", "processed", "bitcoin_market_returns.csv"))

sample_info <- tibble::tibble(
  item = c("sample_start", "sample_end", "observations", "core_business_day_series"),
  value = c(
    as.character(min(return_data$date)),
    as.character(max(return_data$date)),
    as.character(nrow(return_data)),
    "btc_return, sp500_return, vix_change, dgs10_change"
  )
)

readr::write_csv(sample_info, file.path("output", "tables", "sample_info.csv"))

message("Processed data saved in data/processed.")

