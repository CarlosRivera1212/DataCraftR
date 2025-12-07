# DataCraftR <img src="man/figures/logo.png" align="right" height="138" alt="" />

**DataCraftR** is an R package that provides a set of interactive tools for **data generation through visualization**.  
Each tool is implemented as a **Shiny addin** integrating **D3.js** for real-time, graphical data creation.  

> **Inspried on**: [drawdata.xyz](https://github.com/koaning/drawdata)
> **Powered by**: [Shiny](https://shiny.posit.co/) and [D3](https://d3js.org/)

---

## :sparkles: Overview

DataCraftR allows users to *draw* or *manipulate* visual representations of data (boxplots, histograms, scatterplots) and automatically generate the corresponding datasets in R.

This package is ideal for teaching, demonstrations, or prototyping datasets based on distributional intuition.

---

## :jigsaw: Features

- :takeout_box: Interactive **Boxplot**: drag quantiles to define distributions.
- :bar_chart: Interactive **Histogram**: draw bar heights to define data frequency.
- :white_circle: Interactive **Scatter **: paint clusters or point groups directly. 
- :floppy_disk: One-click export of generated data to RDS temporal file.
- :brain: Designed as RStudio **Addins** for quick access.
- :gear:️ Built with **Shiny** and **D3.js** for modern, responsive UI.

---

## :rocket: Installation

```r
# From GitHub
# (requires the 'remotes' package)
install.packages("remotes")
remotes::install_github("your-username/DataCraftR")
```

---

## :brain: Usage

Each visualization tool can be launched directly from R or from the RStudio Addins menu.

```r
# Boxplot generator
DataCraftR::boxplot_dcr()

# Histogram generator
DataCraftR::histogram_dcr()

# Scatter plot generator
DataCraftR::scatter_dcr()
```

Each tool opens a Shiny gadget with an interactive D3.js visualization.  
The generated data can be exported to temporal RDS file by clicking **“Save Data”**.

---

## :gear:️ Technical Notes

- The package integrates **Shiny**, **bslib**, **shinyWidgets**, and **D3.js**.  
- Custom JavaScript files are located in `inst/assets/js/` and are loaded dynamically by each addin.  
- All visualizations communicate with R using Shiny’s `sendCustomMessage` and input bindings.

---

## :books: Example Screenshots

#### Screenshot of Scatterplot example
![Scatter Addin](man/figures/scatter_example.png)

#### Screenshot of Boxplot example
![Boxplot Addin](man/figures/boxplot_example.png)  

#### Screenshot of Histogram example
![Histogram Addin](man/figures/histogram_example.png)  

---

## :man_technologist: Author

**Carlos Rivera**

---

## :scroll: License

This package is licensed under the **GPL-3.0 License**.
See the `LICENSE` file for more details.

---

## :memo: Citation

If you use this package in academic work, please cite it as:

> Rivera, C. (2025). *DataCraftR: Interactive Data Generation Tools with Shiny and D3.js.*
> GitHub repository: [https://github.com/CarlosRivera1212/DataCraftR](https://github.com/CarlosRivera1212/DataCraftR)

---

## :compass: Future Directions

- [c] count
- [d] Extend interactivity to line-based density multicategory data.
- [t] tail
- [f] density 2D
- [p] Extend interactivity to proportion bars multicategory data.
- [t] Extend interactivity to tabular proportions data.
- [l] Extend interactivity to line-based temporal data.
- [r] radial
- Integrate export options to CSV or RDS directly from the UI.  
