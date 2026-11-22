# =====================================================================
# Aspirin–SA PBPK: WP7/WP8 report reproduction script (human + rat)
#   1. Runs all human and rat scenarios used in the WP7/WP8 report
#   2. Draws the report figures from Plots.xlsx (esqlabsR, report format)
#   3. Calculates the report PK tables (Sim_Value, Obs_Value, Fold) and the
#      observed-vs-simulated point summary (Obs_Sim_Points)
#   4. Saves everything to Report_outputs/ (Figures/, Tables/) together with
#      the software versions (sessionInfo.txt)
#
# Same folder level as "Aspirin_manuscript_reproduce.R":
#   <project root>/
#     Aspirin_manuscript_reproduce.R  -> Manuscript_outputs/
#     Aspirin_report_reproduce.R      -> Report_outputs/
#     Fuction_Setting_Codes.R
#
# Calculation as in the report:
#   - Fold = max(Sim/Obs, Obs/Sim) (always >= 1)
#   - single-dose scenarios: full-profile C_max, t_max, AUC_tEnd
#   - repeated-dosing scenarios: fixed time window (see pk_windows below)
#   - observed PK: Cmax, Tmax and trapezoidal AUC from the digitized data,
#     in µmol/L and min (Tmax in h), computed with fixed units
#   - simulated PK: calculatePKAnalyses() (PK-Sim units: µmol/L, h, µmol·min/L)
#
# Requires: Fuction_Setting_Codes.R (compute_summary_log, extract_sim_pk,
#           compute_pk_fold)
# 
# Disclaimer
# This work product was developed and is made publicly available by ESQlabs GmbH under Grant INV-089180, 
# with funding from the Gates Foundation.

# ESQlabs is solely responsible for the scientific content of this work, including its methodology, 
# assumptions, implementation, documentation, analyses, and conclusions. The work represents the 
# state of development achieved under the grant and is provided as-is for research and informational purposes.

# The models and associated outputs have not been independently verified, validated, or qualified by the Gates 
# Foundation for clinical, regulatory, product-development, or patient-care decision-making. Publication of 
# this work, and acknowledgment of Foundation funding, should not be interpreted as endorsement by the Gates 
# Foundation of the scientific methods, model performance, conclusions, or fitness of the work for any particular purpose.

# Users are responsible for independently evaluating the work, its assumptions, limitations, applicability, and 
# fitness for their intended use. ESQlabs should be contacted regarding any questions, corrections, maintenance, 
# or further development of the work.
# =====================================================================


# =====================================================================
# 0. USER SETTINGS – edit this block only
# =====================================================================
human_project_config <- "ProjectConfiguration.xlsx"
rat_project_config   <- "ProjectConfiguration.xlsx"
function_file        <- "Fuction_Setting_Codes.R"
out_dir              <- "Report_outputs"

run_human <- TRUE
run_rat   <- TRUE

# Use the same sheet names as in Aspirin_manuscript_reproduce.R
human_data_sheets <- c("Boelig2024", "Shanmugalingam2019", "Bochner1988",
                       "Bochner1988_Weekdosing", "Rymark1994", "Rymark1994_nonpreg")
rat_data_sheets   <- c("Rat_WILSON 1977", "Rat_WILSON 1977_Pregnant", "Rat_Wientjes1988")

# Scenarios (= plot grid names in Plots.xlsx and DataCombined names) ------
human_scenarios <- c(
  "ASA_IV_50mg", "ASA_Oral_50mg_diss", "ASA_Oral_50mg_release", "ASA_Oral_100mg_ECform",
  "ASA_Oral_100mg_diss", "ASA_Oral_150mg_diss", "ASA_Oral_50mg_release_1wk", "ASA_Oral_75mg_diss",
  "Pregnant individual_36-38wk_Oral_75mg_diss", "Pregnant individual_36-38wk_Oral_75mg_diss_orig",
  "Pregnant individual_27-29wk_Oral_75mg_diss", "Pregnant individual_12wk_Oral_81mg_diss",
  "Pregnant individual_12wk_Oral_81mg_diss_orig", "Pregnant individual_12wk_Oral_repeat81mg_diss",
  "Pregnant individual_25wk_Oral_100mg_diss", "Pregnant individual_25wk_Oral_100mg_EC",
  "Pregnant individual_25wk_Oral_150mg_diss",
  "POP_Pregnant individual_36-38wk_Oral_75mg_diss", "POP_Pregnant individual_27-29wk_Oral_75mg_diss",
  "POP_Pregnant individual_12wk_Oral_81mg_diss", "POP_Pregnant individual_12wk_Oral_81mg_diss_orig",
  "POP_Pregnant individual_12wk_Oral_repeat81mg_diss", "POP_Pregnant individual_25wk_Oral_100mg_diss",
  "POP_Pregnant individual_25wk_Oral_100mg_EC", "POP_Pregnant individual_25wk_Oral_150mg_diss"
)
rat_scenarios <- c(
  "Rat_IV_200mgperkg", "Rat_IV_200mgperkg_2", "Rat_Oral_200mgperkg",
  "Rat_Oral_100mgperkg", "Rat_Oral_150mgperkg",
  "PregnantRat_Oral_100mgperkg", "PregnantRat_Oral_150mgperkg"
)

# Fixed time windows (h) for repeated dosing; all other scenarios use the full profile
pk_windows <- list(
  "ASA_Oral_50mg_release_1wk"                         = c(144.5, 151),
  "Pregnant individual_12wk_Oral_repeat81mg_diss"     = c(2832, 2838),
  "POP_Pregnant individual_12wk_Oral_repeat81mg_diss" = c(2832, 2838),
  "Rat_Oral_100mgperkg"                               = c(85, 101),
  "Rat_Oral_150mgperkg"                               = c(85, 101),
  "PregnantRat_Oral_100mgperkg"                       = c(85, 101),
  "PregnantRat_Oral_150mgperkg"                       = c(85, 101)
)

# AUC interval for single-dose scenarios --------------------------------
# FALSE: simulated AUC_tEnd = time zero to end of simulation (report v5/v6 method)
# TRUE : simulated AUC over the observed sampling interval (first to last observation,
#        never beyond the end of the simulation), as in the manuscript; Cmax and Tmax stay
#        full-profile
auc_to_last_obs <- TRUE

# Figure settings (report format) -------------------------------------
fig_colors <- c("PeripheralVenousBlood|Aspirin" = "red",
                "PeripheralVenousBlood|Salicylic acid" = "blue")
fig_width  <- 7.5   # inch
fig_height <- 5
also_jpeg  <- TRUE  # convert each PDF to JPEG (keeps the PDF layout and font size)
jpeg_dpi   <- 300


# =====================================================================
# 1. Packages and functions
# =====================================================================
library(esqlabsR)
library(ospsuite)
library(ggplot2)
library(dplyr)
library(tidyr)
library(DescTools)
library(tlf)
library(writexl)
if (also_jpeg && !requireNamespace("pdftools", quietly = TRUE)) install.packages("pdftools")

source(function_file)
for (d in c("Figures/Human", "Figures/Rat", "Tables")) {
  dir.create(file.path(out_dir, d), showWarnings = FALSE, recursive = TRUE)
}

# User-defined PK parameters: one set, window changed per scenario -----
removeAllUserDefinedPKParameters()
AUC_userdifined  <- addUserDefinedPKParameter("AUC_userdifined",  StandardPKParameter$AUC_tEnd)
Cmax_userdifined <- addUserDefinedPKParameter("Cmax_userdifined", StandardPKParameter$C_max)
Tmax_userdifined <- addUserDefinedPKParameter("Tmax_userdifined", StandardPKParameter$t_max)

set_pk_window <- function(window_h) {
  for (p in list(AUC_userdifined, Cmax_userdifined, Tmax_userdifined)) {
    p$startTime <- window_h[1] * 60
    p$endTime   <- window_h[2] * 60
  }
}

# Run all scenarios of one project ------------------------------------
run_project <- function(config_path, scenario_names, data_sheets) {
  pc   <- createProjectConfiguration(path = config_path)
  scen <- createScenarios(readScenarioConfigurationFromExcel(
    scenarioNames = scenario_names, projectConfiguration = pc))
  sim  <- runScenarios(scenarios = scen)
  obs  <- loadObservedData(projectConfiguration = pc, sheets = data_sheets)
  dc   <- createDataCombinedFromExcel(
    projectConfiguration = pc, dataCombinedNames = scenario_names,
    simulatedScenarios = sim, observedData = obs, stopIfNotFound = TRUE)
  list(pc = pc, sim = sim, obs = obs, dc = dc)
}

# Observed PK with fixed units (µmol/L, min; Tmax in h) -----------------
# Same calculation as compute_pk_obs(), but units are fixed instead of
# depending on calculateResiduals(); observations after the end of the
# simulation are excluded, as in calculateResiduals().
compute_obs_pk_fixed <- function(dc, scenario, compounds = c("Aspirin", "Salicylic acid")) {
  df <- ospsuite::convertUnits(dc, xUnit = "min", yUnit = "µmol/l")
  bind_rows(lapply(compounds, function(cp) {
    d <- df %>% filter(grepl(cp, group, fixed = TRUE))
    if (!any(d$dataType == "observed")) return(NULL)
    sim_end <- max(d$xValues[d$dataType == "simulated"], na.rm = TRUE)
    o <- d %>% filter(dataType == "observed", !is.na(yValues), xValues <= sim_end) %>% arrange(xValues)
    if (nrow(o) == 0) return(NULL)
    tibble(Scenario = scenario, OrganPath = "PeripheralVenousBlood", Compound = cp,
           C_max = max(o$yValues),
           t_max = o$xValues[which.max(o$yValues)] / 60,
           AUC_tEnd = DescTools::AUC(x = o$xValues, y = o$yValues, method = "trapezoid"))
  }))
}

# PK table for one scenario (report format) ------------------------------
pk_table_scenario <- function(run, scenario) {
  window <- pk_windows[[scenario]]
  if (is.null(window)) {
    params <- c("C_max", "t_max", "AUC_tEnd")
  } else {
    set_pk_window(window)
    params <- c("Cmax_userdifined", "Tmax_userdifined", "AUC_userdifined")
  }
  obs_pk <- compute_obs_pk_fixed(run$dc[[scenario]], scenario)
  if (nrow(obs_pk) == 0) return(NULL)
  get_sim <- function(prm, cps = c("Aspirin", "Salicylic acid"))
    extract_sim_pk(run$sim[[scenario]]$results, scenario_name = scenario,
                   selected_params = prm, organs = "PeripheralVenousBlood", compounds = cps)
  res <- compute_pk_fold(obs_pk, get_sim(params)) %>% filter(Fold_Status == "Fold calculated")
  
  # single dose: replace AUC by AUC from time zero to the last observation (per compound)
  if (is.null(window) && auc_to_last_obs) {
    od <- ospsuite::convertUnits(run$dc[[scenario]], xUnit = "h")
    for (cp in unique(res$Compound)) {
      d <- od %>% filter(grepl(cp, group, fixed = TRUE), !is.na(yValues))
      sim_end <- max(d$xValues[d$dataType == "simulated"])
      t_obs   <- d$xValues[d$dataType == "observed" & d$xValues <= sim_end]
      t_first <- min(t_obs); t_last <- max(t_obs)
      set_pk_window(c(t_first, t_last))   # observed sampling interval
      fa <- compute_pk_fold(obs_pk %>% filter(Compound == cp), get_sim("AUC_userdifined", cp)) %>%
        filter(Fold_Status == "Fold calculated")
      if (nrow(fa) == 1) {
        i <- which(res$Compound == cp & res$Obs_PK == "AUC_tEnd")
        res$Sim_Value[i] <- fa$Sim_Value; res$Fold[i] <- fa$Fold
        res$Sim_PK[i] <- sprintf("AUC %.2f–%.2f h", t_first, t_last)
      }
    }
  }
  
  res %>%
    mutate(
      `PK para.` = Obs_PK,
      # Tmax after IV bolus: first observation at ~time zero -> fold not meaningful ("-" in report)
      Fold = ifelse(Obs_PK == "t_max" & Obs_Value < 1 / 60, NA_real_, Fold),
      PK_method = if (!is.null(window)) sprintf("Window %g–%g h", window[1], window[2])
      else ifelse(grepl("^AUC [0-9]", Sim_PK), paste("Full profile;", Sim_PK), "Full profile"),
      Simulation = ifelse(grepl("^POP_", Scenario), "Population (median, n = 100)", "Individual")
    ) %>%
    select(Scenario, Compound, `PK para.`, Sim_Value, Obs_Value, Fold, PK_method, Simulation)
}

# Observed-vs-simulated point summary (as in the report Rmd) -------------
points_summary <- function(run, scenarios) {
  bind_rows(lapply(scenarios, function(s) {
    res <- calculateResiduals(run$dc[[s]], scaling = tlf::Scaling$log)
    compute_summary_log(res, name = s)
  }))
}

# Report figures from Plots.xlsx -----------------------------------------
save_report_plots <- function(run, scenarios, sub_dir) {
  plots <- createPlotsFromExcel(
    plotGridNames = scenarios, simulatedScenarios = run$sim,
    observedData = run$obs, projectConfiguration = run$pc, stopIfNotFound = TRUE)
  for (nm in names(plots)) {
    p <- plots[[nm]]
    # individual simulations: ASA red / SA blue (population plots keep their own aesthetics)
    if (!grepl("^POP_", nm)) p <- p & scale_color_manual(values = fig_colors)
    f <- file.path(out_dir, "Figures", sub_dir, nm)
    # 1. PDF first (cairo_pdf keeps "µ" correct)
    ggsave(paste0(f, ".pdf"), p, width = fig_width, height = fig_height, device = cairo_pdf)
    # 2. PDF -> JPEG, so the JPEG has exactly the PDF layout and font size
    if (also_jpeg) pdftools::pdf_convert(paste0(f, ".pdf"), format = "jpeg", dpi = jpeg_dpi,
                                         filenames = paste0(f, ".jpeg"), verbose = FALSE)
  }
  invisible(plots)
}


# =====================================================================
# 2. HUMAN
# =====================================================================
tables <- list()

if (run_human) {
  hum <- run_project(human_project_config, human_scenarios, human_data_sheets)
  save_report_plots(hum, human_scenarios, "Human")
  tables[["Human_PK"]]             <- bind_rows(lapply(human_scenarios, pk_table_scenario, run = hum))
  tables[["Human_Obs_Sim_Points"]] <- points_summary(hum, human_scenarios)
}


# =====================================================================
# 3. RAT
# =====================================================================
if (run_rat) {
  rat <- run_project(rat_project_config, rat_scenarios, rat_data_sheets)
  save_report_plots(rat, rat_scenarios, "Rat")
  tables[["Rat_PK"]]             <- bind_rows(lapply(rat_scenarios, pk_table_scenario, run = rat))
  tables[["Rat_Obs_Sim_Points"]] <- points_summary(rat, rat_scenarios)
}


# =====================================================================
# 4. Save tables and session information
# =====================================================================
tables <- lapply(tables, function(t) t %>% mutate(across(where(is.numeric), ~ round(.x, 2))))
write_xlsx(tables, file.path(out_dir, "Tables", "Report_performance_tables.xlsx"))

writeLines(c(paste("Run date:", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
             paste("auc_to_last_obs:", auc_to_last_obs),
             "PK windows (h):",
             paste0("  ", names(pk_windows), ": ", sapply(pk_windows, paste, collapse = "–")),
             "", capture.output(sessionInfo())),
           file.path(out_dir, "sessionInfo.txt"))

cat("\nReport figures, tables and session information written to:",
    normalizePath(out_dir), "\n")