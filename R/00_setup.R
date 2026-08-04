required_packages <- c(
  "readr",
  "dplyr",
  "tidyr",
  "purrr",
  "tibble",
  "lubridate",
  "ggplot2",
  "forecast",
  "tseries",
  "vars",
  "FinTS",
  "knitr"
)

user_library <- Sys.getenv("R_LIBS_USER")
if (!dir.exists(user_library)) {
  dir.create(user_library, recursive = TRUE, showWarnings = FALSE)
}

.libPaths(unique(c(user_library, .libPaths())))

missing_packages <- setdiff(required_packages, rownames(installed.packages()))

if (length(missing_packages) > 0) {
  install.packages(
    missing_packages,
    lib = user_library,
    repos = "https://cloud.r-project.org",
    dependencies = TRUE
  )
}

invisible(lapply(required_packages, library, character.only = TRUE))
