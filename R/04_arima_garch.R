source("R/utils.R")
ensure_project_root()
ensure_dirs()

library(readr)
library(dplyr)
library(ggplot2)
library(forecast)
library(tseries)
library(FinTS)

return_data <- readr::read_csv(file.path("data", "processed", "bitcoin_market_returns.csv"), show_col_types = FALSE) %>%
  mutate(date = as.Date(date)) %>%
  filter(is.finite(btc_return)) %>%
  arrange(date)

btc_returns <- return_data$btc_return
dates <- return_data$date

test_n <- min(252, floor(0.20 * length(btc_returns)))
train_n <- length(btc_returns) - test_n

train_returns <- btc_returns[seq_len(train_n)]
test_returns <- btc_returns[(train_n + 1):length(btc_returns)]
test_dates <- dates[(train_n + 1):length(dates)]

set.seed(123)

arima_fit <- forecast::auto.arima(
  train_returns,
  seasonal = FALSE,
  stepwise = FALSE,
  approximation = FALSE,
  max.p = 5,
  max.q = 5,
  allowdrift = TRUE,
  allowmean = TRUE
)

write_model_summary(arima_fit, "arima_summary.txt")

arima_forecast <- forecast::forecast(arima_fit, h = test_n)
arima_accuracy <- forecast::accuracy(arima_forecast, test_returns) %>%
  as.data.frame() %>%
  tibble::rownames_to_column("sample")

readr::write_csv(arima_accuracy, file.path("output", "tables", "arima_forecast_accuracy.csv"))

arima_residuals <- as.numeric(stats::residuals(arima_fit))

arima_diagnostics <- tibble::tibble(
  test = c("Ljung-Box residual autocorrelation", "ARCH effects in ARIMA residuals"),
  statistic = c(
    unname(stats::Box.test(arima_residuals, lag = 20, type = "Ljung-Box")$statistic),
    unname(FinTS::ArchTest(arima_residuals, lags = 12)$statistic)
  ),
  p_value = c(
    stats::Box.test(arima_residuals, lag = 20, type = "Ljung-Box")$p.value,
    FinTS::ArchTest(arima_residuals, lags = 12)$p.value
  )
)

readr::write_csv(arima_diagnostics, file.path("output", "tables", "arima_diagnostics.csv"))

forecast_plot_data <- tibble::tibble(
  date = test_dates,
  actual = test_returns,
  forecast = as.numeric(arima_forecast$mean),
  lower_80 = as.numeric(arima_forecast$lower[, "80%"]),
  upper_80 = as.numeric(arima_forecast$upper[, "80%"]),
  lower_95 = as.numeric(arima_forecast$lower[, "95%"]),
  upper_95 = as.numeric(arima_forecast$upper[, "95%"])
)

readr::write_csv(forecast_plot_data, file.path("output", "tables", "arima_forecasts.csv"))

p_forecast <- ggplot(forecast_plot_data, aes(x = date)) +
  geom_ribbon(aes(ymin = lower_95, ymax = upper_95), fill = "#b8c7dd", alpha = 0.45) +
  geom_ribbon(aes(ymin = lower_80, ymax = upper_80), fill = "#7998c7", alpha = 0.45) +
  geom_line(aes(y = actual), color = "#222222", linewidth = 0.35) +
  geom_line(aes(y = forecast), color = "#225ea8", linewidth = 0.6) +
  geom_hline(yintercept = 0, color = "grey70", linewidth = 0.25) +
  labs(x = NULL, y = "Bitcoin daily return (%)") +
  theme_minimal(base_size = 11)

save_plot(p_forecast, "arima_forecast_test_sample.png")

garch_input <- train_returns - mean(train_returns, na.rm = TRUE)

garch_fit <- tryCatch(
  tseries::garch(garch_input, order = c(1, 1), trace = FALSE),
  error = function(e) e
)

if (inherits(garch_fit, "error")) {
  writeLines(
    paste("GARCH estimation failed:", garch_fit$message),
    con = file.path("output", "model_summaries", "garch_summary.txt")
  )
  garch_table <- tibble::tibble(
    coefficient = NA_character_,
    estimate = NA_real_,
    note = paste("GARCH estimation failed:", garch_fit$message)
  )
} else {
  capture.output(print(summary(garch_fit)), file = file.path("output", "model_summaries", "garch_summary.txt"))
  garch_table <- tibble::tibble(
    coefficient = names(stats::coef(garch_fit)),
    estimate = as.numeric(stats::coef(garch_fit)),
    note = NA_character_
  )
}

readr::write_csv(garch_table, file.path("output", "tables", "garch_coefficients.csv"))

message("ARIMA and GARCH outputs saved in output.")

