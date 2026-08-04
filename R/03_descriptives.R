source("R/utils.R")
ensure_project_root()
ensure_dirs()

library(readr)
library(dplyr)
library(tidyr)
library(ggplot2)
library(tseries)

level_data <- readr::read_csv(file.path("data", "processed", "fred_levels_daily.csv"), show_col_types = FALSE) %>%
  mutate(date = as.Date(date))

return_data <- readr::read_csv(file.path("data", "processed", "bitcoin_market_returns.csv"), show_col_types = FALSE) %>%
  mutate(date = as.Date(date))

analysis_vars <- c("btc_return", "sp500_return", "vix_change", "dgs10_change", "dollar_index_return")

summary_stats <- return_data %>%
  summarise(
    across(
      all_of(analysis_vars),
      list(
        n = ~sum(!is.na(.x)),
        mean = ~mean(.x, na.rm = TRUE),
        sd = ~sd(.x, na.rm = TRUE),
        min = ~min(.x, na.rm = TRUE),
        p25 = ~quantile(.x, 0.25, na.rm = TRUE),
        median = ~median(.x, na.rm = TRUE),
        p75 = ~quantile(.x, 0.75, na.rm = TRUE),
        max = ~max(.x, na.rm = TRUE),
        skewness = ~skewness(.x),
        excesskurtosis = ~excess_kurtosis(.x)
      ),
      .names = "{.col}_{.fn}"
    )
  ) %>%
  pivot_longer(everything(), names_to = "name", values_to = "value") %>%
  tidyr::separate(name, into = c("variable", "statistic"), sep = "_(?=[^_]+$)") %>%
  pivot_wider(names_from = statistic, values_from = value)

readr::write_csv(summary_stats, file.path("output", "tables", "summary_statistics.csv"))

correlation_table <- return_data %>%
  dplyr::select(dplyr::all_of(analysis_vars)) %>%
  stats::cor(use = "pairwise.complete.obs") %>%
  as.data.frame() %>%
  tibble::rownames_to_column("variable")

readr::write_csv(correlation_table, file.path("output", "tables", "correlation_matrix.csv"))

safe_adf <- function(x) {
  x <- x[is.finite(x)]
  tryCatch({
    test <- tseries::adf.test(x, alternative = "stationary")
    c(statistic = unname(test$statistic), p_value = clean_p_value(test$p.value))
  }, error = function(e) c(statistic = NA_real_, p_value = NA_real_))
}

safe_kpss <- function(x) {
  x <- x[is.finite(x)]
  tryCatch({
    test <- tseries::kpss.test(x, null = "Level")
    c(statistic = unname(test$statistic), p_value = clean_p_value(test$p.value))
  }, error = function(e) c(statistic = NA_real_, p_value = NA_real_))
}

unit_root_inputs <- list(
  log_btc_price = log(level_data$btc_price),
  log_sp500 = log(level_data$sp500),
  vix = level_data$vix,
  dgs10 = level_data$dgs10,
  btc_return = return_data$btc_return,
  sp500_return = return_data$sp500_return,
  vix_change = return_data$vix_change,
  dgs10_change = return_data$dgs10_change
)

unit_root_table <- dplyr::bind_rows(lapply(names(unit_root_inputs), function(variable) {
  x <- unit_root_inputs[[variable]]
  adf <- safe_adf(x)
  kpss <- safe_kpss(x)
  data.frame(
    variable = variable,
    adf_statistic = adf[["statistic"]],
    adf_p_value = adf[["p_value"]],
    kpss_statistic = kpss[["statistic"]],
    kpss_p_value = kpss[["p_value"]]
  )
}))

readr::write_csv(unit_root_table, file.path("output", "tables", "unit_root_tests.csv"))

price_plot_data <- level_data %>%
  filter(!is.na(btc_price), !is.na(sp500), !is.na(nasdaq)) %>%
  mutate(
    bitcoin = 100 * btc_price / dplyr::first(btc_price),
    sp500 = 100 * sp500 / dplyr::first(sp500),
    nasdaq = 100 * nasdaq / dplyr::first(nasdaq)
  ) %>%
  dplyr::select(date, bitcoin, sp500, nasdaq) %>%
  pivot_longer(-date, names_to = "series", values_to = "index_value")

p_prices <- ggplot(price_plot_data, aes(x = date, y = index_value, color = series)) +
  geom_line(linewidth = 0.5) +
  labs(x = NULL, y = "Index, first observation = 100", color = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

save_plot(p_prices, "indexed_prices.png")

returns_plot_data <- return_data %>%
  dplyr::select(date, btc_return, sp500_return) %>%
  pivot_longer(-date, names_to = "series", values_to = "return")

p_returns <- ggplot(returns_plot_data, aes(x = date, y = return, color = series)) +
  geom_hline(yintercept = 0, color = "grey70", linewidth = 0.25) +
  geom_line(linewidth = 0.35) +
  labs(x = NULL, y = "Daily log return (%)", color = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

save_plot(p_returns, "bitcoin_vs_sp500_returns.png")

vol_plot_data <- return_data %>%
  mutate(
    btc_rolling_vol = rolling_sd(btc_return, 30) * sqrt(252),
    sp500_rolling_vol = rolling_sd(sp500_return, 30) * sqrt(252)
  ) %>%
  dplyr::select(date, btc_rolling_vol, sp500_rolling_vol) %>%
  pivot_longer(-date, names_to = "series", values_to = "annualized_volatility")

p_vol <- ggplot(vol_plot_data, aes(x = date, y = annualized_volatility, color = series)) +
  geom_line(linewidth = 0.5, na.rm = TRUE) +
  labs(x = NULL, y = "30-day rolling annualized volatility", color = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

save_plot(p_vol, "rolling_volatility.png")

message("Descriptive tables and figures saved in output.")
