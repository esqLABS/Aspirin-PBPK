# Aspirin PBPK Models — Rat and Human, Non-Pregnant and Pregnant

This repository contains the PK-Sim/MoBi (Open Systems Pharmacology / OSP Suite) project files, source data, and analysis code underlying the aspirin/salicylic acid (SA) PBPK modeling work reported in *[Work Package 7 & 8 Report — Physiologically Based Kinetic (PBK) Models for Aspirin]*. It is made publicly available in fulfillment of the Global Access commitments of the funding grant.

## License

This repository is released under the **GPL 2.0** license. See [LICENSE](./LICENSE) for details.

## Repository contents

| File / folder | Description |
|---|---|
| `Reports/WP7_WP8_Report_v5.pdf` | The full closeout report: methods, parameter provenance, datasets, validation results, disclosed limitations, and the complete reproducibility guide referenced throughout this README. |
| `Project files/Aspirin PBPK_human.pksim5`<br>`Project files/Aspirin PBPK_rat.pksim5` | Runnable non-pregnant PK-Sim project files (human and rat). |
| `Project files/HumanPregnancyModel.mbp3`<br>`Project files/RATPregnancyModel.mbp3` | Runnable pregnant MoBi project files (human and rat). |
| `Data/TimeValuesData_forPKML.xlsx` | Digitized source data underlying all calibration/validation comparisons, one sheet per study. |
| `Code/Fu_scale_code.R` | Calculates gestational-age-specific fraction-unbound values for the pregnant models. |
| `Plot code/` | R workflow used to run scenarios and generate all figures and performance tables. |

For full descriptions, file-by-file usage notes, and the complete reproducibility guide, see **`Reports/WP7_WP8_Report_v5.pdf`**.

## Requirements

- **PK-Sim and MoBi** (Open Systems Pharmacology / OSP Suite) — version 12.3
- **R**, with packages: `esqlabsR`, `ESQapp`, `ggplot2`, `dplyr`, `DescTools`, `readxl`, `tlf`, `purrr`, `tidyr`, `writexl`

## How to reproduce reported results

For full file descriptions, the complete build order, the parameter identification method, and known factors affecting exact reproduction (e.g., IVIVE-constrained fitting ranges, fixed-time-window PK-parameter calculations), see **`Reports/WP7_WP8_Report_v5.pdf`**.

1. Open the non-pregnant `.pksim5` files directly in PK-Sim to inspect or re-run the non-pregnant models.
2. Open the pregnant `.mbp3` files directly in MoBi to inspect or re-run the pregnant models.
3. Use `Fu_scale_code.R` to recalculate gestational-age-specific fraction-unbound values if modifying the pregnant models.
4. Use the `Plot code/` workflow to regenerate all figures and fold-difference/performance tables reported in the manuscript.


## Need More Help?

For ESQlabs R resources (guides, troubleshooting, conventions), check [ESQlabs technical handbook](https://techbook.esqlabs.com).

For Git and GitHub collaboration, see the [ESQlabs Git Guide](https://techbook.esqlabs.com/topics/git/git-introduction.html).


