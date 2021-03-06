params <-
structure(list(min.year = 1470L, max.year = 1880L, time.window = 10L, 
    date = "Sat Oct  7 20:15:44 2017", place = "All", language = "any", 
    document.type = "All", subtitle = "My subtitle", idsource = "history_of_england_headings.txt", 
    update.bibliographica = FALSE), .Names = c("min.year", "max.year", 
"time.window", "date", "place", "language", "document.type", 
"subtitle", "idsource", "update.bibliographica"))

## ----init, echo=FALSE, message=FALSE, warning=FALSE, echo=FALSE, cache=FALSE----
# For all parameter options for rmarkdown slide rendering, see:
# http://rmarkdown.rstudio.com/developer_parameterized_reports.html
# More header options in Pandoc manual
# http://pandoc.org/MANUAL.html#templates

if (params$update.bibliographica) {
  library(devtools)
  install_github("ropengov/bibliographica")
}

# Read parameters from the header
mydate <- params$start
min.year <- params$min.year
max.year <- params$max.year

# Selected place (if any)
selected.place <- params$place

# Time window for the plots
time.window <- params$time.window

# Limit the length of names to print on screen / figures
nchar <- 40

library(devtools)
library(estc)
library(magrittr)
library(bibliographica)
library(reshape2)
library(gridExtra)
library(knitr)
library(ggmap)
#library(stringr)
library(dplyr)
library(tidyr)
library(ggplot2)
library(sorvi)
knitr::opts_chunk$set(echo = FALSE)
#knitr::opts_chunk$set(fig.path = "figure_slides/", dev="CairoPNG")
knitr::opts_chunk$set(fig.path = "figure_slides/")

# Set locale
# tmp <- Sys.setlocale(locale="UTF-8") 

# Nice theme
theme_set(theme_bw(26))

# Nice default themes
# https://github.com/cttobin/ggthemr#palettes
#ggthemr('fresh', text_size = 20)
# ggthemr('greyscale', text_size = 20)
#ggthemr('light', text_size = 20)
# ggthemr('pale', text_size = 20)
#ggthemr_reset() # Reset theme

# Default number of top hits to show
ntop <- 20

## ----data, echo=FALSE, message=FALSE, warning=FALSE, echo=FALSE, cache=FALSE----
## SELECT AND AUGMENT THE COMPLETE DATA SET (df.orig)

# Read the preprocessed data
df.orig <- readRDS("df.Rds") # Keep the complete data

# Add Metadata ID field 
idfield <- "system_control_number"
df.orig$id <- sapply(strsplit(as.character(df.orig[, idfield]), ")"), function (xi) {xi[[length(xi)]]})

# Add document type
df.orig$document_type <- rep(NA, nrow(df.orig))
df.orig$document_type[df.orig$pagecount > 32] <- "Books"
df.orig$document_type[df.orig$pagecount <= 32] <- "Pamphlets"
df.orig$document_type <- factor(df.orig$document_type)

# Set the desired time window (default one decade)
if (time.window == 10) {
  df.orig$publication_time <- df.orig$publication_decade
} else {
  df.orig$publication_time <- time.window * floor(df.orig$publication_year / time.window)
}

# --------------------------------------

## PICK SELECTED SUBSET OF THE DATA (df.preprocessed AND df.preprocessed.allplaces)

# Now pick selected subset (time, place, language..)
df.preprocessed <- df.orig

# Selected time window
df.preprocessed <- df.preprocessed %>% filter(publication_year >= min.year &
			                      publication_year <= max.year)

# Selected language
if (!params$language == "any") {
  df.preprocessed <- df.preprocessed %>% filter(language %in% params$language)
}

# Selected document type
if (!params$document.type == "All") {  
  df.preprocessed <- df.preprocessed %>% filter(document_type %in% params$document.type)

  # Remove issues if Pamphlets are selected
  if (params$document.type == "Pamphlets") {
    df.preprocessed <- df.preprocessed %>% filter(!issue)
  }
  
} 

# Selected place
df.preprocessed.allplaces <- df.preprocessed
if (!selected.place == "All") {
  # Keep version with all places
  # Make version with selected place
  df.preprocessed <- df.preprocessed %>% filter(publication_place %in% selected.place)
}



# ---------------------------------------

## PICK SELECTED DOCUMENTS (df0)

# Read the custom list of entry IDs
# Including also the number of hits per document
# and document total length for normalization purposes
idfile <- params$idsource
custom.ids <- read.table(idfile, skip = 1)[, c(1, 2, 4)]
ids.orig <- as.character(custom.ids[,1])
custom.ids[,1] <- gsub("\\,$", "", as.character(custom.ids[,1]))
custom.ids[,2] <- as.numeric(as.character(custom.ids[,2]))
custom.ids[,3] <- as.numeric(as.character(custom.ids[,3]))
names(custom.ids) <- c("id", "freq", "length")
# Remove leading zeroes from the IDs to get them compatible with our versions
custom.ids$id <- apply(cbind(substr(custom.ids$id, 1, 1),
	               gsub("^[A-Z]0*", "", custom.ids$id)), 1, function (x) {paste(x, collapse = "")})

#---------------------------------------------------------

# Pick entries with the given IDs.. must remove the source ID from the ESTC strings
df0 <- subset(df.preprocessed, id %in% custom.ids$id)

# Selected place
# Keep also version with all places
df0.allplaces <- subset(df.preprocessed.allplaces, id %in% custom.ids$id)  

# Not found
notfound <- setdiff(custom.ids$id, df0$id)

# Combine duplicated customIDs
custom.ids <- custom.ids %>% group_by(id) %>%
	                     summarise(freq = sum(freq, na.rm = T),
	                     	       length = sum(length, na.rm = T)
			     )

# Add normalization field: hits per 1000 words
custom.ids$freq.normalized <- 1e3 * custom.ids$freq/custom.ids$length

# Number and percentage of the custom list IDs that were found
# in the very original data
hitn0 <- sum(custom.ids$id %in% df.orig$id, na.rm = TRUE)
hitp0 <- 100 * hitn0/nrow(custom.ids)

# Hits after final subsetting
hitn1 <- nrow(df0)
hitp1 <- 100 * hitn1/nrow(custom.ids)

# Duplicated entries
duplicated.ids.in.estc <- sum(duplicated(df.preprocessed$id), na.rm = T)
duplicated.ids.in.query <- sum(duplicated(custom.ids$id), na.rm = T)

## ----normalization, echo=FALSE, message=FALSE, warning=FALSE, cache=FALSE, fig.width=7, fig.height=7, out.width="100px", eval=FALSE----
## # Document length vs. normalized hit frequency:
## p <- ggplot(custom.ids, aes(x = length, y = freq.normalized)) +
##        geom_point() + scale_x_log10() + scale_y_log10() +
##        xlab("Document length") + ylab("Hits per unit length (x1000)")
## print(p)

## ----titlecount, echo=FALSE, message=FALSE, warning=FALSE, echo=FALSE, cache=FALSE, fig.width=15, fig.height=7----
# If selected place is given, then show
# both the selected and all places
myfield <- "titlecount"
df1 <- NULL
if (!selected.place == "All") {
  df1 <- df0.allplaces
}

# Standard timeline
# If place selection is applied then show both the
# selected place and total data
p1 <- plot_timeline(df0, x = "publication_decade", y = myfield,
        nmin = 0, mode = "absolute") +
        ylab("Title count (n)") +
	ggtitle("Total title count timeline ()") 
	#guides(fill = "none") 

if (!selected.place == "All") {
  p1 <- p1 + scale_fill_manual("Place", 
                      values = c("black", "darkgray"), 
                      labels = c(selected.place, "All"))
}

p1 <- p1 + scale_y_log10()


# Compare the selected field in between the two data sets
df <- timeline_relative(df0, df.preprocessed, myfield)
df$group <- rep(selected.place, nrow(df))
if (!selected.place == "All") {
  df.allplaces <- timeline_relative(df0.allplaces, df.preprocessed.allplaces, myfield)
  df.allplaces$group <- rep("All", nrow(df.allplaces))
  df <- bind_rows(df, df.allplaces)
}
df$group <- factor(df$group)

# Mark NAs to 0
df2 <- df %>% select(publication_time, group, fraction) 
df2 <- unique(df2)
df2 <- df2 %>% spread(publication_time, fraction, fill = 0)
df2 <- df2 %>% gather(publication_time, fraction, -group)
df2$publication_time <- as.numeric(as.character(df2$publication_time))

p2 <- ggplot(df2, aes(y = fraction, x = publication_time, fill = group)) + 
       geom_bar(stat = "identity", position = "dodge", color = "black") +
       scale_fill_manual(values = c("black", "darkgray")) +
       ylab("Fraction of total documents (%)")  + 
       xlab("Publication time") +
	     ggtitle("Query relative to all docs") 
       # guides(fill = "none")
if (!selected.place == "All") {
  p2 <- p2 + scale_fill_manual("Place", 
                      values = c("black", "darkgray"), 
                      labels = c(selected.place, "All"))

}


grid.arrange(p1, p2, nrow = 1)

## ----paper, echo=FALSE, message=FALSE, warning=FALSE, echo=FALSE, cache=FALSE, fig.width=15, fig.height=7----
# If selected place is given, then show
# both the selected and all places
myfield <- "paper"
df1 <- NULL
if (!params$place == "All") {
  df1 <- df0.allplaces
}

# Standard timeline
# If place selection is applied then show both the
# selected place and total data
p1 <- plot_timeline(df0, x = "publication_decade", y = myfield,
        nmin = 0, mode = "absolute") +
        ylab("Paper (sheets)") +
	ggtitle("Total paper consumption timeline ()") 
#	guides(fill = "none")	

if (!is.null(df1)) {
  p1 <- p1 + scale_fill_manual("Place", 
                      values = c("black", "darkgray"), 
                      labels = c(selected.place, "All"))
}
p1 <- p1 + scale_y_log10()

# Compare the selected field in between the two data sets
df <- timeline_relative(df0, df.preprocessed, myfield)
df$group <- rep(selected.place, nrow(df))
if (!selected.place == "All") {
  df.allplaces <- timeline_relative(df0.allplaces, df.preprocessed.allplaces, myfield)
  df.allplaces$group <- rep("All", nrow(df.allplaces))
  df <- bind_rows(df, df.allplaces)
}
df$group <- factor(df$group)


# Mark NAs to 0
df2 <- df %>% select(publication_time, group, fraction) 
df2 <- unique(df2)
df2 <- df2 %>% spread(publication_time, fraction, fill = 0)
df2 <- df2 %>% gather(publication_time, fraction, -group)
df2$publication_time <- as.numeric(as.character(df2$publication_time))


p2 <- ggplot(df2, aes(y = fraction, x = publication_time, fill = group)) + 
       geom_bar(stat = "identity", position = "dodge", color = "black") +
       scale_fill_manual(values = c("black", "darkgray")) +
       ylab("Fraction of total documents (%)")  + 
       xlab("Publication time") +
	     ggtitle("Query relative to all docs") 
       #guides(fill = "none")

if (!selected.place == "All") {
  p2 <- p2 + scale_fill_manual("Place", 
                      values = c("black", "darkgray"), 
                      labels = c(selected.place, "All"))

}

grid.arrange(p1, p2, nrow = 1)

## ----bookvspamphlets, echo=FALSE, message=FALSE, warning=FALSE, echo=FALSE, fig.width=10, fig.height=7----
if (params$document.type == "All") {
  df <- df0
  df2 <- df %>% group_by(publication_year, document_type) %>%
              summarize(paper = sum(paper, na.rm = TRUE), n = n()) %>%
	      filter(!is.na(document_type))

  p <- ggplot(df2, aes(x = publication_year, y = paper, group = document_type, color = document_type))
  p <- p + geom_point() + scale_y_log10() 
  p <- p + geom_smooth(method = "loess", span = 0.1)
  p <- p + xlab("Year")
  p <- p + ylab("Paper (sheets)")
  print(p)
} 

## ----topauthors, echo=FALSE, message=FALSE, warning=FALSE, fig.width=20, fig.height=5----

df <- df0
field <- "author"

p1 <- p2 <- p3 <- NULL

p1 <- top_plot(df, field, ntop) +
     		  ggtitle("Title count") +
		  ylab("Title count (n)") 

# Use unnormalized frequency for now
df$hits <-  unlist(custom.ids[match(df$id, custom.ids$id), "freq"], use.names = F) 
df$names <- df[[field]]
dfs.total <- df %>% group_by(names) %>%
              filter(!is.na(names)) %>%
	      summarise(count = sum(hits, na.rm = T), n = n()) %>%
	      mutate(hits.per.edition = count/n)

# Limit title length
dfs.total$names <- substr(as.character(dfs.total$names), 1, nchar)

# Select top-N
dfs <- dfs.total %>% arrange(desc(count)) %>% head(ntop) 
dfs$names <- droplevels(factor(dfs$names, levels = rev(dfs$names)))

theme_set(theme_bw(15))  
p <- ggplot(dfs, aes(x = names, y = count))
  p <- p + geom_bar(stat = "identity")
  p <- p + coord_flip()
  v <- 10^(1:max(na.omit(round(log10(max(dfs$count))))))
  p <- p + scale_y_log10(breaks = v, labels = v)
  #p <- p + scale_y_log10(breaks = v, labels = v)    
  p <- p + ylab("Term occurrences (n)") + xlab("")
  p <- p + ggtitle("Total hits")
  p1 <- p

p <- ggplot(dfs, aes(x = names, y = hits.per.edition))
  p <- p + geom_bar(stat = "identity")
  p <- p + coord_flip()
  v <- 10^(1:max(na.omit(round(log10(max(dfs$hits.per.edition))))))
  p <- p + scale_y_log10(breaks = v, labels = v)
  p <- p + ylab("Hits per edition (n)") + xlab("")
  p <- p + ggtitle("Hits/edition")
  p2 <- p

# Select top-N
dfs2 <- dfs.total %>% arrange(desc(hits.per.edition)) %>% head(ntop) 
dfs2$names <- droplevels(factor(dfs2$names, levels = rev(dfs2$names)))
p <- ggplot(dfs2, aes(x = names, y = hits.per.edition))
  p <- p + geom_bar(stat = "identity")
  p <- p + coord_flip()
  v <- 10^(1:max(na.omit(round(log10(max(dfs$hits.per.edition))))))
  p <- p + scale_y_log10(breaks = v, labels = v)
  p <- p + ylab("Hits per edition (n)") + xlab("")
  p <- p + ggtitle("Hits/edition")
  p3 <- p

grid.arrange(p1, p2, p3, nrow = 1)

## ----topauthorstimeline, fig.height=4, fig.width=10, echo=FALSE----------
df <- df0
theme_set(theme_bw(20))
top.authors <- names(top(df, field = "author", n = 10))
dfs <- df %>% filter(author %in% top.authors) %>%
     	 group_by(author, publication_time) %>%
     	 tally() %>%
     	 arrange(publication_time)
v <- seq(min(dfs$publication_time), max(dfs$publication_time), 20)
p <- ggplot(dfs, aes(x = publication_time, y = n, fill = author)) +
       geom_bar(stat = "identity", position = "stack", color = "black") +
       xlab("Publication time") +
       ylab("Title count (n)") +
       scale_fill_grey() +
       scale_x_continuous(breaks = v, labels = v) +
       guides(fill = guide_legend("Author", reverse = TRUE)) 
       #ggtitle("Title count timeline for the top authors")
print(p)

## ----topplaces, echo=FALSE, message=FALSE, warning=FALSE, fig.width=12, fig.height=5----
df <- df0
p <- NULL
v <- 10^(1:max(na.omit(round(log10(max(table(df$publication_place)))))))
p1 <- top_plot(df, "publication_place", ntop) +
     		  ggtitle(paste("Title count")) +
		  ylab("Title count (n)") +
  		  scale_y_log10(breaks = v, labels = v)    		  


field <- "publication_place"
df$names <- df[[field]]
df$hits <-  unlist(custom.ids[match(df$id, custom.ids$id), "freq"], use.names = F)

# Title counts
dfs <- df %>% group_by(names) %>%
              filter(!is.na(names)) %>% 
              summarise(n = n(), hits = sum(hits, na.rm = T))

p2 <- ggplot(dfs, aes(x = n, y = hits, label = names)) +
       geom_text() + geom_smooth(method = "lm") +
       scale_x_log10() + scale_y_log10() +
       xlab("Title count") + ylab("Query hits") +
       ggtitle("Comparison of title count vs. query hits")

grid.arrange(p1, p2, nrow = 1)

## ----toptitles, echo=FALSE, message=FALSE, warning=FALSE, fig.width=12, fig.height=5----
df <- df0
# Limit title length
df$title <- substr(as.character(df$title), 1, nchar)
p <- NULL
v <- 10^(1:max(na.omit(round(log10(max(table(df$title)))))))
p1 <- top_plot(df, "title", ntop) +
     		  ggtitle(paste("Title count")) +
		  ylab("Title count (n)") +
  		  scale_y_log10(breaks = v, labels = v)    		  

print(p1)

## ----toptitles2, echo=FALSE, message=FALSE, warning=FALSE, fig.width=20, fig.height=5----
df <- df0
v <- 10^(1:max(na.omit(round(log10(max(table(df$title)))))))

# Use unnormalized frequency for now
field <- "title"
df$hits <-  unlist(custom.ids[match(df$id, custom.ids$id), "freq"], use.names = F)
df$names <- df[[field]]

dfs.total <- df %>% group_by(names) %>%
              filter(!is.na(names)) %>% 
              summarise(n = n(), # number of editions
	                count = sum(hits, na.rm = T)) %>% # number of hits
	      mutate(hits.per.edition = count/n)

# Limit title length
dfs.total$names <- substr(as.character(dfs.total$names), 1, nchar)

# Select top-N
dfs <- dfs.total %>% arrange(desc(count)) %>% head(ntop) 

# Retrieve document length from the ID info
dfs$document_length <- custom.ids[match(df$id[match(dfs$names, df$title)], custom.ids$id), "length"]
dfs$names <- droplevels(factor(dfs$names, levels = rev(dfs$names)))

theme_set(theme_bw(15))  

p <- ggplot(dfs, aes(x = names, y = count))
  p <- p + geom_bar(stat = "identity")
  p <- p + coord_flip()
  v <- 10^(1:max(na.omit(round(log10(max(dfs$count))))))
  p <- p + scale_y_log10(breaks = v, labels = v)
  #p <- p + scale_y_log10(breaks = v, labels = v)    
  p <- p + ylab("Term occurrences (n)") + xlab("")
  p <- p + ggtitle("Total hits")
  p1 <- p

p <- ggplot(dfs, aes(x = names, y = hits.per.edition))
  p <- p + geom_bar(stat = "identity")
  p <- p + coord_flip()
  v <- 10^(1:max(na.omit(round(log10(max(dfs$hits.per.edition))))))
  p <- p + scale_y_log10(breaks = v, labels = v)
  p <- p + ylab("Hits per edition (n)") + xlab("")
  p <- p + ggtitle("Hits/edition")
  p2 <- p

# Select top-N
dfs.total <- dfs.total %>% arrange(desc(hits.per.edition)) %>% head(ntop) 
dfs.total$names <- droplevels(factor(dfs.total$names, levels = rev(dfs.total$names)))
p <- ggplot(dfs.total, aes(x = names, y = hits.per.edition))
  p <- p + geom_bar(stat = "identity")
  p <- p + coord_flip()
  v <- 10^(1:max(na.omit(round(log10(max(dfs$hits.per.edition))))))
  p <- p + scale_y_log10(breaks = v, labels = v)
  p <- p + ylab("Hits per edition (n)") + xlab("")
  p <- p + ggtitle("Hits/edition")
  p3 <- p

grid.arrange(p1, p2, p3, nrow = 1)

## ----toppublishers, echo=FALSE, message=FALSE, warning=FALSE, fig.width=12, fig.height=5----
df <- df0
field <- "publisher"

p <- NULL
p1 <- top_plot(df, field, ntop, max.char = nchar) +
     		  ggtitle("Title count") +
		  ylab("Title count (n)") 


# Use unnormalized frequency for now
df$hits <-  unlist(custom.ids[match(df$id, custom.ids$id), "freq"], use.names = F)
df$names <- df[[field]]
dfs <- df %>% group_by(names) %>%
              filter(!is.na(names)) %>% 
              summarise(count = sum(hits, na.rm = T)) %>%
	      arrange(desc(count)) %>%
	      head(ntop) 

# Limit title length
dfs$names <- substr(as.character(dfs$names), 1, nchar)

  dfs$names <- droplevels(factor(dfs$names, levels = rev(dfs$names)))
  theme_set(theme_bw(15))  
  p <- ggplot(dfs, aes(x = names, y = count))
  p <- p + geom_bar(stat = "identity")
  p <- p + coord_flip()
  p <- p + ylab("Term occurrences (n)") + xlab("")
  p <- p + ggtitle("Query hits")
  p2 <- p

grid.arrange(p1, p2, nrow = 1)

