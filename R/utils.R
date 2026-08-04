ensure_project_root <- function() {
  if (basename(getwd()) == "bitcoin_project") {
    return(invisible(normalizePath(getwd(), winslash = "/")))
  }

  if (dir.exists("bitcoin_project") && file.exists(file.path("bitcoin_project", "R", "run_all.R"))) {
    setwd("bitcoin_project")
    return(invisible(normalizePath(getwd(), winslash = "/")))
  }

  stop("Please run this script from the course folder or from inside bitcoin_project.")
}

ensure_dirs <- function() {
  dirs <- c(
    "data/raw",
    "data/processed",
    "output",
    "output/figures",
    "output/tables",
    "output/model_summaries",
    "report"
  )

  for (dir in dirs) {
    if (!dir.exists(dir)) {
      dir.create(dir, recursive = TRUE)
    }
  }
}

save_plot <- function(plot, filename, width = 8, height = 4.8) {
  ggplot2::ggsave(
    filename = file.path("output", "figures", filename),
    plot = plot,
    width = width,
    height = height,
    dpi = 300
  )
}

write_model_summary <- function(object, filename) {
  path <- file.path("output", "model_summaries", filename)
  capture.output(print(summary(object)), file = path)
}

clean_p_value <- function(x) {
  ifelse(is.na(x), NA_real_, pmax(pmin(as.numeric(x), 1), 0))
}

skewness <- function(x) {
  x <- x[is.finite(x)]
  m <- mean(x)
  s <- stats::sd(x)
  if (length(x) < 3 || s == 0) return(NA_real_)
  mean(((x - m) / s)^3)
}

excess_kurtosis <- function(x) {
  x <- x[is.finite(x)]
  m <- mean(x)
  s <- stats::sd(x)
  if (length(x) < 4 || s == 0) return(NA_real_)
  mean(((x - m) / s)^4) - 3
}

rolling_sd <- function(x, window) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    if (i >= window) {
      out[i] <- stats::sd(x[(i - window + 1):i], na.rm = TRUE)
    }
  }
  out
}

