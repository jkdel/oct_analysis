#' Custom PCA plotting function
#'
#' @param dataset Data frame or numeric matrix.
#' @param scaling Should the data be scaled?
#' @param axes Principal components to plot.
#' @param plot Actually plot the result or suppress output.
#' @param link Optional vector indicating  non-independent points (e.g., from the same
#'   individuals) which should be connected on the PCA plot.
#' @param annotations Optional character vector naming the points.
#' @param group Optional grouping variable.
#' @param ellipse Indicate the confidence ellipse around groups.
#' @param ellipse_prob Confidence interval of said ellipses.
#' @return An invisible `ggplot()`.
#' @import ggplot2
#' @importFrom rlang .data
#' @export
mpca <- function(dataset, scaling=T, axes=1:2, plot=T, link,
                 annotations, group, ellipse=!missing(group),
                 ellipse_prob = 0.68, group2) {
  if (is.function(scaling)) {
    dataset <- scaling(dataset)
    pca <- stats::prcomp(dataset, scale. = FALSE)
  } else if (is.logical(scaling)) {
    pca <- stats::prcomp(dataset, scale. = scaling)
  } else {
    stop("`scaling` appears to be neither logical nor a function.",
         call. = F)
  }
  perc <- round(pca$sdev[axes]^2 * 100/sum(pca$sdev^2))
  ppca <- stats::predict(pca)
  cols <- colnames(ppca)[axes]
  ppca <- stats::setNames(as.data.frame(ppca[, axes]), c("x", "y"))
  g <- ggplot() +
    coord_equal() +
    labs(x = paste0(cols[[1]], " (", perc[[1]], "%)"),
         y = paste0(cols[[2]], " (", perc[[2]], "%)"),
         color = deparse(substitute(group)))
  if (!missing(group)) {
    ppca$gp <- factor(group)
      if (!missing(group2)) {
        ppca$gp2 <- factor(group2)
        g <- g + geom_point(data = ppca, aes(.data$x, .data$y, color = .data$gp,
                                             shape = .data$gp2), size=2)
      } else {
        g <- g + geom_point(data = ppca, aes(.data$x, .data$y, color = .data$gp))
      }
  }
  else g <- g + geom_point(data = ppca, aes(.data$x, .data$y))
  if (!missing(link)) {
    ppca$link <- link
    if (!missing(group)) sppca <- group_by(ppca, gp, link)
    else sppca <- group_by(ppca, link)
    sppca <- summarise(sppca,xend=last(x),yend=last(y),
                       x=first(x),y=first(y))
    if (!missing(group)) g <- g +
      geom_segment(data=sppca, aes(x=x, y=y, xend=xend, yend=yend, color=gp))
    else g <- g +
      geom_segment(data=sppca, aes(x=x, y=y, xend=xend, yend=yend))
  }
  if (ellipse && length(unique(ppca$gp)) > 1) {
    theta <- c(seq(-pi, pi, length = 50), seq(pi, -pi, length = 50))
    circle <- cbind(cos(theta), sin(theta))
    spl <- split(ppca[, 1:2], ppca$gp)
    spl <- spl[!sapply(spl, \(x) nrow(x) <= 2)]
    ell <- do.call(rbind.data.frame, lapply(spl, function(x) {
      sigma <- stats::var(x)
      mu <- sapply(x, base::mean)
      ed <- base::sqrt(stats::qchisq(ellipse_prob, df = 2))
      data.frame(sweep(circle %*% chol(sigma) * ed, 2, mu,FUN = "+"))}))
    names(ell)[1:2] <- c("x", "y")
    ell$gp <- factor(rep(names(spl), each = 100), levels(ppca$gp))
    g <- g +
      geom_path(data = ell, aes(.data$x, .data$y,
                                color = .data$gp, group = .data$gp))
  }
  if (!missing(annotations)) {
    ppca$annot <- annotations
    g <- g + geom_text(data = ppca,
                       aes(.data$x, .data$y, label = .data$annot),
                       hjust = 0, nudge_x = 0.05)
  }
  if (plot) print(g)
  invisible(g)
}

#' Find a specified distance measure between pairs of rows of a data matrix.
#'
#' @param dataset Data frame or numeric matrix.
#' @param id Name of the variable identifying the pairs (i.e., `table(dataset$id)` should
#'   give 2 for every id).
#' @param within Name of the variable identifying the rows within one pair (i.e.,
#'   `with(dataset, table(id, within))` should give 1 in every cell)
#' @param scale Would you like to scale the data prior to distance calculation?
#' @param method Method argument passed to the `dist` function. Defaults to `euclidean`.
#' @return A vector of distances.
#' @export
finddists <- function(dataset, id, within, scale=T, method="euclidean") {
  dataset <- as.data.frame(droplevels(dataset))
  if (!all(table(dataset[[id]], dataset[[within]])==1))
    stop("The provided dataset does not consists strictly of pairs of data. ",
         "Try tabulating the dataset by the id and within variables to find the error.")
  dataset <- dataset[order(dataset[[id]], dataset[[within]]),]
  rownames(dataset) <- paste(dataset[[id]], dataset[[within]], sep = "_")
  dataset <- dataset[,!colnames(dataset) %in% c(id, within)]
  dists <- as.matrix(dist(scale(dataset, center = scale, scale = scale), method = method))
  setNames(diag(dists[(1:(nrow(dataset)/2))*2, (1:(nrow(dataset)/2))*2-1]),
           sub("_.+$","",rownames(dists)[(1:(nrow(dataset)/2))*2]))
}

#' Match the rows of a `data.frame` in pairs based on (almost) all its variables.
#'
#' @param dataset Data frame or numeric matrix containing only the columns to consider
#'   for matching the rows (individuals) as well as an id and treatment column whose names
#'   can be specified via the other arguments.
#' @param id Name of the variable identifying the individuals. The id of each row should
#'   be unique.
#' @param treatment Name of the variable identifying the treatment variable upon which to
#'   match (i.e., differs between the groups to match), it should have only two possible
#'   values.
#' @param control String used to identify the control group in the `treatment` variable.
#' @param check If `TRUE` a `data.frame` displaying the matches side by side is outputed,
#'   otherwise the result `data.frame` (input dataset containing only the matched
#'   individuals with an additional match identifier `pair`) is outputed.
#' @return Result `data.frame` containing all matching variables as well as a match
#'   identifier, with all unmatched rows removed.
#' @import dplyr
#' @importFrom tibble rownames_to_column
#' @export
match_patients <- function(dataset, id="id", treatment="treatment", control="control", check=F) {
  dat <- base::as.data.frame(dataset)
  rownames(dat) <- dat[[id]]
  dat[[id]] <- NULL
  treat <- base::as.character(base::unique(dat[[treatment]][dat[[treatment]]!=control]))
  dat$treatment <- base::ifelse(dat[[treatment]]==control,0,1)
  dat[[treatment]] <- NULL
  tm <- optmatch::pairmatch(treatment ~ ., data = dat)
  res <- base::cbind(dat, pair=tm) %>%
    filter(!is.na(pair)) %>%
    rownames_to_column("id") %>%
    group_by(pair) %>%
    mutate(pair = lag(id),
           pair = base::ifelse(base::is.na(pair),
                               base::paste(lead(id),id,sep="-"),
                               base::paste(id,pair,sep="-"))) %>%
    as.data.frame()
  colnames(res)[colnames(res)=="id"] <- id
  res$treatment <- base::ifelse(res$treatment==0,control,treat)
  colnames(res)[colnames(res)=="treatment"] <- treatment
  if (check) {
    comp_values <- function(vals) {
      if (is.factor(vals)) vals <- as.character(vals)
      if (is.character(vals)) return(all.equal(vals[1], vals[-1]))
      else if (is.numeric(vals)) diff(vals)
    }
    sum_values <- function(vals) {
      if (is.logical(vals)) {
        if (all(vals)) base::message("- Within matched pairs, all values of ",substitute(vals)," were equal.")
        else base::message("- Some values of ",substitute(vals)," could not be matched within pairs.")
      } else if (is.numeric(vals)) {
        base::message("- The values within ",substitute(vals)," had a mean absolute difference of ",mean(abs(vals))," and a range of ",paste(range(vals),collapse=" to "),".")
      }
    }
    left_join(res %>% filter(.data[[treatment]] != control),
              res %>% filter(.data[[treatment]] == control),
              by = "pair") %>%
      base::as.data.frame() %>%
      base::print.data.frame()
    matching_cols <- colnames(dat)[!colnames(dat) %in% c("treatment","id")]
    res %>%
      group_by(pair) %>%
      summarise(across(!!matching_cols, comp_values)) %>%
      summarise(across(!!matching_cols, sum_values))
    invisible(res)
  }
  return(res)
}

# eye <- data.frame(
#   start = c(0,rep(seq(0.25*pi, 2.25 * pi, length.out = 5)[-5],2)),
#   end = c(2*pi,rep(seq(0.25*pi, 2.25 * pi, length.out = 5)[-1],2)),
#   r0 = c(0,rep(1,4),rep(2,4)),
#   r = c(1,rep(2,4),rep(3,4)),
#   x.center = c(0, 1.5, 0, -1.5, 0, 2.5, 0, -2.5, 0),
#   y.center = c(0, 0, -1.5, 0, 1.5, 0, -2.5, 0, 2.5),
#   segment=factor(c("C0","N1","I1","T1","S1","N2","I2","T2","S2"),
#                  levels=c("C0","N1","I1","T1","S1","N2","I2","T2","S2"))
# )
eye <- data.frame(
  start = c(0,rep(seq(0.25*pi, 2.25 * pi, length.out = 5)[-5],2)),
  end = c(2*pi,rep(seq(0.25*pi, 2.25 * pi, length.out = 5)[-1],2)),
  r0 = c(0,rep(1,4),rep(3,4)),
  r = c(1,rep(3,4),rep(6,4)),
  x.center = c(0, 2, 0, -2, 0, 4.5, 0, -4.5, 0),
  y.center = c(0, 0, -2, 0, 2, 0, -4.5, 0, 4.5),
  segment=factor(c("C0","N1","I1","T1","S1","N2","I2","T2","S2"),
                 levels=c("C0","N1","I1","T1","S1","N2","I2","T2","S2"))
)
eye_legend <- ggplot(eye, aes(x0 = 0, y0 = 0, r0 = r0, r = r, start = start, end = end,
                label=segment)) +
  ggforce::geom_arc_bar(aes(color=segment!="C0"), fill="white", show.legend = F, size=.1) +
  scale_color_manual(values = c("FALSE"="transparent", "TRUE"="black")) +
  geom_text(aes(x=x.center, y=y.center), color="black", size=2.2) +
  coord_fixed() +
  theme_void()

pvals_by_layer <- function(dat) {
  message("CAVE: filling scale limits are hard-coded! Those may need to be adjusted!")
  dat %>%
    left_join(eye) %>%
    rbind(data.frame(layer="LEGEND",
                     segment=unique(dat$segment),
                     data=NA, fit=NA, Coefficient=NA, SE=NA,
                     CI=NA, CI_low=NA, CI_high=NA, t=NA,
                     df_error=NA, p=NA, adj.p=NA, sig.p=F) %>%
            left_join(eye)) %>%
    mutate(color_l = ifelse(segment!="C0"&layer=="LEGEND", "black", "transparent"),
           color_t = ifelse(layer=="LEGEND", "black", "transparent")) %>%
    ggplot(aes(x0 = 0, y0 = 0, r0 = r0, r = r, start = start, end = end,
               fill = Coefficient, label=ifelse(sig.p, "*", NA))) +
    ggforce::geom_arc_bar(aes(color=color_l), size=.1) +
    geom_text(aes(x=x.center, y=y.center, label=segment, color=color_t), size=2.8) +
    scale_color_identity() +
    geom_text(aes(x = x.center, y = y.center), hjust=.5, vjust=.75,
              color="red", fontface="bold", size=6) +
    facet_wrap(.~layer, ncol = 4,
               labeller = as_labeller(\(x) sub("LEGEND","",sub("_","/",x)))) +
    viridis::scale_fill_viridis(na.value="white", limits=c(-155,32), labels=signs::signs_format()) +
    theme_void() +
    coord_fixed() +
    guides(fill=guide_colorbar(title="Mean difference in thickness to control (µm)",
                               title.position = "top",
                               title.hjust = 0.5,
                               barwidth = 16)) +
    theme(axis.text=element_blank(),
          axis.title=element_blank(),
          axis.ticks=element_blank(),
          legend.position = "bottom",
          legend.justification = "center")
}
