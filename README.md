# ESQlabs Project Template

Welcome to your new ESQlabs project! This README will guide you through everything you need to know to get started. 📊

## 📋 What's Included

This template comes with everything you need to start a standardized ESQlabs project:

- **Ready-to-use folder structure** for organizing your work
- **Pre-configured R environment** to ensure consistency across team members
- **Version control with Git** to track changes and collaborate effectively
- **PK-Sim models and modules** for pharmaceutical modeling tasks

## 🚀 Quick Start

### If you just created this project from the template

This sets up an isolated package environment for your project, installs the
starter packages, and locks them for reproducibility.

1. **Open the project in RStudio** by double-clicking the `.Rproj` file.
2. Make sure a **`GITHUB_PAT`** token is defined. See [troubleshooting](https://techbook.esqlabs.com/troubleshooting.html) for documentation.
3. **Install renv** if you don't already have it:
   ```r
   install.packages("renv")
   ```
4. **Initialize renv and install the starter packages** (this may take several minutes):
   ```r
   renv::init(settings = list(snapshot.type = "implicit"))
   ```
   renv reads `DESCRIPTION` (which lists the starter packages and pins the GitHub ones to `@*release`), installs everything, and writes `renv.lock`. Restart R when prompted. Commit `renv.lock` to Git so collaborators get the same environment via `renv::restore()`.


5. **Initialize the ESQlabsR project structure**:
   ```r
   esqlabsR::initProject()
   ```
   Learn more about the [esqlabsR project structure](https://esqlabs.github.io/esqlabsR/articles/esqlabsR-project-structure.html).
6. **Add your project description** at the top of this file.

### If you're joining a project already created from this template

1. **Open the project in RStudio** by double-clicking the `.Rproj` file.
2. Make sure a **`GITHUB_PAT`** token is defined. See [troubleshooting](https://techbook.esqlabs.com/troubleshooting.html) for documentation.
3. **Install packages**:
   - If the project has a `renv.lock`, run:
     ```r
     renv::restore()
     ```
   - Otherwise, ask the project lead which packages to install.



## 📁 Project Organization

After initialization the project or checking out the repository with initialized project, your folder structure should look like this:

```
├── Code/     # Your R scripts and functions
├── Data/     # Raw and processed data files - must be moved to SharePoint!
├── Models/   # Model files (includes pre-built templates)
├── Reports/  # Documentation and reports
└── Results/  # Output files, plots, and analysis results
```

## 🧰 Common Operations

This project uses `renv` to maintain consistent R package versions across your team. First-time setup is covered in the [Quick Start](#-quick-start) above.

### Adding packages

1. Install it:
   ```r
   renv::install("packageName")            # CRAN
   renv::install("user/repo@*release")     # GitHub (pin to latest release)
   ```
   > ⚠️ GitHub packages should always use `@*release` so renv installs the latest published release rather than the moving tip of the default branch.
2. Update the lock file:
   ```r
   renv::snapshot()
   ```
3. Commit the updated `renv.lock` to Git.

### Syncing with team updates

If you see this message at startup:

```
- Project loaded. [renv]
- The project is out-of-sync -- use `renv::status()` for details.
```

Run:
```r
renv::restore()
```

## 🤝 Collaboration

### Sharing project configuration

Project configuration lives in Excel files (`ProjectConfiguration.xlsx` and `Configurations/*.xlsx`), but these are **gitignored** — Git and Excel don't mix well, so the Excel files never travel through the repository. Instead, configuration is shared as a JSON snapshot that **is** committed.

Two commands move configuration between Excel (what you edit) and JSON (what your teammates see):

| | Command | When |
|---|---|---|
| **Before committing** | `esqlabsR::snapshotProjectConfiguration()` | After changing any Excel config — writes the JSON snapshot. |
| **After pulling** | `esqlabsR::restoreProjectConfiguration()` | Rebuilds your Excel files from the latest JSON snapshot. |

So the loop is: edit Excel → `snapshotProjectConfiguration()` → commit the JSON. On the other side: pull → `restoreProjectConfiguration()` → your Excel matches.

> ⚠️ Forgetting to snapshot before committing is the most common mistake — your Excel changes won't reach the team. Forgetting to restore after pulling means your Excel is out of date.

See the [esqlabsR documentation](https://esqlabs.github.io/esqlabsR/reference/snapshotProjectConfiguration.html) for details.

### Linking observed data via SharePoint

Observed data Excel files may be shared through SharePoint instead of git. In this situation, follow these steps:

1. Sync your project's SharePoint folder to your computer.
2. Move Excel data files from the `Data` folder to your SharePoint folder (to be done by project lead at the initialization of the project).
3. After loading the project in RStudio, open your project `.Renviron` file:
   ```r
   usethis::edit_r_environ(scope = "project")
   ```
4. Add the SharePoint path:
   ```
   PROJECT_DATA_FOLDER="path/to/your/sharepoint/project_folder/data_folder"
   ```
5. In `ProjectConfiguration.xlsx`, set the `DataFolder` value to: `PROJECT_DATA_FOLDER`
6. Restart RStudio.

### Working with large files (Git LFS)

Git limits file sizes. Use Git LFS for files larger than 100 MB.

> 💡 **Note**: This template repository does not use Git LFS (since template repositories cannot include LFS files), but you can set up Git LFS in your project after creating it from this template.

**To add large files to your project:**

1. Install [Git LFS](https://git-lfs.github.com/) on your computer.
2. Initialize Git LFS in your repository:
   ```bash
   git lfs install
   ```
3. Track your large file:
   ```bash
   git lfs track "path/to/large/file.pkml"
   ```
4. Commit the file and tracking configuration:
   ```bash
   git add path/to/large/file.pkml
   git add .gitattributes
   git commit -m "Add large file"
   git push
   ```

## 📚 Pre-built Model Resources

### PK-Sim Project with Default Expression
Located at: `Models/Snapshots/Default_PBPK_Individual_V11_and_V12.json`

This file contains standard protein expressions used in DDI publications.

### Species Extrapolation Module
Located at: `Models/PKML/Module_Species_Scaling_from_Human.pkml`

This module helps with species extrapolations in MoBi from human to animal species.

Usage:
1. Start with a model using human spatial structure
2. Create an animal individual
3. Load the "Species Scaling from Humans" module
4. Add the individual and and the PV BB `Saliva_and_Gallbladder` from the extension module.

### Spatial Structure BB with Organism Template Structure
Located at:  `Models/PKML/Template_organism_BB.pkml`
             `Models/PKML/Template_organism_BB_with_subcomparments.pkml`

The pkml files add a template Organism structure containing all organs (w/wo sub-compartments), as Spatial Structure BB. A typical use case is to create a module that adds new containers to all standard organs or their subcompartments (see also TalentLMS course Lysosomal trapping M04-12).

Usage:
1. Create a new extension module 
2. Load the pkml as Building Block
3. Load that module after your base module


## 📘 Need More Help?

For ESQlabs R resources (guides, troubleshooting, conventions), check [ESQlabs technical handbook](https://techbook.esqlabs.com).

For Git and GitHub collaboration, see the [ESQlabs Git Guide](https://techbook.esqlabs.com/topics/git/git-introduction.html).

---
*Remember to replace this template content with your specific project information, but keep the instruction sections for reference.*
