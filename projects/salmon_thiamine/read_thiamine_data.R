library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(plotly)
library(scales)

get_pretty_stock <- function(hatch, run, yr) {
  hatch_label <- ifelse(is.na(hatch) | hatch == "", "Unknown", hatch)
  run_label <- ifelse(is.na(run) | run == "NA" | run == "", "", paste0(str_to_title(run), " "))
  yr_label <- ifelse(is.na(yr), "", as.character(yr))
  
  str_trim(paste0(str_to_title(hatch_label), " ", run_label, yr_label))
}

read_thiamine_data <- function(file_path = "data/FED_salmon_thiamine.csv") {
  
  status_order <- c("severely impacted", "impacted", "likely impacted", "unlikely impacted")
  
  df <- read.csv(file_path, stringsAsFactors = FALSE)
  
  # Base dataset filtering matching PHP logic
  filtered_df <- df %>%
    filter(
      (is.na(treatment_status) | treatment_status %in% c("NA", "saline")),
      avg_total_egg_thi_nmol_g > 0,
      !is.na(new_status), 
      new_status != ""
    ) %>%
    distinct(sample_id, .keep_all = TRUE)
  
  groups_config <- list(
    list(id = 1, type_val = "ocean fishery", stock_val = "ccv",     species_regex = "all",                 title_type = "boat"),
    list(id = 2, type_val = "hatchery",      stock_val = "ccv",     species_regex = "(chinook|coho)",      title_type = "hatchery"),
    list(id = 3, type_val = "hatchery",      stock_val = "coastal", species_regex = "(chinook|coho)",      title_type = "hatchery"),
    list(id = 4, type_val = "hatchery",      stock_val = "ccv",     species_regex = "(steelhead)",         title_type = "hatchery"),
    list(id = 5, type_val = "hatchery",      stock_val = "coastal", species_regex = "(steelhead)",         title_type = "hatchery")
  )
  
  processed_list <- lapply(groups_config, function(cfg) {
    sub_df <- filtered_df %>%
      filter(collection_type == cfg$type_val, stock == cfg$stock_val)
    
    if (cfg$species_regex != "all") {
      sub_df <- sub_df %>% filter(str_detect(species, cfg$species_regex))
    }
    
    if (nrow(sub_df) == 0) return(NULL)
    
    sub_df <- sub_df %>%
      mutate(boat_label = get_pretty_stock(boat_hatchery, run, year))
    
    boat_levels <- unique(sub_df$boat_label)
    
    sub_df %>%
      mutate(
        group_id = cfg$id,
        title_type = cfg$title_type,
        boat_label = factor(boat_label, levels = boat_levels),
        new_status = factor(new_status, levels = status_order)
      ) %>%
      group_by(group_id, title_type, boat_label, new_status) %>%
      summarise(count = n_distinct(sample_id), .groups = "drop") %>%
      complete(nesting(group_id, title_type), boat_label, new_status, fill = list(count = 0)) %>%
      # CALCULATE EXPLICIT PROPORTIONS (0.00 to 1.00) PER BOAT/HATCHERY
      group_by(group_id, boat_label) %>%
      mutate(
        total_samples = sum(count),
        prop = ifelse(total_samples > 0, count / total_samples, 0)
      ) %>%
      ungroup()
  })
  
  bind_rows(processed_list)
}


thiamine_data <- read_thiamine_data("data/FED_salmon_thiamine.csv")

# Color mapping matching JS colors
status_colors <- c(
  "severely impacted"  = "#660001",
  "impacted"           = "#ce0003",
  "likely impacted"    = "#e7a005",
  "unlikely impacted"  = "#9a9a9a"
)

status_order <- c("severely impacted", "impacted", "likely impacted", "unlikely impacted")
# Height vector matching your JS `hts` array
default_hts <- c(500, 1700, 1100, 800, 700)

plot_thiamine_bar <- function(data, div_idx) {
  
  chart_data <- data %>% filter(group_id == div_idx)
  if (nrow(chart_data) == 0) return(NULL)
  
  # Calculate dynamic height: 120px for margins/title/legend + 28px per boat/hatchery label
  n_rows <- n_distinct(chart_data$boat_label)
  calc_height <- 120 + (n_rows * 28)
  
  # Ensure a minimum height so small charts don't look crushed
  final_height <- max(calc_height, 400)
  group_title <- paste("Thiamine status by", unique(chart_data$title_type))
  
  p <- ggplot(chart_data, aes(
    x = prop, 
    y = boat_label, 
    fill = new_status,
    # SET MOUSEOVER POPUP CONTENT HERE:
    text = paste0(
      "<b>", boat_label, "</b><br>",
      new_status,": ", count," (", number(prop, accuracy = 0.01),")"
    )
  )) +
    # Map directly to 'prop' and use standard stack reversal
    geom_bar(stat = "identity", position = position_stack(reverse = TRUE), width = 0.85) +
    scale_fill_manual(values = status_colors, breaks = status_order) +
    scale_x_continuous(
      labels = label_number(accuracy = 0.01),
      limits = c(0, 1),
      expand = c(0, 0)
    ) +
    labs(
      title = group_title,
      x = "Proportion",
      y = NULL,
      fill = NULL
    ) +
    theme_minimal() +
    theme(
      panel.background = element_rect(fill = "lightgray", color = NA),
      plot.background = element_rect(fill = "lightgray", color = NA),
      legend.text = element_text(size = 14, face = "bold"),
      axis.text.y = element_text(size = 14, face = "bold"), # Y-axis tick labels (Boat/Hatchery names)
      axis.text.x = element_text(size = 14, face = "bold"), # X-axis tick labels (Proportions)
      axis.title.x = element_text(size = 14, face = "bold", margin = margin(t = 10))
    )
  
  ggplotly(p, height = final_height, tooltip = "text") %>%
    style(hoverinfo = "text") %>%
    layout(
      title = list(
        text = paste0("<b>", group_title, "</b>"),
        font = list(size = 16),
        x = 0.5,
        xanchor = "center",
        yref="container",
        yanchor="top",
        y = 0.98
      ),
      hoverlabel = list(
        bgcolor = "white",
        font = list(color = "black", size = 16),
        bordercolor = "gray"
      ),
      legend = list(
        orientation = "h",
        xanchor = "center",
        x = 0.5,        # Center horizontally
        y = 0.95,       # Position right below the title (above the plot area)
        yref="container",
        yanchor="top",
        font = list(size = 12)
      ),
      margin = list(l = 220, t = 100, r = 20, b = 100)
    ) %>%
    # HIDES THE INTERACTIVE TOOLBAR (MODEBAR)
    config(displayModeBar = FALSE)
}
plot_thiamine_pie <- function(data, div_idx = 1) {
  
  # Aggregate total sample counts across all boats for the target group
  pie_data <- data %>%
    filter(group_id == div_idx) %>%
    group_by(new_status) %>%
    summarise(total_count = sum(count), .groups = "drop") %>%
    filter(total_count > 0) %>%
    mutate(
      prop = total_count / sum(total_count),
      new_status = factor(new_status, levels = status_order)
    ) %>%
    arrange(new_status)
  
  if (nrow(pie_data) == 0) return(NULL)
  
  # Generate native Plotly pie chart (preserves factor ordering and hex colors)
  plot_ly(
    data = pie_data,
    labels = ~new_status,
    values = ~total_count,
    type = "pie",
    sort = FALSE,
    textinfo = "percent",
    hoverinfo = "text",
    text = ~paste0(
      "<b>", new_status, "</b><br>",
      "Count: ", total_count, "<br>",
      "Proportion: ", percent(prop, accuracy = 0.01)
    ),
    marker = list(
      colors = unname(status_colors[as.character(pie_data$new_status)]),
      line = list(color = "#FFFFFF", width = 1)
    )
  ) %>%
    layout(
      title = list(
        text = paste0("<b>Ocean Fishery Thiamine Status</b>"),
        font = list(size = 16),
          x = 0.5,
          xanchor = "center",
          yref="container",
          yanchor="top",
          y = 0.98
      ),
      hoverlabel = list(
        bgcolor = "white",
        font = list(color = "black", size = 16),
        bordercolor = "gray"
      ),
      paper_bgcolor = "lightgray",
      plot_bgcolor = "lightgray",
      legend = list(
        orientation = "h",
        xanchor = "center",
        x = 0.5,        # Center horizontally
        y = 0.95,       # Position right below the title (above the plot area)
        yref="container",
        yanchor="top",
        font = list(size = 12, color = "black")
      ),
      margin = list(l = 40, r = 40, t = 80, b = 60)
    ) %>%
    config(displayModeBar = FALSE)
}