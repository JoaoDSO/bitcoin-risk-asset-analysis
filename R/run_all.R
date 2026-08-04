source("R/utils.R")
ensure_project_root()
ensure_dirs()

message("Running reproducible Bitcoin project workflow from: ", getwd())

source("R/00_setup.R")
source("R/01_download_data.R")
source("R/02_prepare_data.R")
source("R/03_descriptives.R")
source("R/04_arima_garch.R")
source("R/05_var_analysis.R")

message("Done. Check data/processed, output/tables, output/figures, and output/model_summaries.")

