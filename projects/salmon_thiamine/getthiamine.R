#!/usr/bin/env Rscript

## Read data from ERDDAP and generate json file for input to bar charts

suppressPackageStartupMessages({
  library(jsonlite)
  library(httr)
  library(stringr)
})

dset <- "Salmon_thiamine"
outfile <- "/var/www/html/ERDtest/app/data/thiamine_menu.json"
# outfile <- "/var/www/data/thiamine_menu.json"

types <- list(
  list(
    name = "ocean",
    value = "ocean%20fishery",
    vars = list(
      list(name = "sample_id", title = "Sample ID"),
      list(name = "collection_date", title = "Collection Date"),
      list(name = "boat_hatchery", title = "Boat"),
      list(name = "port_landed", title = "Port Landed")
    )
  ),
  list(
    name = "hatchery",
    value = "hatchery",
    vars = list(
      list(name = "sample_id", title = "Sample ID"),
      list(name = "collection_date", title = "Collection Date"),
      list(name = "boat_hatchery", title = "Hatchery"),
      list(name = "port_landed", title = "Hatchery Location")
    )
  )
)

species <- list(
  list(c("all"), c("all")),
  list(c("(chinook|coho)", "(steelhead)"), c("(chinook|coho)", "(steelhead)"))
)

stocks <- c("ccv", "coastal")
server <- "https://oceanview.pfeg.noaa.gov/erddap/tabledap/"
# server <- "http://127.0.0.1:8080/erddap/tabledap/"

# Equivalent of PHP pretty_stock()
pretty_stock <- function(count, stat, yr, st, hatch) {
  st1 <- if (is.na(st) || st == "NA") "" else paste0(str_to_title(st), " ")
  if (is.na(stat) || stat == "" || stat == "NA") stat <- "Unknown"
  pretty <- paste0(str_to_title(hatch), " ", st1, yr)
  list(count = count, stat = stat, pretty = pretty)
}

# Helper to fetch and parse JSON safely (suppressing HTTP errors like @file_get_contents)
fetch_json_safe <- function(url) {
  tryCatch({
    res <- GET(url)
    if (status_code(res) >= 400) return(NULL)
    fromJSON(content(res, as = "text", encoding = "UTF-8"), simplifyVector = FALSE)
  }, error = function(e) NULL)
}

typearr <- list()

for (k in seq_along(types)) {
  typeobj <- list(name = types[[k]]$name)
  stocksarr <- list()
  vars <- types[[k]]$vars
  
  for (kk in seq_along(stocks)) {
    stockobj <- list(name = stocks[kk])
    sp <- species[[k]][[kk]]
    speciesarr <- list()
    
    for (jj in seq_along(sp)) {
      speciesobj <- list()
      thissp <- sp[jj]
      spquery <- ""
      if (thissp != "all") spquery <- paste0("&species=~%22", thissp, "%22")
      cat(types[[k]]$name, stocks[kk], thissp, spquery, "\n")
      
      itemslist <- list()
      stock_found <- TRUE
      
      for (i in seq_along(vars)) {
        varlist <- list(name = vars[[i]]$name, title = vars[[i]]$title, vals = list())
        url <- paste0(
          server, dset, ".json?", vars[[i]]$name,
          "&collection_type=%22", types[[k]]$value, "%22",
          "&stock=%22", stocks[kk], "%22",
          "&treatment_status=~%22(NA|saline)%22&avg_total_egg_thi%3E0",
          spquery, "&distinct()"
        )
        
        json_data <- fetch_json_safe(url)
        if (is.null(json_data)) {
          stock_found <- FALSE
          break
        }
        
        vals <- json_data$table$rows
        var_vals <- character(0)
        if (length(vals) > 0) {
          for (j in seq_along(vals)) {
            val <- vals[[j]][[1]]
            if (!is.null(val) && val != "" && val != "TBD") {
              var_vals <- c(var_vals, as.character(val))
            }
          }
        }
        varlist$vals <- as.list(var_vals)
        itemslist[[length(itemslist) + 1]] <- varlist
      }
      
      if (!stock_found) next
      
      # Status summary query
      url <- paste0(
        server, dset, ".json?sample_id,new_status",
        "&collection_type=%22", types[[k]]$value, "%22",
        "&stock=%22", stocks[kk], "%22",
        "&treatment_status=~%22(NA|saline)%22&avg_total_egg_thi%3E0",
        spquery, "&new_status!=%22%22&distinct()&orderByCount(%22new_status%22)"
      )
      
      c_json <- fetch_json_safe(url)
      if (is.null(c_json)) next
      
      counts <- c_json$table$rows
      order_levels <- c("severely impacted", "impacted", "likely impacted", "unlikely impacted")
      
      countarr <- list(list("Thimine Status", "Number of Fish"))
      for (lvl in order_levels) {
        matched_val <- 0
        for (row in counts) {
          if (!is.null(row[[2]]) && row[[2]] == lvl) {
            matched_val <- row[[1]]
            break
          }
        }
        countarr[[length(countarr) + 1]] <- list(lvl, matched_val)
      }
      
      speciesobj$name <- thissp
      speciesobj$menu <- itemslist
      speciesobj$count <- countarr
      
      # Grouped query by boat/hatchery, year, run, etc.
      url <- paste0(
        server, dset, ".json?sample_id,new_status,boat_hatchery,year,run,sequence",
        "&collection_type=%22", types[[k]]$value, "%22",
        "&stock=%22", stocks[kk], "%22",
        "&treatment_status=~%22(NA|saline)%22&avg_total_egg_thi%3E0",
        spquery, "&distinct()&orderByCount(%22year,sequence,run,boat_hatchery,new_status%22)&new_status!=%22%22"
      )
      cat(url, "\n")
      
      c_json <- fetch_json_safe(url)
      counts <- if (!is.null(c_json)) c_json$table$rows else list()
      
      stock <- list()
      if (length(counts) > 0) {
        for (row in counts) {
          stock[[length(stock) + 1]] <- pretty_stock(
            count = row[[1]],
            stat = row[[2]],
            yr = row[[4]],
            st = row[[5]],
            hatch = row[[3]]
          )
        }
      }
      
      pretty_names <- sapply(stock, function(x) x$pretty)
      boats <- rev(unique(pretty_names))
      
      countarr2 <- list(list("Boat", "severely impacted", "impacted", "likely impacted", "unlikely impacted"))
      
      for (b in boats) {
        boat_label <- if (is.na(b) || b == "") "Unknown" else b
        row_vals <- list(boat_label)
        
        for (j in 1:4) {
          cell_val <- 0
          target_stat <- countarr2[[1]][[j + 1]]
          for (s in stock) {
            if (s$pretty == b && s$stat == target_stat) {
              cell_val <- s$count
              break
            }
          }
          row_vals[[j + 1]] <- cell_val
        }
        countarr2[[length(countarr2) + 1]] <- row_vals
      }
      
      speciesobj$count_by_boat_or_hatchery <- countarr2
      speciesarr[[length(speciesarr) + 1]] <- speciesobj
    }
    
    stockobj$species <- speciesarr
    if (length(speciesarr) > 0) stocksarr[[length(stocksarr) + 1]] <- stockobj
  }
  
  typeobj$stocks <- stocksarr
  typearr[[length(typearr) + 1]] <- typeobj
}

out <- list(
  name = "thiamine_meas",
  types = typearr
)

dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(out, auto_unbox = TRUE, pretty = TRUE), con = outfile)

