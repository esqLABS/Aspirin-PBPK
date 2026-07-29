local({
  renv_active <- file.exists("renv/activate.R")

  # State 1: renv not initialized yet.
  if (!renv_active) {
    message(
      "This project hasn't been set up yet.\n",
      "Step 1: install renv if needed: `install.packages(\"renv\")`\n",
      "Step 2: run `renv::init(settings = list(snapshot.type = \"implicit\"))`, then restart R when prompted.\n",
      "renv will install the starter packages.\n",
      "See README.md for the full setup walk-through."
    )
    return()
  }

  # renv is initialized -- activate it for all later states.
  source("renv/activate.R")

  # State 2: packages installed but ESQlabsR project not initialized.
  # Only prompt to run initProject() if esqlabsR is actually available;
  # otherwise let renv's own out-of-sync notice guide the user to restore().
  if (!file.exists("ProjectConfiguration.xlsx")) {
    if (requireNamespace("esqlabsR", quietly = TRUE)) {
      warning(
        "ESQlabsR project not initialized.\n",
        "Run `esqlabsR::initProject()` to scaffold the project.",
        call. = FALSE
      )
    }
    return()
  }

  # State 3: fully initialized -- check env vars referenced in ProjectConfiguration.xlsx
  used_env_vars <- unique(grep(
    "^[A-Z_]+$",
    unlist(strsplit(
      x = readxl::read_excel("ProjectConfiguration.xlsx")$Value,
      "/"
    )),
    value = TRUE
  ))
  missing_env_vars <- used_env_vars[Sys.getenv(used_env_vars) == ""]

  if (length(missing_env_vars) > 0) {
    message(
      "ProjectConfiguration.xlsx references environment variables whose values are not set.\n",
      "Open .Renviron with `usethis::edit_r_environ('project')` and append:\n",
      paste(paste0(missing_env_vars, "="), collapse = "\n")
    )
  }
})
