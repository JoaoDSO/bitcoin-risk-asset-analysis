source("R/utils.R")
ensure_project_root()
ensure_dirs()

library(readr)
library(dplyr)
library(tidyr)
library(ggplot2)
library(vars)

return_data <- readr::read_csv(file.path("data", "processed", "bitcoin_market_returns.csv"), show_col_types = FALSE) %>%
  mutate(date = as.Date(date)) %>%
  arrange(date)

var_data <- return_data %>%
  dplyr::select(date, sp500_return, vix_change, dgs10_change, btc_return) %>%
  tidyr::drop_na()

var_matrix <- var_data %>%
  dplyr::select(sp500_return, vix_change, dgs10_change, btc_return)

lag_selection <- vars::VARselect(var_matrix, lag.max = 10, type = "const")

lag_table <- as.data.frame(t(lag_selection$criteria)) %>%
  tibble::rownames_to_column("lag")

readr::write_csv(lag_table, file.path("output", "tables", "var_lag_selection.csv"))

selected_lag <- as.integer(lag_selection$selection[["SC(n)"]])
if (is.na(selected_lag) || selected_lag < 1) {
  selected_lag <- 2
}

var_fit <- vars::VAR(var_matrix, p = selected_lag, type = "const")
write_model_summary(var_fit, "var_summary.txt")

make_lagged_data <- function(data, variables, p) {
  out <- data
  for (variable in variables) {
    for (lag in seq_len(p)) {
      out[[paste0(variable, "_l", lag)]] <- dplyr::lag(out[[variable]], lag)
    }
  }
  out %>% tidyr::drop_na()
}

btc_granger_tests <- function(data, variables, p) {
  lagged <- make_lagged_data(data, variables, p)
  all_lag_terms <- unlist(lapply(variables, function(v) paste0(v, "_l", seq_len(p))))

  lapply(setdiff(variables, "btc_return"), function(cause) {
    cause_terms <- paste0(cause, "_l", seq_len(p))
    restricted_terms <- setdiff(all_lag_terms, cause_terms)

    full_formula <- stats::as.formula(paste("btc_return ~", paste(all_lag_terms, collapse = " + ")))
    restricted_formula <- stats::as.formula(paste("btc_return ~", paste(restricted_terms, collapse = " + ")))

    full_model <- stats::lm(full_formula, data = lagged)
    restricted_model <- stats::lm(restricted_formula, data = lagged)
    test <- stats::anova(restricted_model, full_model)

    tibble::tibble(
      null_hypothesis = paste(cause, "does not Granger-cause btc_return"),
      lags = p,
      f_statistic = test$F[2],
      p_value = test$`Pr(>F)`[2]
    )
  }) %>%
    dplyr::bind_rows()
}

granger_btc <- btc_granger_tests(
  data = var_data,
  variables = c("sp500_return", "vix_change", "dgs10_change", "btc_return"),
  p = selected_lag
)

readr::write_csv(granger_btc, file.path("output", "tables", "granger_tests_btc_equation.csv"))

system_causality <- lapply(c("sp500_return", "vix_change", "dgs10_change"), function(cause) {
  test <- vars::causality(var_fit, cause = cause)$Granger
  statistic <- if (!is.null(test$statistic)) {
    unname(test$statistic)
  } else {
    unname(test[["statistic"]])
  }
  p_value <- if (!is.null(test$p.value)) {
    test$p.value
  } else {
    test[["p.value"]]
  }
  tibble::tibble(
    cause = cause,
    test = "VAR system Granger causality",
    statistic = as.numeric(statistic),
    p_value = as.numeric(p_value)
  )
}) %>%
  dplyr::bind_rows()

readr::write_csv(system_causality, file.path("output", "tables", "var_system_granger_tests.csv"))

save_irf <- function(impulse, var_fit, response = "btc_return", n_ahead = 20) {
  set.seed(123)
  ir <- vars::irf(
    var_fit,
    impulse = impulse,
    response = response,
    n.ahead = n_ahead,
    boot = TRUE,
    runs = 500,
    ci = 0.95,
    ortho = TRUE
  )

  extract_irf_series <- function(irf_object, component) {
    matrices <- irf_object[[component]]
    matrix <- matrices[[impulse]]
    if (is.null(matrix)) {
      matrix <- matrices[[1]]
    }
    if (is.null(dim(matrix))) {
      return(as.numeric(matrix))
    }
    column <- if (!is.null(colnames(matrix)) && response %in% colnames(matrix)) {
      response
    } else {
      1
    }
    as.numeric(matrix[, column])
  }

  irf_values <- extract_irf_series(ir, "irf")
  lower_values <- extract_irf_series(ir, "Lower")
  upper_values <- extract_irf_series(ir, "Upper")

  irf_table <- tibble::tibble(
    horizon = seq_along(irf_values) - 1,
    impulse = impulse,
    response = response,
    irf = irf_values,
    lower = lower_values,
    upper = upper_values
  )

  safe_impulse <- gsub("[^A-Za-z0-9]+", "_", impulse)
  readr::write_csv(irf_table, file.path("output", "tables", paste0("irf_", safe_impulse, "_to_btc.csv")))

  p <- ggplot(irf_table, aes(x = horizon, y = irf)) +
    geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#b8c7dd", alpha = 0.5) +
    geom_hline(yintercept = 0, color = "grey60", linewidth = 0.3) +
    geom_line(color = "#225ea8", linewidth = 0.75) +
    labs(x = "Horizon in trading days", y = "Response of Bitcoin return (%)") +
    theme_minimal(base_size = 11)

  save_plot(p, paste0("irf_", safe_impulse, "_to_btc.png"))
  irf_table
}

irf_tables <- lapply(c("sp500_return", "vix_change", "dgs10_change"), save_irf, var_fit = var_fit)

combined_irf_table <- dplyr::bind_rows(irf_tables) %>%
  mutate(
    impulse_label = dplyr::recode(
      impulse,
      sp500_return = "S&P 500 return shock",
      vix_change = "VIX shock",
      dgs10_change = "10-year yield shock"
    )
  )

combined_irf_plot <- ggplot(combined_irf_table, aes(x = horizon, y = irf)) +
  geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#b8c7dd", alpha = 0.5) +
  geom_hline(yintercept = 0, color = "grey60", linewidth = 0.3) +
  geom_line(color = "#225ea8", linewidth = 0.75) +
  facet_wrap(~ impulse_label, scales = "free_y", ncol = 1) +
  labs(x = "Horizon in trading days", y = "Response of Bitcoin return (%)") +
  theme_minimal(base_size = 11) +
  theme(strip.text = element_text(face = "bold"))

save_plot(combined_irf_plot, "combined_irfs_to_btc.png", width = 7.2, height = 7)

var_info <- tibble::tibble(
  item = c("selected_lag", "lag_selection_rule", "variable_order_for_orthogonalized_irfs"),
  value = c(
    as.character(selected_lag),
    "Schwarz information criterion, SC(n)",
    "sp500_return, vix_change, dgs10_change, btc_return"
  )
)

readr::write_csv(var_info, file.path("output", "tables", "var_model_info.csv"))

message("VAR, Granger causality, and impulse response outputs saved in output.")
