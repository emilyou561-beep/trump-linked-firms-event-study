# Cumulative abnormal returns around the 2020 and 2024 elections.
#
# Abnormal return = firm daily return - S&P 500 value-weighted return (CRSP sprtrn).
# Day 0 is the first trading day after the result was called:
#   2020: Nov 9, 2020    2024: Nov 6, 2024
# CAR[0, w] sums abnormal returns from day 0 through day w, for w = 5, 10, 20.
# The 255 trading days before day 0 are used for the pre-event volatility
# reported in the descriptive table.
#
# Input:  data/raw/crsp_daily.csv  (WRDS export: ticker, date, ret, sprtrn; not included)
# Output: data/car_by_firm.csv

library(dplyr)
library(readr)

connected <- read_csv("data/connected_firms.csv", show_col_types = FALSE)
controls  <- read_csv("data/control_firms.csv", show_col_types = FALSE) %>%
  distinct(ticker)

sample_firms <- bind_rows(
  connected %>% transmute(ticker, group = "Connected"),
  controls  %>% transmute(ticker, group = "Nonconnected")
)

crsp <- read_csv("data/raw/crsp_daily.csv", show_col_types = FALSE) %>%
  mutate(date = as.Date(date),
         ret = as.numeric(ret),
         ar = ret - sprtrn) %>%
  inner_join(sample_firms, by = "ticker") %>%
  arrange(ticker, date)

events  <- tibble(event = c("2020_election", "2024_election"),
                  day0  = as.Date(c("2020-11-09", "2024-11-06")))
windows <- c(5, 10, 20)

# trading-day index relative to day 0, per event
trading_days <- sort(unique(crsp$date))

event_window <- function(day0) {
  i0 <- match(day0, trading_days)
  tibble(date = trading_days, rel_day = seq_along(trading_days) - i0)
}

car <- list()
vol <- list()

for (k in seq_len(nrow(events))) {
  ev  <- events$event[k]
  idx <- event_window(events$day0[k])
  d   <- crsp %>% inner_join(idx, by = "date")

  vol[[ev]] <- d %>%
    filter(rel_day >= -255, rel_day < 0) %>%
    group_by(ticker, group) %>%
    summarise(volatility = sd(ret, na.rm = TRUE), .groups = "drop") %>%
    mutate(event = ev)

  for (w in windows) {
    car[[paste(ev, w)]] <- d %>%
      filter(rel_day >= 0, rel_day <= w) %>%
      group_by(ticker, group) %>%
      summarise(CAR = sum(ar, na.rm = TRUE), n_days = n(), .groups = "drop") %>%
      mutate(event = ev, window = w)
  }
}

car <- bind_rows(car)

short <- car %>% filter(n_days < window + 1)
if (nrow(short) > 0) {
  message(nrow(short), " firm-windows have missing trading days, check before using")
}

car %>%
  select(ticker, group, event, window, CAR) %>%
  arrange(event, window, group) %>%
  write_csv("data/car_by_firm.csv")

bind_rows(vol) %>% write_csv("output/pre_event_volatility.csv")
