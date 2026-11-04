# Tables 3 and 4 from the thesis, plus the CAR difference chart.
# Runs on data/car_by_firm.csv, which is included, so this step works
# without WRDS access.

library(dplyr)
library(tidyr)
library(readr)
library(ggplot2)

car <- read_csv("data/car_by_firm.csv", show_col_types = FALSE) %>%
  mutate(year = substr(event, 1, 4))

# ---- Table 3: is mean CAR different from zero within each group? ----

one_sample <- function(x) {
  tt <- t.test(x, mu = 0)
  tibble(N = length(x), mean_car = mean(x), sd = sd(x),
         t = unname(tt$statistic), p = tt$p.value,
         pct_positive = mean(x > 0))
}

table3 <- car %>%
  bind_rows(car %>% mutate(group = "All")) %>%
  group_by(year, window, group) %>%
  reframe(one_sample(CAR)) %>%
  mutate(group = factor(group, c("All", "Connected", "Nonconnected"))) %>%
  arrange(year, group, window)

# ---- Table 4: connected vs. nonconnected (Welch two-sample t-test) ----

two_sample <- function(df) {
  a <- df$CAR[df$group == "Connected"]
  b <- df$CAR[df$group == "Nonconnected"]
  tt <- t.test(a, b)
  tibble(mean_connected = mean(a), mean_nonconnected = mean(b),
         diff = mean(a) - mean(b),
         ci_low = tt$conf.int[1], ci_high = tt$conf.int[2],
         t = unname(tt$statistic), p = tt$p.value)
}

table4 <- car %>%
  group_by(year, window) %>%
  group_modify(~ two_sample(.x)) %>%
  ungroup()

dir.create("output", showWarnings = FALSE)
write_csv(table3, "output/table3_one_sample.csv")
write_csv(table4, "output/table4_two_sample.csv")

print(table4 %>% mutate(across(where(is.numeric), ~ round(.x, 4))), width = Inf)

# ---- Chart ----

plot_df <- table4 %>%
  mutate(window = factor(paste0("[0,", window, "]"), c("[0,5]", "[0,10]", "[0,20]")),
         label = paste0(round(diff * 100, 1), "%", ifelse(p < 0.05, " *", "")))

p <- ggplot(plot_df, aes(window, diff * 100, fill = year)) +
  geom_col(position = position_dodge(0.8), width = 0.7) +
  geom_errorbar(aes(ymin = ci_low * 100, ymax = ci_high * 100),
                position = position_dodge(0.8), width = 0.2, colour = "grey30") +
  geom_text(aes(y = ci_high * 100 + 0.6, label = label),
            position = position_dodge(0.8), size = 3.2) +
  geom_hline(yintercept = 0, colour = "grey40") +
  scale_fill_manual(values = c("2020" = "#00274C", "2024" = "#FFCB05"), name = "Election") +
  labs(x = "Event window (trading days)",
       y = "Mean CAR gap (pts)",
       title = "Abnormal return gap after the 2020 and 2024 elections",
       caption = "Bars: mean difference. Error bars: 95% CI (Welch). * p < 0.05") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.x = element_blank(), legend.position = "bottom")

dir.create("figures", showWarnings = FALSE)
ggsave("figures/car_difference.png", p, width = 7, height = 4.2, dpi = 150)
