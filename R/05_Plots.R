posteriorNameFromControls <- function(controls) {
  return(paste(
    controls$region, controls$type, controls$ind_eta, controls$iterations,
    "iter", controls$chains, "chains", controls$timestamp, sep = "_"))
}

# ----------------------------------------------------------------------------#
# plots for all regions (individually) ---- 
# ----------------------------------------------------------------------------#

# the following lines very simply call the full 04_ModelDiagnostics.R for 
# each posterior individually. It takes some time, but should run fine.

for(posterior in list.files("Posteriors")) {
  print(posterior)
  posteriorName <- posterior
  source("R/04_ModelDiagnostics.R")
  remove(list = ls())
}
posteriorNameRegions <-
  str_sub(list.files("Posteriors"), 1,
          str_locate(list.files("Posteriors"), "\\.")[,1]-1)

# ----------------------------------------------------------------------------#
# generate data for all samples (outdated) ----
# DO NOT USE UNLESS YOU REALLY KNOW WHAT YOU'RE DOING!!!
# ----------------------------------------------------------------------------#
# the following code can be used to extract data from all the posteriors that
# are in the respective directory. Only run this code when you want to update
# all the posteriors.
source("setup.R")
generatedQuantitiesList <- list()
for(posteriorName in list.files("Posteriors")) {
  print(posteriorName)
  remove("controls", "sample", "list")
  controls <- extractPosteriorMetadata(posteriorName)
  check_controls(controls)
  sample <- initialiseSample(posteriorName, type = controls$type)
  if(controls$chains != as.character(sample$metadata$chains) |
     controls$iterations != as.character(sample$metadata$iterations)) {
    stop(paste("Error: posterior metadata did not match its name\n",
               posteriorName))
  }
  list <- list(append(sample, controls))
  names(list) <- posteriorName
  generatedQuantitiesList <- append(generatedQuantitiesList, list)
}
saveRDS(generatedQuantitiesList, "data/00_generatedQuantities.Rds")

# this code extracts data about the generated quantities from all the 
# posteriors
{
  generatedQuantitiesList <- readRDS("data/00_generatedQuantities.Rds")
  
  generatedQuantitiesSummary <- list()
  for (parameter in c("per_day", "per_group", "per_both", "per_none")) {
    parameterSummary <- map_dfr(generatedQuantitiesList, function(x) {
      x$parameters[[parameter]] %>% 
        add_column(region = x$region, 
                   type = x$type,
                   ind_eta = x$ind_eta,
                   chains = x$chains,
                   iterations = x$iterations,
                   timestamp = x$timestamp)
    })
    generatedQuantitiesSummary <- append(generatedQuantitiesSummary,
                                         list(parameterSummary))
  }
  
  names(generatedQuantitiesSummary) <- c("per_day", "per_group",
                                         "per_both", "per_none")
  generatedQuantitiesSummary <- map_dfr(generatedQuantitiesSummary,
                                        function(x) {
                                          group_by(x, parameter) %>% nest()
                                        })
  
  quantityMetadataTable <- quantityMetadataTable(controls$type) %>% 
    mutate(parameter = str_replace(parameter, "(age)|(gender)", "group"))
  
  generatedQuantitiesSummary <- generatedQuantitiesSummary %>% 
    mutate(
      parameter = str_replace(parameter, "(age)|(gender)", "group"),
      parameter = factor(parameter,
                         levels = quantityMetadataTable$parameter))
}
# ----------------------------------------------------------------------------#


# ----------------------------------------------------------------------------#
# generate data for all samples ----
# ----------------------------------------------------------------------------#

# the following code generates all the data necessary for plotting for all the
# posteriors in the respectiv folders. The data includes:
#  - sample             sampleRegions
#  - controls           controlsRegions
#  - data_list_model    dlmRegions
#  - day_max, day_data  daysRegions
# For each of these objects, a list is created. Objects in these lists are 
# named and have the same order as the posteriors. Objects can be accessed by
# (for example) sampleRegions[[2]] to get the sample for the second posterior.
source("setup.R")
source("R/99_ContactMatrix_Gender_Age_Function.R")

sampleRegions <- list()
for(posterior in list.files("Posteriors")) {
  sample <- list(readRDS(file = paste0("Posteriors/", posterior)))
  names(sample) <- posterior
  sampleRegions <- append(sampleRegions, sample)
}
controlsRegions <- list()
daysRegions <- list()
dlmRegions <- list()
controls <- list(visualise = F)
for(posterior in list.files("Posteriors")) {
  controlsTemp <- list(extractPosteriorMetadata(posterior))
  names(controlsTemp) <- posterior
  controlsRegions <- append(controlsRegions, controlsTemp)
  source(paste0("R/01_DataManagement_", controlsTemp[[posterior]]["region"], ".R"))
  source(paste0("R/02_PrepareModel_", controlsTemp[[posterior]]["type"], ".R"))
  daysTemp <- list(list("day_data" = day_data, "day_max" = day_max))
  names(daysTemp) <- posterior
  daysRegions <- append(daysRegions, daysTemp)
  dlmtemp <- list(data_list_model)
  names(dlmtemp) <- posterior
  dlmRegions <- append(dlmRegions, dlmtemp)
}
posteriorNameRegions <-
  str_sub(list.files("Posteriors"), 1,
          str_locate(list.files("Posteriors"), "\\.")[,1]-1)
remove_except(list("dlmRegions", "daysRegions", "controlsRegions",
                   "sampleRegions", "posteriorNameRegions"))
source("setup.R")
source("R/99_DataFunctions.R")
source("R/99_PlotFunctions.R")
# ----------------------------------------------------------------------------#


# ----------------------------------------------------------------------------#
# plots to compare samples ----
# ----------------------------------------------------------------------------#

# The following code generates plots to compare different posteriors next to
# each other. Using pretty dumb for-loops, plots are
# generated for each posterior and then saved in plotlist. Specifiy which 
# posteriors you want to plot by changing the iterator values in the loop.
# Plots are lated plotted using cowplot's plot_grid().

# generate data for the chosen regions
plotlist <- list("time" = list(), "total" = list(), "groups" = list())
for(i in c(7,9,8)) { # choose which regions you want to plot
  simvsrealTimeCases <- data_SimVsReal_Time(metric = "cases",
                                            sample = sampleRegions[[i]],
                                            day_max = daysRegions[[i]]$day_max,
                                            day_data = daysRegions[[i]]$day_data,
                                            data_list_model = dlmRegions[[i]])
  plotlist$time <-
    append(plotlist$time,
           list(plot_SimVsReal_Time(simvsrealTimeCases, "cases",
                                    day_max = daysRegions[[i]]$day_max,
                                    day_data = daysRegions[[i]]$day_data,
                                    dlmRegions[[i]])))
  simvsrealTotalCases <- data_SimVsReal_Total(sample = sampleRegions[[i]],
                                              metric = "cases",
                                              data_list_model = dlmRegions[[i]],
                                              controls = controlsRegions[[i]])
  plotlist$total <-
    append(plotlist$total,
           list(plot_SimVsReal_Total(simvsrealTotalCases,
                                     metric = "cases",
                                     plotSums = "time")))
  simvsrealGroupCases <- data_SimVsReal_Group(sample = sampleRegions[[i]],
                                              metric = "cases",
                                              data_list_model = dlmRegions[[i]],
                                              controls = controlsRegions[[i]])
  plotlist$groups <-
    append(plotlist$groups,
           list(plot_SimVsReal_Group(simvsrealGroupCases,
                                     metric = "cases",
                                     controls = controlsRegions[[i]])))
}

# use the generated data to plot a comparison of cases
legend <- get_legend(plotlist$time[[1]] + theme(legend.direction = "horizontal",
                                                legend.title = element_blank()))
comparisonCases <- cowplot::plot_grid(
  plot_grid(
    plotlist$time[[1]] + guides(linetype = F, fill = F, col = F) +
      labs(x = NULL),
    plotlist$total[[1]] + guides(linetype = F, fill = F, col = F) +
      labs(x = NULL),
    plotlist$groups[[1]] + guides(linetype = F, fill = F, col = F) +
      labs(x = NULL),
    plotlist$time[[2]] + guides(linetype = F, fill = F, col = F) +
      labs(subtitle = NULL, x = NULL),
    plotlist$total[[2]] + guides(linetype = F, fill = F, col = F) +
      labs(subtitle = NULL, x = NULL),
    plotlist$groups[[2]] + guides(linetype = F, fill = F, col = F) +
      labs(subtitle = NULL, x = NULL),
    plotlist$time[[3]] + guides(linetype = F, fill = F, col = F) +
      labs(subtitle = NULL),
    plotlist$total[[3]] + guides(linetype = F, fill = F, col = F) +
      labs(subtitle = NULL),
    plotlist$groups[[3]] + guides(linetype = F, fill = F, col = F) +
      labs(subtitle = NULL, x = "Group"),
    align = "hv", axis = "b", rel_widths = c(1, 0.4, 1),
    labels = c("A1", "A2", "A3", "B1", "B2", "B3", "C1", "C2", "C3"),
    label_x = c(-.01, -.5, -.01, rep(c(-.01, -.1, -.01), 2)),
    label_y = c(1, 1, 1, rep(1.1, 9))
  ),
  legend, nrow = 2, rel_heights = c(10,1)
)
save_gg(comparisonCases,"Comparison_Spain_Cases", width = 7, height = 7.5)

# use the generated data to plot a comparison of deaths
plotlist <- list("time" = list(), "total" = list(), "groups" = list())
for(i in c(7,9,8)) { # choose which regions you want to plot
  simvsrealTimeDeaths <- data_SimVsReal_Time(metric = "deaths",
                                            sample = sampleRegions[[i]],
                                            day_max = daysRegions[[i]]$day_max,
                                            day_data = daysRegions[[i]]$day_data,
                                            data_list_model = dlmRegions[[i]])
  plotlist$time <- 
    append(plotlist$time,
           list(
             plot_SimVsReal_Time(simvsrealTimeDeaths, "deaths",
                                 day_max = daysRegions[[i]]$day_max,
                                 day_data = daysRegions[[i]]$day_data,
                                 dlmRegions[[i]])
           )
    )
  simvsrealTotalDeaths <- data_SimVsReal_Total(sample = sampleRegions[[i]],
                                              metric = "deaths",
                                              data_list_model = dlmRegions[[i]],
                                              controls = controlsRegions[[i]])
  plotlist$total <-
    append(plotlist$total,
           list(
             plot_SimVsReal_Total(simvsrealTotalDeaths,
                                  metric = "deaths",
                                  plotSums = "time")
           )
    )
  simvsrealGroupDeaths <- data_SimVsReal_Group(sample = sampleRegions[[i]],
                                              metric = "deaths",
                                              data_list_model = dlmRegions[[i]],
                                              controls = controlsRegions[[i]])
  plotlist$groups <-
    append(plotlist$groups,
           list(plot_SimVsReal_Group(simvsrealGroupDeaths,
                                     metric = "deaths",
                                     controls = controlsRegions[[i]])
           )
    )
}
legend <- get_legend(plotlist$time[[1]] + theme(legend.direction = "horizontal",
                                                legend.title = element_blank()))
comparisonDeaths <- cowplot::plot_grid(
  plot_grid(
    plotlist$time[[1]] + guides(linetype = F, fill = F, col = F),
    plotlist$total[[1]] + guides(linetype = F, fill = F, col = F),
    plotlist$groups[[1]] + guides(linetype = F, fill = F, col = F),
    plotlist$time[[2]] + guides(linetype = F, fill = F, col = F),
    plotlist$total[[2]] + guides(linetype = F, fill = F, col = F),
    plotlist$groups[[2]] + guides(linetype = F, fill = F, col = F),
    plotlist$time[[3]] + guides(linetype = F, fill = F, col = F),
    plotlist$total[[3]] + guides(linetype = F, fill = F, col = F),
    plotlist$groups[[3]] + guides(linetype = F, fill = F, col = F),
    align = "hv", axis = "b", rel_widths = c(1, 0.3, 1),
    labels = c("A1", "A2", "A3", "B1", "B2", "B3", "C1", "C2", "C3"),
    label_x = c(-.01, -.5, -.01, rep(c(-.01, -.1, -.01), 2)),
    label_y = c(1, 1, 1, rep(1.1, 9))
  ),
  legend, nrow = 2, rel_heights = c(10,1)
)
save_gg(comparisonCases,"Comparison_Spain_Deaths", width = 7, height = 7.5)


# ----------------------------------------------------------------------------#
# tables for parameter overviews ----
# ----------------------------------------------------------------------------#
# this code block attempts to export tables to Latex
for(i in seq_along(list.files("Posteriors"))) {
  print(list.files("Posteriors")[[i]])
  # get the parameter values
  if(controlsRegions[[i]]$ind_eta == "VaryingEta") {
    parRegions <- summary(sampleRegions[[i]],
                          c("beta", "psi", "pi", "nu",
                            "xi", "phi[1]", "phi[2]"))[[1]]
    parNames <- c("$\\beta$", "$\\psi$", "$\\pi$", "$\\nu$", "$\\xi$",
                  "$\\phi_1$", "$\\phi_2$")
    parDescription <- c("Probability of transmission upon contact",
                        "Proportion of symptomatic infections",
                        "Initial proportion of infected in the population",
                        "Delay of implementation of control measures (days)",
                        "Slope of implementation of control measures",
                        "Overdispersion parameter for cases",
                        "Overdispersion parameter for deaths")
  } else if (controlsRegions[[i]]$ind_eta == "CommonEta") {
    parRegions <- summary(sampleRegions[[i]],
                          c("beta", "psi", "pi", "eta", "nu",
                            "xi", "phi[1]", "phi[2]"))[[1]]
    parNames <- c("$\\beta$", "$\\psi$", "$\\pi$", "$\\eta$", "$\\nu$",
                  "$\\xi$", "$\\phi_1$", "$\\phi_2$")
    parDescription <- c("Probability of transmission upon contact",
                        "Proportion of symptomatic infections",
                        "Initial proportion of infected in the population",
                        "Reduction of transmission due to control measures",
                        "Delay of implementation of control measures (days)",
                        "Slope of implementation of control measures",
                        "Overdispersion parameter for cases",
                        "Overdispersion parameter for deaths")
  }
  # prepare the tibble
  parTibble <- tibble("Parameter" = parNames,
                      "Interpretation" = parDescription,
                      "Posterior Median (95\\% CI)" = str_c(
                        signif(parRegions[,"50%"], 2), " [",
                        str_c(signif(parRegions[,"2.5%"], 2),
                              signif(parRegions[,"97.5%"], 2),
                              sep = " - "), "]"))
  # write a caption
  parCaption <- paste0("Posterior distributions of the general parameters in ",
                       controlsRegions[[i]]$region, " (model for ",
                       str_to_lower(controlsRegions[[i]]$type),
                       " groups with ",
                       str_to_lower(
                         str_extract(controlsRegions[[i]]$ind_eta,
                                     "[:alpha:]*(?=(Eta))")), " $\\eta$)")
  # write a label
  parLabel <- paste0("tab:ParamTable", controlsRegions[[i]]$region, "_",
                     controlsRegions[[i]]$type, "_",
                     controlsRegions[[i]]$ind_eta)
  xtable::xtable(parTibble,
                 caption = parCaption, label = parLabel,
                 align = c("l", "l", "p{9cm}", "p{3cm}")
  ) %>% 
    print(paste0("Tables/Parameters_",
                 posteriorNameRegions[i],".tex"),
          type = "latex", include.rownames=FALSE,
          sanitize.text.function=function(x){x}) # this makes it possible to 
  # have math mode, but all LaTeX special character need to be escaped
}


# ----------------------------------------------------------------------------#
# plots to compare fatality ratios ----
# ----------------------------------------------------------------------------#

# we need the data generated in section "generate data for all samples"
# here we use it to extract the smulated FRs
realRegions <- list()
simRegions <- list()
for (posterior in names(sampleRegions)) {
  data <- data_CFR_Total(controlsRegions[[posterior]],
                         dlmRegions[[posterior]], sampleRegions[[posterior]])
  real <- list(data$real)
  names(real) <- posteriorNameFromControls(controlsRegions[[posterior]])
  sim <- list(data$sim)
  names(sim) <- posteriorNameFromControls(controlsRegions[[posterior]])
  realRegions <- append(realRegions, real)
  simRegions <- append(simRegions, sim)
}
bind_rows(realRegions, .id = "id")


simFRRegions <- bind_rows(simRegions, .id = "id") %>% 
  mutate(metric_description = fct_relevel(factor(metric_description),
                                          "CFR (simulated)",
                                          "sCFR (simulated)",
                                          "IFR (simulated)"),
         controls = str_split(id, "_")) %>%
  unnest_wider(controls) %>% 
  mutate(xlabel = str_c(...1, " (", ...2, ",\n", ...3, ")")) %>% 
  select(metric_description, `2.5%`, `50%`, `97.5%`, xlabel)
realCFRRegions <- bind_rows(realRegions, .id = "id") %>% 
  mutate(controls = str_split(id, "_")) %>% 
  unnest_wider(controls) %>% 
  mutate(xlabel = str_c(...1, " (", ...2, ",\n", ...3, ")")) %>% 
  select(name, value, xlabel) %>% 
  filter(name == "CFRoverTime")
  
plot_CFR_total_regions <- ggplot() +
  geom_col(data = realCFRRegions, aes(x = xlabel, y = value),
           fill = "white", color = "black", width = 0.67) +
  geom_pointrange(data = simFRRegions,
                  aes(x = xlabel, col = metric_description, ymin = `2.5%`, y = `50%`, ymax = `97.5%`),
                  position = position_dodge2(width = 0.6, padding = 0.1)) +
  scale_x_labelsRotate() + labs(x = NULL) +
  scale_y_percent(name = NULL,
                  breaks = c(0.05, 0.1, 0.15, 0.2, 0.25)) +
  scale_colour_manual(values = c("#B22222", "#66CD00", "#00B2EE"),
                      name = "Fatality ratio\n(95% CI)") +
  theme(legend.direction = "horizontal", legend.position = "bottom")
save_gg(plot_CFR_total_regions, "CFRtotal_AllRegions", width = 7, height = 5)
