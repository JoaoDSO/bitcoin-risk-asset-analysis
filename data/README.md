# Data

The project uses public daily CSV downloads from FRED, Federal Reserve Bank of St. Louis.

The scripts create two data folders:

- `raw/`: downloaded FRED series and metadata
- `processed/`: cleaned level data and transformed return/change data

No FRED API key is required. To recreate the data, run the project workflow from the repository root:

```r
source("R/run_all.R")
```

The saved outputs in this repository were produced from a sample ending on 2026-05-21. Because the source data are downloaded live, future runs may produce updated samples or slightly different results.
