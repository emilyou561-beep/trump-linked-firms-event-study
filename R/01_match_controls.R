# Match each Trump-connected firm to the two closest firms by market cap
# in the same 2-digit SIC sector, using Compustat Fundamentals Annual (FY2020).
#
# Input:  data/raw/compustat_fy2020.csv  (WRDS export, not included in the repo)
# Output: data/control_firms.csv

library(dplyr)
library(readr)

connected <- read_csv("data/connected_firms.csv", show_col_types = FALSE)

compustat <- read_csv("data/raw/compustat_fy2020.csv", show_col_types = FALSE)

firms <- compustat %>%
  filter(grepl("2020", datadate)) %>%
  filter(!is.na(mkvalt), mkvalt > 0) %>%
  mutate(sich = as.numeric(sich)) %>%
  filter(!is.na(sich)) %>%
  group_by(tic) %>%
  slice_max(datadate, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  mutate(sic2 = floor(sich / 100))

targets    <- firms %>% filter(tic %in% connected$ticker)
candidates <- firms %>% filter(!tic %in% connected$ticker)

missing <- setdiff(connected$ticker, targets$tic)
if (length(missing) > 0) {
  message("Not found in Compustat (check ticker / match by hand): ",
          paste(missing, collapse = ", "))
}

find_matches <- function(target, pool, n = 2) {
  same_sector <- pool %>% filter(sic2 == target$sic2)

  if (nrow(same_sector) < n) {
    message(target$tic, ": only ", nrow(same_sector),
            " candidates in SIC ", target$sic2)
  }
  if (nrow(same_sector) == 0) return(NULL)

  same_sector %>%
    mutate(mkvalt_diff  = abs(mkvalt - target$mkvalt),
           mkvalt_ratio = mkvalt / target$mkvalt) %>%
    arrange(mkvalt_diff) %>%
    slice_head(n = n) %>%
    mutate(matched_to = target$tic)
}

matches <- bind_rows(lapply(seq_len(nrow(targets)),
                            function(i) find_matches(targets[i, ], candidates)))

cat("Control rows:", nrow(matches), "\n")
cat("Unique control firms:", n_distinct(matches$tic), "\n")
cat("Connected firms matched:", n_distinct(matches$matched_to), "\n")

# A control can be the closest match for more than one target
# (e.g. two big banks). It's kept once in the CAR sample.
matches %>%
  select(ticker = tic, company = conm, matched_to, sic2) %>%
  write_csv("data/control_firms.csv")
