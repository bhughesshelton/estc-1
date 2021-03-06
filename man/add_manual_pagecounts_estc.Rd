% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/add_manual_pagecounts_estc.R
\name{add_manual_pagecounts_estc}
\alias{add_manual_pagecounts_estc}
\title{Add Manual Page Counts}
\usage{
add_manual_pagecounts_estc(df)
}
\arguments{
\item{df}{Preprocessed data.frame}
}
\value{
data.frame with publication years estimated
}
\description{
Augment the ESTC data with manually insertred page counts.
}
\examples{
\dontrun{df2 <- add_manual_pagecounts_estc(df)}
}
\references{
See citation("estc")
}
\author{
Leo Lahti \email{leo.lahti@iki.fi}
}
\keyword{utilities}
