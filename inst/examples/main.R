library(devtools)
library(dplyr)
library(sorvi)
library(bibliographica)
library(estc)

# I/O definitions
# make daily output folders TODO convert into function -vv
today.str <- as.character(Sys.Date())
# NOTE / LL: I now discard this change and return the earlier output.tables
# for two key reasons:
# 1) the modification date is visible in the github stamps in any case
# 2) it is quite beneficial for cross-linking and other purposes
#    to have a static url
#    for these key summary tables - the idea is that they are always up-to-date
#    with the most recent package versions and for that the date does not
#    matter; the date can be included if we freeze some versions
#    of the data, but this can be done separately when it really matters
#    (for instance for conferences & publications)
#    This also helps to keep the code more simple. We are linking to these
#    tables for instance from the github summary pages.
# -> However we can discuss and change these policies if you have
#    good arguments.
# output.folder <- paste("output.tables/", today.str, "/", sep = '')
# old version:
output.folder <- "output.tables/"
dir.create(output.folder)

# List preprocessed data files
fs <- "estc_parsed.csv.gz"
catalog <- "estc"

# Languages to consider in cleanup.
# TODO: recognize the necessary languages automatically ?
languages <- c("english", "latin")

# Cores: does not seem to work at the moment
mc.cores <- 4

# Update selected fields only -
# comment out if not needed
# update.fields <- c("physical_extent")
# update.fields <- c("publication_place")
# update.fields <- c("publication_place", "author_name", "author_date")
update.fields <- NULL

# Remove selected fields
ignore.fields <- c("title_uniform", "title_uniform2") # ESTC

# ----------------------------------------------------
#            LOAD DATA FOR PREPROCESSING
# ----------------------------------------------------

# reload.data <- FALSE
source(system.file("extdata/init.R", package = "bibliographica"))
# all the source calls just load functions now

# load initial data
df.orig <- load_initial_datafile(fs, ignore.fields, reload.data = FALSE)
# returns: df.orig

# Test with small data test set
# df.orig <- df.orig[sample(1:nrow(df.orig), 1000),] # random 1000
# df.orig <- df.orig[1:1000, ] # first 1000



# load data for preprocessing
data.preprocessing <- get_preprocessing_data(df.orig, 
                                             update.fields,
                                             ignore.fields)
# returns list of 3 (df.preprocessed, update.fields, conversions)

# obs!: All following functions now return lists of 3 or 2, with generally 
#       the same objects- we could make this neater by packaking all in S3
#       object. Functions could take as both input and output an instance of
#       that class then.

#       For now decided to input&output same list of 3:
#       (df.preprocessed, update.fields, conversions)

# ----------------------------------------------------
#           PREPROCESS DATA
# ----------------------------------------------------

source(system.file("extdata/preprocessing.R", package = "bibliographica"))

data.preprocessed <- preprocess_data(data.preprocessing, 
                                     df.orig,
                                     languages, 
                                     mc.cores = 4)
rm(data.preprocessing)
# returns list of 3 (df.preprocessed, update.fields, conversions)

# ----------------------------------------------------
#           VALIDATE PREPROCESSED DATA
# ----------------------------------------------------

data.validated <- validate_preprocessed_data(data.preprocessed)
# returns list of 3 (df.preprocessed, update.fields, conversions)
rm(data.preprocessed)

# -----------------------------------------------------
#           ENRICH VALIDATED DATA
# ----------------------------------------------------

data.enriched <- enrich_preprocessed_data(data.validated, df.orig)
# returns list of 3 (df.preprocessed, update.fields, conversions)
# some function(s) need df.orig. Should tidy that up? -vv
# -> would be nice but might prove challenging - welcome to implement if possible -LL
# rm(data.validated)

# Custom enrich for ESTC
data.enriched.estc <- enrich_estc(data.enriched, df.orig)

# ----------------------------------------------------

data.validated2 <- validate_preprocessed_data(data.enriched.estc)

# -----------------------------------------------------

# Pick the final data
df.preprocessed <- data.validated2$df.preprocessed

# ----------------------------------------------------

print("Saving updates on preprocessed data")
saveRDS(df.preprocessed, file = "data/df.Rds", compress = TRUE)

# ----------------------------------------------------

print("Analyze the preprocessed data")
source("analysis.R")

print("All OK.")

# Test map visualizations (estc/old)
# source("map.R")
