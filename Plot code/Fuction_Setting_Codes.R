# set function for compute performance table ---------------
compute_summary_log <- function(df, name = NA, eps = 1e-15) {
  
  summary_table <- df %>%
    mutate(
      # Avold log10(0)
      yObs_adj = pmax(yValuesObserved, eps),
      ySim_adj = pmax(yValuesSimulated, eps),
      
      log_yObs = log10(yObs_adj),
      log_ySim = log10(ySim_adj),
      
      fold = pmax(
        yValuesSimulated / yValuesObserved,
        yValuesObserved / yValuesSimulated
      )
    ) %>%
    group_by(group) %>%
    summarise(
      MAE  = mean(abs(log_ySim - log_yObs), na.rm = TRUE),
      MSE  = mean((log_ySim - log_yObs)^2, na.rm = TRUE),
      RMSE = sqrt(mean((log_ySim - log_yObs)^2, na.rm = TRUE)),
      ME   = mean(log_ySim - log_yObs, na.rm = TRUE),
      r    = cor(log_ySim, log_yObs, use = "complete.obs"),
      
      n_total = n(),
      n_zero  = sum(
        yValuesObserved == 0 | yValuesSimulated == 0,
        na.rm = TRUE
      ),
      
      n_2fold   = sum(fold <= 2, na.rm = TRUE),
      pct_2fold = n_2fold / n_total * 100,
      
      n_3fold   = sum(fold <= 3, na.rm = TRUE),
      pct_3fold = n_3fold / n_total * 100,
      
      n_10fold   = sum(fold <= 10, na.rm = TRUE),
      pct_10fold = n_10fold / n_total * 100,
      
      .groups = "drop"
    ) %>%
    mutate(
      Scenario = name
    ) %>%
    select(Scenario, group, everything()) %>%
    mutate(across(where(is.numeric), ~ round(.x, 3)))
  
  return(summary_table)
}

# set function for compute PK performance table ---------------
# find Obs PK
compute_pk_obs <- function(
    datacombined_list, 
    scenario_name = NA, 
    organs = NULL, 
    compounds = NULL) {
  
  res_df <- calculateResiduals(datacombined_list, scaling = tlf::Scaling$log) %>%
    filter(!is.na(yValuesObserved))
  
  if(nrow(res_df) == 0) return(tibble())
  
  # Splits group：last layer is Compound, other is OrganPath
  parts_list <- strsplit(res_df$group, "\\|")
  res_df$Compound <- sapply(parts_list, function(x) tail(x, 1))
  res_df$OrganPath <- sapply(parts_list, function(x) paste(head(x, -1), collapse = "|"))
  
  # selected organ
  if(!is.null(organs)) {
    res_df <- res_df %>% filter(sapply(strsplit(OrganPath, "\\|"), 
                                       function(x) any(x %in% organs)))
  }
  
  # selected chemicals
  if(!is.null(compounds)) res_df <- res_df %>% filter(Compound %in% compounds)
  
  # if no data, return tibble
  if(nrow(res_df) == 0) return(tibble())
  
  # calculate obs PK
  pk_table <- res_df %>%
    group_by(Scenario = scenario_name, OrganPath, Compound) %>%
    reframe(
      C_max = if(all(is.na(yValuesObserved))) NA_real_ else max(yValuesObserved, na.rm = TRUE),
      t_max = if(all(is.na(yValuesObserved))) NA_real_ else xValues[which.max(yValuesObserved)]/60,
      AUC_tEnd = if(all(is.na(yValuesObserved))) NA_real_ else DescTools::AUC(
        x = xValues,
        y = yValuesObserved,
        method = "trapezoid"
      )
    )
  
  return(pk_table)
}


# find Sim PK
extract_sim_pk <- function(
    sim_results,
    scenario_name = NA,
    selected_params = NULL,
    organs = NULL,
    compounds = NULL
) {
  
  # convert to PK dataframe
  df <- pkAnalysesToDataFrame(
    calculatePKAnalyses(sim_results)
  )
  
  # select PK parameter
  if (!is.null(selected_params)) {
    df <- df %>% filter(Parameter %in% selected_params)
  }
  
  # split QuantityPath
  parts <- strsplit(df$QuantityPath, "\\|")
  
  # OrganPath = layers at begining part, last layer is QuantityName
  df$QuantityName <- sapply(parts, function(x) tail(x, 1))
  df$Compound <- sapply(parts, function(x) x[length(x)-1])
  df$OrganPath <- sapply(parts, function(x) {
    if(length(x) > 2) paste(x[2:(length(x)-2)], collapse = "|") else NA
  })
  
  # select organs
  if(!is.null(organs)) {
    df <- df %>% filter(sapply(strsplit(OrganPath, "\\|"), function(x) any(x %in% organs)))
  }
  
  # select compound
  if(!is.null(compounds)) df <- df %>% filter(Compound %in% compounds)
  
  # identify population and calculate median
  if("IndividualId" %in% names(df) && length(unique(df$IndividualId)) > 1) {
    df <- df %>%
      group_by(OrganPath, Compound, Parameter) %>%
      summarise(Value = median(Value, na.rm = TRUE), .groups = "drop")
  }
  
  # compile output
  df %>%
    mutate(Scenario = scenario_name) %>%
    select(Scenario, OrganPath, Compound, Parameter, Value) %>%
    pivot_wider(
      names_from = Parameter,
      values_from = Value,
      names_prefix = "Sim_"
    )
}


# calculate PK fold difference
compute_pk_fold <- function(
    obs_pk,
    sim_pk,
    pk_mapping = NULL,
    eps = 1e-15
) {
  
  if (is.null(pk_mapping)) {
    pk_mapping <- tibble::tribble(
      ~Obs_PK,        ~Sim_PK,
      "C_max",        "C_max",
      "C_max",        "Cmax_userdifined",
      "t_max",        "t_max",
      "t_max",        "Tmax_userdifined",
      "AUC_tEnd",     "AUC_tEnd",
      "AUC_tEnd",     "AUC_inf",
      "AUC_tEnd",     "AUC_userdifined"
    )
  }
  
  # Sim → long）
  sim_long <- sim_pk %>%
    tidyr::pivot_longer(
      cols = starts_with("Sim_"),
      names_to = "Sim_PK",
      values_to = "Sim_Value"
    ) %>%
    dplyr::mutate(Sim_PK = sub("^Sim_", "", Sim_PK))
  
  # Obs → long
  obs_long <- obs_pk %>%
    tidyr::pivot_longer(
      cols = -c(Scenario, OrganPath, Compound),
      names_to = "Obs_PK",
      values_to = "Obs_Value"
    )
  
  # Sim → find possible Obs
  df <- sim_long %>%
    dplyr::left_join(pk_mapping, by = "Sim_PK") %>%
    dplyr::left_join(
      obs_long,
      by = c("Scenario", "OrganPath", "Compound", "Obs_PK")
    )
  
  # calculate fold
  df %>%
    dplyr::mutate(
      Fold = dplyr::if_else(
        !is.na(Obs_Value),
        pmax(
          pmax(Sim_Value, eps) / pmax(Obs_Value, eps),
          pmax(Obs_Value, eps) / pmax(Sim_Value, eps)
        ),
        NA_real_
      ),
      Fold_Status = dplyr::case_when(
        is.na(Obs_PK) ~ "Not mapped",
        is.na(Obs_Value) ~ "Mapped but no obs PK",
        TRUE ~ "Fold calculated"
      )
    ) %>%
    dplyr::select(
      Scenario, OrganPath, Compound,
      Sim_PK, Sim_Value,
      Obs_PK, Obs_Value,
      Fold, Fold_Status
    )
}
