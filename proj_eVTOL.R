setwd("C:/Users/Siva Lakshmi Veesam/OneDrive/Desktop/ONM")

library(ggplot2)
library(dplyr)
library(lubridate)

weather_data <- read.csv("VOBL.csv", stringsAsFactors = FALSE, na.strings = "M")

weather_clean <- weather_data %>%
  mutate(sknt = as.numeric(sknt),
         drct = as.numeric(drct)) %>%
  filter(!is.na(sknt), !is.na(drct)) %>%
  mutate(wind_speed_ms = sknt * 0.51444) %>%
  mutate(headwind_w = wind_speed_ms * cos((drct - 10) * pi / 180))

real_mu <- mean(weather_clean$headwind_w)
real_variance <- var(weather_clean$headwind_w)

cat("Real Mean:", real_mu, "\n")
cat("Real Variance:", real_variance, "\n")

p1 <- ggplot(weather_clean, aes(x = headwind_w)) +
  geom_histogram(aes(y = after_stat(density)), bins = 50, fill = "#2c3e50", color = "black", alpha = 0.7) +
  stat_function(fun = dnorm, args = list(mean = real_mu, sd = sqrt(real_variance)), color = "black", linewidth = 1.2) +
  labs(title = "Real Distribution of Headwinds (Route 1)", x = "Headwind (m/s)", y = "Density") +
  theme_minimal()

ggsave("chart1.png", plot = p1, width = 8, height = 5, dpi = 300)

weather_clean <- weather_clean %>%
  mutate(
    headwind_w2 = wind_speed_ms * cos((drct - 315) * pi / 180),
    
    headwind_w3 = wind_speed_ms * cos((drct - 45) * pi / 180),
    
    month_name = month(ymd_hm(valid), label = TRUE, abbr = TRUE)
  )

mu_wind <- c(mean(weather_clean$headwind_w), 
             mean(weather_clean$headwind_w2), 
             mean(weather_clean$headwind_w3))

sigma_sq_wind <- c(var(weather_clean$headwind_w), 
                   var(weather_clean$headwind_w2), 
                   var(weather_clean$headwind_w3))

monthly_variance <- weather_clean %>%
  group_by(month_name) %>%
  summarize(variance = var(headwind_w, na.rm = TRUE)) %>%
  filter(!is.na(month_name))

p2 <- ggplot(monthly_variance, aes(x = month_name, y = variance, group = 1)) +
  geom_line(color = "#e74c3c", linewidth = 1.5) +
  geom_point(color = "#e74c3c", size = 4) +
  geom_area(fill = "#e74c3c", alpha = 0.1) +
  labs(title = "Real Monthly Wind Variance (VOBL Data)", 
       x = "Month", 
       y = expression("Variance (" * sigma^2 * ")")) +
  theme_minimal(base_size = 14) +
  ylim(0, max(monthly_variance$variance) * 1.2)

ggsave("chart2.png", plot = p2, width = 8, height = 5, dpi = 300)

routes <- c('Electronic City -> KIA', 'Whitefield -> KIA', 'Kengeri -> KIA')
distances_m <- c(45000.0, 35000.0, 40000.0) 
k_drag <- 0.015 
T_max <- 1800.0 

# The Expected Energy Objective Function
expected_energy <- function(v) {
  # Formula: (v - mu)^3 + 3(v - mu)sigma^2
  expected_drag_factor <- (v - mu_wind)^3 + 3 * (v - mu_wind) * sigma_sq_wind
  time_in_air <- distances_m / v
  energy_per_route <- k_drag * expected_drag_factor * time_in_air
  return(sum(energy_per_route))
}

# The Constraints
min_speed_time <- distances_m / T_max
min_speed_wind <- mu_wind + 5.0 # Must fly 5 m/s faster than mean wind
lower_bounds <- pmax(min_speed_time, min_speed_wind)

initial_guess <- c(30.0, 30.0, 30.0)

cat("\nStarting Convex Optimization with REAL Bangalore Data...\n")
result <- optim(
  par = initial_guess,
  fn = expected_energy,
  method = "L-BFGS-B",  
  lower = lower_bounds,
  control = list(trace = 0) 
)

if(result$convergence == 0) {
  optimal_speeds_ms <- result$par
  optimal_speeds_kmh <- optimal_speeds_ms * 3.6
  
  for(i in 1:3) {
    cat(sprintf("\nRoute %d: %s\n", i, routes[i]))
    cat(sprintf("  -> Real Mean Headwind: %.2f m/s | Real Variance: %.2f\n", mu_wind[i], sigma_sq_wind[i]))
    cat(sprintf("  -> Optimal Airspeed: %.2f m/s (%.2f km/h)\n", optimal_speeds_ms[i], optimal_speeds_kmh[i]))
    cat(sprintf("  -> Expected Flight Time: %.1f minutes\n", (distances_m[i] / optimal_speeds_ms[i]) / 60))
  }
} else {
  cat("Optimization Failed. Convergence code:", result$convergence, "\n")
}

