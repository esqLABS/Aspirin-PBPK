# =====================================================================
# Aspirin–SA PBPK manuscript: reproduction script
#   1. Runs all human and rat scenarios used in the manuscript
#   2. Recalculates Table S1 (rat), Table S2 (human, non-pregnant),
#      Table 4 (pregnancy) and the ratios quoted in the text
#   3. Draws Fig. 2, Fig. 3, Fig. S1, Fig. S2, Fig. S3 (Fig. 4 style)
#   4. Saves the tables (with simulated and observed values) and the
#      software versions (sessionInfo.txt)
#
# Rules used (as in the manuscript):
#   - parameter estimation / calibration: single individual
#   - non-pregnant evaluation: single individual
#   - pregnant single-dose evaluation: virtual population (n = 100), median
#   - repeated dosing: single individual, user-defined time window
#   - ratio = predicted / observed, rounded half-up to 2 decimals
#
# Requires: Fuction_Setting_Codes.R (extract_sim_pk, compute_pk_fold)
# =====================================================================


# =====================================================================
# 0. USER SETTINGS – edit this block only
# =====================================================================
human_project_config <- "ProjectConfiguration.xlsx"
rat_project_config   <- "ProjectConfiguration.xlsx"
function_file        <- "Fuction_Setting_Codes.R"
out_dir              <- "Manuscript_outputs"

run_human <- TRUE
run_rat   <- TRUE

human_data_sheets <- c("Boelig2024", "Shanmugalingam2019", "Bochner1988",
                       "Bochner1988_Weekdosing", "Rymark1994", "Rymark1994_nonpreg")
rat_data_sheets   <- c("Rat_WILSON 1977", "Rat_WILSON 1977_Pregnant", "Rat_Wientjes1988")

# Figure style (Fig. 4 layout) ----------------------------------------
fig_style <- list(
  col_ASA     = "#C0392B",   # aspirin colour
  col_SA      = "#2B5BA8",   # salicylic acid colour
  band_alpha  = 0.18,        # transparency of 5th–95th percentile band
  line_width  = 0.9,
  point_size  = 1.8,
  point_shape = 16,          # 16 = filled circle
  base_size   = 10,          # font size
  panel_w     = 5,           # inch per panel
  panel_h     = 3.8,
  ncol        = 2,
  dpi         = 300,
  y_label     = "Plasma concentration (µmol/L)",
  y_unit      = "µmol/l",
  x_unit      = "h",
  title_gap   = 10,          # space (pt) between panel title and frame
  panel_gap   = 12,          # space (pt) around each panel
  fig3d_days_before = 2,     # Fig. 3d: days shown before the 2832–2838 h window
  legend_position   = "inside", # "inside" = top-right inside the frame; "top" = above the frame
  legend_buffer     = 1         # extra decades added to the top of the y axis to make room for the legend
)

# AUC interval --------------------------------------------------------
# FALSE: simulated AUC_tEnd = time zero to end of simulation (method used for v1.2 tables)
# TRUE : simulated AUC/Cmax/Tmax from time zero to the last observation of each dataset,
#        so that simulated and observed AUC cover the same interval
auc_to_last_obs <- FALSE


# =====================================================================
# 1. Packages and functions
# =====================================================================
library(esqlabsR)
library(ospsuite)
library(dplyr)
library(tidyr)
library(DescTools)
library(tlf)
library(ggplot2)
library(writexl)
if (!requireNamespace("patchwork", quietly = TRUE)) install.packages("patchwork")
library(patchwork)

source(function_file)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(out_dir, "Figures"), showWarnings = FALSE)

`%||%` <- function(a, b) if (is.null(a)) b else a
round_half_up <- function(x, d = 2) floor(x * 10^d + 0.5 + 1e-9) / 10^d
fmt2 <- function(x) ifelse(is.na(x), "–", formatC(round_half_up(x), format = "f", digits = 2))
geo_mean <- function(x) { x <- x[!is.na(x)]; if (length(x) == 0) NA_real_ else exp(mean(log(x))) }

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

# Observed PK with explicit units (µmol/L, min; Tmax in h) -----------------
# Same calculation as compute_pk_obs(), but units are fixed instead of
# depending on calculateResiduals(); observations after the end of the
# simulation are excluded, as in calculateResiduals().
compute_obs_pk_fixed <- function(dc, scenario, compound) {
  df <- ospsuite::convertUnits(dc, xUnit = "min", yUnit = "µmol/l") %>%
    filter(grepl(compound, group, fixed = TRUE))
  sim_end <- max(df$xValues[df$dataType == "simulated"], na.rm = TRUE)
  o <- df %>% filter(dataType == "observed", !is.na(yValues), xValues <= sim_end) %>%
    arrange(xValues)
  if (nrow(o) == 0) return(tibble())
  tibble(Scenario = scenario, OrganPath = "PeripheralVenousBlood", Compound = compound,
         C_max = max(o$yValues),
         t_max = o$xValues[which.max(o$yValues)] / 60,
         AUC_tEnd = DescTools::AUC(x = o$xValues, y = o$yValues, method = "trapezoid"))
}

# One table row: predicted/observed Cmax, Tmax, AUC --------------------
pk_row <- function(run, scenario, analyte, window = NULL) {
  compound <- c(ASA = "Aspirin", SA = "Salicylic acid")[[analyte]]
  obs_pk <- compute_obs_pk_fixed(run$dc[[scenario]], scenario, compound)
  if (is.null(window) && auc_to_last_obs) {
    od <- ospsuite::convertUnits(run$dc[[scenario]], xUnit = "h") %>%
      filter(dataType == "observed", grepl(compound, group, fixed = TRUE), !is.na(yValues))
    window <- c(0, max(od$xValues))
  }
  if (is.null(window)) {
    params <- c("C_max", "t_max", "AUC_tEnd")
  } else {
    set_pk_window(window)
    params <- c("Cmax_userdifined", "Tmax_userdifined", "AUC_userdifined")
  }
  sim_pk <- extract_sim_pk(run$sim[[scenario]]$results, scenario_name = scenario,
                           selected_params = params,
                           organs = "PeripheralVenousBlood", compounds = compound)
  f <- compute_pk_fold(obs_pk, sim_pk) %>% filter(Fold_Status == "Fold calculated")
  pick <- function(o) {
    r <- f[f$Obs_PK == o, ]
    if (nrow(r) == 0) c(NA_real_, NA_real_) else c(r$Sim_Value[1], r$Obs_Value[1])
  }
  cm <- pick("C_max"); tm <- pick("t_max"); au <- pick("AUC_tEnd")
  tibble(Sim_Cmax = cm[1], Obs_Cmax = cm[2], Sim_Tmax = tm[1], Obs_Tmax = tm[2],
         Sim_AUC = au[1], Obs_AUC = au[2],
         Cmax = cm[1] / cm[2], Tmax = tm[1] / tm[2], AUC = au[1] / au[2])
}

# Build a full table from its definition ------------------------------
build_table <- function(def, run) {
  raw <- def %>%
    rowwise() %>%
    mutate(res = list(pk_row(run, scenario, analyte,
                             if (is.na(win_start)) NULL else c(win_start, win_end)))) %>%
    ungroup() %>%
    tidyr::unnest(res) %>%
    mutate(Tmax = ifelse(hide_tmax, NA_real_, Tmax))
  
  rows <- list()
  for (sec in unique(raw$section)) {
    d <- raw %>% filter(section == sec)
    rows[[length(rows) + 1]] <- tibble(`Study and dosing` = sec, Analyte = "",
                                       Cmax = "", Tmax = "", AUC = "")
    rows[[length(rows) + 1]] <- tibble(`Study and dosing` = d$label, Analyte = d$analyte,
                                       Cmax = fmt2(d$Cmax), Tmax = fmt2(d$Tmax), AUC = fmt2(d$AUC))
    if (any(d$gm)) {
      rows[[length(rows) + 1]] <- tibble(
        `Study and dosing` = d$gm_label[1], Analyte = "",
        Cmax = fmt2(geo_mean(d$Cmax)), Tmax = fmt2(geo_mean(d$Tmax)), AUC = fmt2(geo_mean(d$AUC)))
    }
  }
  list(raw = raw, formatted = bind_rows(rows))
}

# =====================================================================
# 2. TABLE DEFINITIONS (scenario, analyte, time window)
#    win_start/win_end in h; NA = standard PK (time zero to end)
# =====================================================================
B88 <- "Bochner et al. 1988 [21]"; R94 <- "Rymark et al. 1994 [22]"
S19 <- "Shanmugalingam et al. 2019 [15]"; B24 <- "Boelig et al. 2024 [16]"
P <- "POP_Pregnant individual_"; I <- "Pregnant individual_"

tab_S2_def <- tibble::tribble(
  ~section,      ~label,                                   ~scenario,                    ~analyte, ~win_start, ~win_end, ~hide_tmax,
  "Calibration", paste0(B88, ", 50 mg IV"),                "ASA_IV_50mg",                "ASA",    NA, NA, FALSE,
  "Calibration", paste0(B88, ", 50 mg IV"),                "ASA_IV_50mg",                "SA",     NA, NA, FALSE,
  "Calibration", paste0(B88, ", 50 mg oral solution"),     "ASA_Oral_50mg_diss",         "ASA",    NA, NA, FALSE,
  "Calibration", paste0(B88, ", 50 mg oral solution"),     "ASA_Oral_50mg_diss",         "SA",     NA, NA, FALSE,
  "Calibration", paste0(B88, ", 50 mg oral MR"),           "ASA_Oral_50mg_release",      "ASA",    NA, NA, FALSE,
  "Calibration", paste0(B88, ", 50 mg oral MR"),           "ASA_Oral_50mg_release",      "SA",     NA, NA, FALSE,
  "Calibration", paste0(S19, ", 100 mg oral EC"),          "ASA_Oral_100mg_ECform",      "SA",     NA, NA, FALSE,
  "Evaluation",  paste0(B88, ", 50 mg MR daily, 1 week"),  "ASA_Oral_50mg_release_1wk",  "ASA",   144, 155, FALSE,
  "Evaluation",  paste0(B88, ", 50 mg MR daily, 1 week"),  "ASA_Oral_50mg_release_1wk",  "SA",    144, 155, FALSE,
  "Evaluation",  paste0(R94, ", 75 mg oral"),              "ASA_Oral_75mg_diss",         "ASA",    NA, NA, FALSE,
  "Evaluation",  paste0(R94, ", 75 mg oral"),              "ASA_Oral_75mg_diss",         "SA",     NA, NA, FALSE,
  "Evaluation",  paste0(S19, ", 100 mg oral"),             "ASA_Oral_100mg_diss",        "SA",     NA, NA, FALSE,
  "Evaluation",  paste0(S19, ", 150 mg oral"),             "ASA_Oral_150mg_diss",        "SA",     NA, NA, FALSE
) %>% mutate(gm = TRUE, gm_label = "Geometric mean")

tab_4_def <- tibble::tribble(
  ~section,      ~label,                                          ~scenario,                                   ~analyte, ~win_start, ~win_end, ~hide_tmax,
  "Calibration", paste0(R94, ", 75 mg oral, 36–38 wk"),           paste0(I, "36-38wk_Oral_75mg_diss"),         "ASA",  NA, NA, FALSE,
  "Calibration", paste0(R94, ", 75 mg oral, 36–38 wk"),           paste0(I, "36-38wk_Oral_75mg_diss"),         "SA",   NA, NA, FALSE,
  "Evaluation",  paste0(R94, ", 75 mg oral, 27–29 wk"),           paste0(P, "27-29wk_Oral_75mg_diss"),         "ASA",  NA, NA, FALSE,
  "Evaluation",  paste0(R94, ", 75 mg oral, 27–29 wk"),           paste0(P, "27-29wk_Oral_75mg_diss"),         "SA",   NA, NA, FALSE,
  "Evaluation",  paste0(B24, ", 81 mg oral, 10–16 wk"),           paste0(P, "12wk_Oral_81mg_diss"),            "SA",   NA, NA, FALSE,
  "Evaluation",  paste0(B24, ", 81 mg oral daily, 28–32 wk"),     paste0(I, "12wk_Oral_repeat81mg_diss"),      "SA", 2832, 2838, TRUE,
  "Evaluation",  paste0(S19, ", 100 mg oral, 22–28 wk"),          paste0(P, "25wk_Oral_100mg_diss"),           "SA",   NA, NA, FALSE,
  "Evaluation",  paste0(S19, ", 100 mg oral EC, 22–28 wk"),       paste0(P, "25wk_Oral_100mg_EC"),             "SA",   NA, NA, FALSE,
  "Evaluation",  paste0(S19, ", 150 mg oral, 22–28 wk"),          paste0(P, "25wk_Oral_150mg_diss"),           "SA",   NA, NA, FALSE
) %>% mutate(gm = section == "Evaluation", gm_label = "Geometric mean, evaluation")

# Ratios quoted only in the text (3.2 and Discussion)
text_def <- tibble::tribble(
  ~section,                       ~label,                                       ~scenario,                                 ~analyte, ~win_start, ~win_end, ~hide_tmax,
  "3.2: before re-estimation",    "36–38 wk, non-pregnant parameters",          paste0(I, "36-38wk_Oral_75mg_diss_orig"),  "ASA", NA, NA, FALSE,
  "3.2: before re-estimation",    "36–38 wk, non-pregnant parameters",          paste0(I, "36-38wk_Oral_75mg_diss_orig"),  "SA",  NA, NA, FALSE,
  "Discussion",                   "10–16 wk, non-pregnant parameters (POP)",    paste0(P, "12wk_Oral_81mg_diss_orig"),     "SA",  NA, NA, FALSE
) %>% mutate(gm = FALSE, gm_label = NA_character_)

rat_window <- c(85, 101)
tab_S1_def <- tibble::tribble(
  ~section,                       ~label,                                              ~scenario,                     ~analyte, ~hide_tmax,
  "Non-pregnant rat – Calibration", "IV 200 mg/kg, dataset 1 [34]",                    "Rat_IV_200mgperkg",           "ASA", TRUE,
  "Non-pregnant rat – Calibration", "IV 200 mg/kg, dataset 1 [34]",                    "Rat_IV_200mgperkg",           "SA",  FALSE,
  "Non-pregnant rat – Calibration", "IV 200 mg/kg, dataset 2 [34]",                    "Rat_IV_200mgperkg_2",         "ASA", TRUE,
  "Non-pregnant rat – Calibration", "IV 200 mg/kg, dataset 2 [34]",                    "Rat_IV_200mgperkg_2",         "SA",  FALSE,
  "Non-pregnant rat – Calibration", "Oral 200 mg/kg [34]",                             "Rat_Oral_200mgperkg",         "ASA", FALSE,
  "Non-pregnant rat – Calibration", "Oral 200 mg/kg [34]",                             "Rat_Oral_200mgperkg",         "SA",  FALSE,
  "Non-pregnant rat – Evaluation",  "Non-pregnant rat, oral 100 mg/kg twice daily [35]", "Rat_Oral_100mgperkg",       "SA",  FALSE,
  "Non-pregnant rat – Evaluation",  "Non-pregnant rat, oral 150 mg/kg twice daily [35]", "Rat_Oral_150mgperkg",       "SA",  FALSE,
  "Pregnant rat",                   "Pregnant rat, oral 100 mg/kg twice daily [35]",   "PregnantRat_Oral_100mgperkg", "SA",  FALSE,
  "Pregnant rat",                   "Pregnant rat, oral 150 mg/kg twice daily [35]",   "PregnantRat_Oral_150mgperkg", "SA",  FALSE
) %>%
  mutate(win_start = ifelse(grepl("twice daily", label), rat_window[1], NA_real_),
         win_end   = ifelse(grepl("twice daily", label), rat_window[2], NA_real_),
         gm = FALSE, gm_label = NA_character_)


# =====================================================================
# 3. FIGURE FUNCTIONS (Fig. 4 style)
# =====================================================================
col_analyte <- c(ASA = fig_style$col_ASA, SA = fig_style$col_SA)

theme_fig4 <- function(base_size = fig_style$base_size) {
  theme_bw(base_size = base_size) +
    theme(
      panel.border = element_rect(colour = "black", linewidth = 0.6),
      panel.grid.major = element_line(colour = "grey90", linewidth = 0.3),
      panel.grid.minor = element_blank(),
      plot.title = element_text(size = base_size + 1, hjust = 0,
                                margin = margin(b = fig_style$title_gap)),
      plot.title.position = "plot",
      plot.margin = margin(fig_style$panel_gap, fig_style$panel_gap + 6,
                           fig_style$panel_gap, fig_style$panel_gap),
      axis.text = element_text(colour = "black"),
      legend.position = if (fig_style$legend_position == "inside") c(0.98, 0.98) else "top",
      legend.justification = if (fig_style$legend_position == "inside") c(1, 1) else "right",
      legend.direction = if (fig_style$legend_position == "inside") "vertical" else "horizontal",
      legend.margin = margin(0, 0, 0, 0),
      legend.box.spacing = unit(2, "pt"),
      legend.background = element_rect(fill = NA, colour = NA),
      legend.key = element_rect(fill = NA, colour = NA),
      legend.title = element_blank(),
      legend.text = element_text(size = base_size - 1)
    )
}

log_labels <- function(x) sapply(x, function(v) {
  if (is.na(v)) return(NA)
  e <- log10(v)
  if (abs(e - round(e)) < 1e-8) parse(text = paste0("10^", round(e))) else format(v)
})

get_dc_data <- function(dc) {
  df <- tryCatch(
    ospsuite::convertUnits(dc, xUnit = fig_style$x_unit, yUnit = fig_style$y_unit),
    error = function(e) {
      warning("convertUnits() failed – plotting without unit conversion: ", conditionMessage(e))
      dc$toDataFrame()
    })
  df %>% mutate(analyte = ifelse(grepl("Salicylic", group), "SA", "ASA"))
}

plot_panel <- function(dc, title, xlim = NULL, ylim = NULL) {
  df  <- get_dc_data(dc)
  sim <- df %>% filter(dataType == "simulated") %>%
    group_by(analyte, xValues) %>%
    summarise(n_ind = n(), median = median(yValues, na.rm = TRUE),
              p05 = quantile(yValues, 0.05, na.rm = TRUE),
              p95 = quantile(yValues, 0.95, na.rm = TRUE), .groups = "drop")
  obs <- df %>% filter(dataType == "observed", !is.na(yValues))
  if (!"yErrorValues" %in% names(obs)) obs$yErrorValues <- NA_real_
  if (!"yErrorType"   %in% names(obs)) obs$yErrorType   <- NA_character_
  obs <- obs %>% mutate(
    ymin = ifelse(is.na(yErrorValues), NA,
                  ifelse(grepl("Geometric", yErrorType), yValues / yErrorValues, yValues - yErrorValues)),
    ymax = ifelse(is.na(yErrorValues), NA,
                  ifelse(grepl("Geometric", yErrorType), yValues * yErrorValues, yValues + yErrorValues)))
  is_pop <- any(sim$n_ind > 1)
  
  if (is.null(xlim)) xlim <- c(0, max(c(sim$xValues, obs$xValues), na.rm = TRUE))
  sim <- sim %>% filter(xValues >= xlim[1], xValues <= xlim[2])
  if (is.null(ylim)) {
    v  <- c(obs$yValues, obs$ymin); v <- v[!is.na(v) & v > 0]
    hi <- max(c(obs$yValues, obs$ymax, sim$p95, sim$median), na.rm = TRUE)
    buffer <- if (fig_style$legend_position == "inside") fig_style$legend_buffer else 0
    ylim <- c(10^floor(log10(min(v) / 3)), 10^(ceiling(log10(hi * 1.5)) + buffer))
  }
  analytes <- intersect(c("ASA", "SA"), unique(c(sim$analyte, obs$analyte)))
  
  p <- ggplot()
  if (is_pop) p <- p + geom_ribbon(data = sim,
                                   aes(x = xValues, ymin = pmax(p05, ylim[1]), ymax = p95, fill = analyte),
                                   alpha = fig_style$band_alpha, show.legend = FALSE)
  p + geom_line(data = sim, aes(x = xValues, y = median, colour = analyte),
                linewidth = fig_style$line_width) +
    geom_errorbar(data = obs %>% filter(!is.na(ymin)),
                  aes(x = xValues, ymin = pmax(ymin, ylim[1]), ymax = ymax, colour = analyte),
                  width = 0, linewidth = 0.4, show.legend = FALSE) +
    geom_point(data = obs, aes(x = xValues, y = yValues, colour = analyte),
               size = fig_style$point_size, shape = fig_style$point_shape) +
    scale_colour_manual(values = col_analyte, breaks = analytes, labels = analytes) +
    scale_fill_manual(values = col_analyte) +
    scale_y_log10(labels = log_labels) +
    scale_x_continuous(labels = function(x) format(x, trim = TRUE, drop0trailing = TRUE)) +
    coord_cartesian(xlim = xlim, ylim = ylim, expand = FALSE) +
    labs(title = title, x = "Time (h)", y = fig_style$y_label) +
    theme_fig4()
}

save_figure <- function(panels, name, ncol = fig_style$ncol, also_tiff = FALSE) {
  if (!requireNamespace("pdftools", quietly = TRUE)) install.packages("pdftools")
  nrow <- ceiling(length(panels) / ncol)
  fig  <- wrap_plots(panels, ncol = ncol)
  w <- fig_style$panel_w * ncol; h <- fig_style$panel_h * nrow
  # 1. Vector PDF (cairo_pdf keeps "µ" and "–" correct)
  pdf_file <- file.path(out_dir, "Figures", paste0(name, ".pdf"))
  ggsave(pdf_file, fig, width = w, height = h, device = cairo_pdf, bg = "white")
  # 2. PDF -> JPEG
  pdftools::pdf_convert(pdf_file, format = "jpeg", dpi = fig_style$dpi,
                        filenames = file.path(out_dir, "Figures", paste0(name, ".jpeg")),
                        verbose = FALSE)
  # 3. Optional lossless TIFF
  if (also_tiff) ggsave(file.path(out_dir, "Figures", paste0(name, ".tiff")), fig,
                        width = w, height = h, dpi = fig_style$dpi, bg = "white",
                        compression = "lzw")
  invisible(fig)
}


# =====================================================================
# 4. HUMAN: run, tables, figures
# =====================================================================
out_tables <- list(); out_raw <- list()

if (run_human) {
  human_scenarios <- unique(c(tab_S2_def$scenario, tab_4_def$scenario, text_def$scenario))
  hum <- run_project(human_project_config, human_scenarios, human_data_sheets)
  
  tS2 <- build_table(tab_S2_def, hum)
  t4  <- build_table(tab_4_def,  hum)
  tTx <- build_table(text_def,   hum)
  
  out_tables[["Table_S2_human_nonpregnant"]] <- tS2$formatted
  out_tables[["Table_4_pregnancy"]]          <- t4$formatted
  out_tables[["Text_values"]]                <- tTx$formatted
  out_raw   <- c(out_raw, list(tS2$raw, t4$raw, tTx$raw))
  
  d <- hum$dc
  save_figure(list(
    plot_panel(d[["ASA_IV_50mg"]],           "a  50 mg intravenous (Bochner et al. 1988)"),
    plot_panel(d[["ASA_Oral_50mg_diss"]],    "b  50 mg oral solution (Bochner et al. 1988)"),
    plot_panel(d[["ASA_Oral_50mg_release"]], "c  50 mg oral MR (Bochner et al. 1988)"),
    plot_panel(d[["ASA_Oral_100mg_ECform"]], "d  100 mg EC, non-pregnant (Shanmugalingam et al. 2019)")
  ), "Fig2")
  
  save_figure(list(
    plot_panel(d[[paste0(I, "36-38wk_Oral_75mg_diss")]],    "a  75 mg, 36–38 weeks, re-estimated (Rymark et al. 1994)"),
    plot_panel(d[[paste0(P, "27-29wk_Oral_75mg_diss")]],    "b  75 mg, 27–29 weeks (Rymark et al. 1994)"),
    plot_panel(d[[paste0(P, "12wk_Oral_81mg_diss")]],       "c  81 mg, 10–16 weeks (Boelig et al. 2024)"),
    plot_panel(d[[paste0(I, "12wk_Oral_repeat81mg_diss")]], "d  81 mg daily, 28–32 weeks (Boelig et al. 2024)", xlim = c(2832 - 24 * fig_style$fig3d_days_before, 2840)),
    plot_panel(d[[paste0(P, "25wk_Oral_100mg_diss")]],      "e  100 mg IR, 22–28 weeks (Shanmugalingam et al. 2019)"),
    plot_panel(d[[paste0(P, "25wk_Oral_100mg_EC")]],        "f  100 mg EC, 22–28 weeks (Shanmugalingam et al. 2019)"),
    plot_panel(d[[paste0(P, "25wk_Oral_150mg_diss")]],      "g  150 mg IR, 22–28 weeks (Shanmugalingam et al. 2019)")
  ), "Fig3")
  
  save_figure(list(
    plot_panel(d[["ASA_Oral_50mg_release_1wk"]], "a  50 mg MR daily for 1 week (Bochner et al. 1988)"),
    plot_panel(d[["ASA_Oral_75mg_diss"]],        "b  75 mg oral, non-pregnant (Rymark et al. 1994)"),
    plot_panel(d[["ASA_Oral_100mg_diss"]],       "c  100 mg IR, non-pregnant (Shanmugalingam et al. 2019)"),
    plot_panel(d[["ASA_Oral_150mg_diss"]],       "d  150 mg IR, non-pregnant (Shanmugalingam et al. 2019)")
  ), "FigS2")
  
  save_figure(list(
    plot_panel(d[[paste0(I, "36-38wk_Oral_75mg_diss_orig")]],
               "75 mg, 36–38 weeks, non-pregnant parameters (Rymark et al. 1994)")
  ), "FigS3", ncol = 1)
}


# =====================================================================
# 5. RAT: run, table, figure
# =====================================================================
if (run_rat) {
  rat <- run_project(rat_project_config, unique(tab_S1_def$scenario), rat_data_sheets)
  
  tS1 <- build_table(tab_S1_def, rat)
  out_tables[["Table_S1_rat"]] <- tS1$formatted
  out_raw   <- c(out_raw, list(tS1$raw))
  
  d <- rat$dc
  save_figure(list(
    plot_panel(d[["Rat_IV_200mgperkg"]],           "a  200 mg/kg IV, dataset 1 (Wientjes and Levy 1988)"),
    plot_panel(d[["Rat_IV_200mgperkg_2"]],         "b  200 mg/kg IV, dataset 2 (Wientjes and Levy 1988)"),
    plot_panel(d[["Rat_Oral_200mgperkg"]],         "c  200 mg/kg oral (Wientjes and Levy 1988)"),
    plot_panel(d[["Rat_Oral_100mgperkg"]],         "d  100 mg/kg twice daily, non-pregnant (Wilson et al. 1977)"),
    plot_panel(d[["Rat_Oral_150mgperkg"]],         "e  150 mg/kg twice daily, non-pregnant (Wilson et al. 1977)"),
    plot_panel(d[["PregnantRat_Oral_100mgperkg"]], "f  100 mg/kg twice daily, pregnant (Wilson et al. 1977)"),
    plot_panel(d[["PregnantRat_Oral_150mgperkg"]], "g  150 mg/kg twice daily, pregnant (Wilson et al. 1977)")
  ), "FigS1")
}


# =====================================================================
# 6. Save tables and session information
# =====================================================================
raw <- bind_rows(out_raw) %>%
  select(section, label, scenario, analyte, win_start, win_end,
         Sim_Cmax, Obs_Cmax, Sim_Tmax, Obs_Tmax, Sim_AUC, Obs_AUC, Cmax, Tmax, AUC)

write_xlsx(c(out_tables, list(Raw_values = raw)),
           file.path(out_dir, "Manuscript_tables_reproduced.xlsx"))

# Software versions used for this run
writeLines(c(paste("Run date:", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
             paste("auc_to_last_obs:", auc_to_last_obs), "",
             capture.output(sessionInfo())),
           file.path(out_dir, "sessionInfo.txt"))

cat("\nTables, figures and session information written to:", normalizePath(out_dir), "\n")