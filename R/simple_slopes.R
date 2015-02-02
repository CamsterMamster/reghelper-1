#' Simple slopes of interaction.
#' 
#' \code{simple_slopes} is a generic function for calculating the simple effects
#' of an interaction in a regression model.
#' 
#' @param model A fitted linear model of type 'lm'.
#' @param ... Additional arguments to be passed to the particular method for the
#'   given model.
#' @return The form of the value returned by \code{simple_slopes} depends on the
#'   class of its argument. See the documentation of the particular methods for
#'   details of what is produced by that method.
#' @seealso \code{\link{simple_slopes.lm}}
#' @examples TODO: Need to complete.
#' @export
simple_slopes <- function(model, ...) UseMethod('simple_slopes')


#' Simple slopes of interaction.
#' 
#' \code{simple_slopes.lm} calculates all the simple effects of an interaction
#' in a regression model.
#' 
#' If the model includes interactions at different levels (e.g., three two-way
#' interactions and one three-way interaction), the function will test the
#' simple effects of the highest-order interaction. If there are multiple
#' interactions in the highest order, it will test the first one in the model.
#' If you wish to test simple effects for a different interaction, simply switch
#' the order in the formula.
#' 
#' By default, this function will provide slopes at -1SD, the mean, and +1SD for
#' continuous variables, and at each level of categorical variables. This can be
#' overridden with the \code{levels} parameter.
#' 
#' @param model A fitted linear model of type 'lm' with at least one interaction
#'   term.
#' @param levels A list with arguments names corresponding to some or all of the
#'   variables in the model. Each list element should be a vector with the names
#'   of factor levels (for categorical variables) or numeric points (for
#'   continuous variables) at which to test that variable. \strong{Note:} If you
#'   do not include 0 as one of these levels, the function will not test the
#'   simple effects for that variable.
#' @return A data frame with a row for each simple effect. The first few columns
#    identify the level at which each variable in your model was set for that
#    test. A 0 value in a particular column indicates that this was the variable
#    being tested. After columns for each variable, the data frame has columns
#    for the slope of the 0 variable, the standard error, t-value, p-value, and
#    degrees of freedom for the model.
#' @examples TODO: Need to complete.
#' @export
simple_slopes.lm <- function(model, levels=NULL) {
    mdata <- model$model
    
    int_term <- which.max(attr(terms(model), 'order'))
        # get location of highest interaction term
    int_vars <- which(attr(terms(model), 'factors')[, int_term] == 1)
        # get location of variables in the interaction
    
    # get points at which to test each variable
    factors <- .set_factors(model, int_vars, levels)
    
    # create grid of all tests to be done
    grids <- .create_grids(mdata, factors)
    
    form <- format(formula(model))
    
    template <- grids[[1]]
    models <- grids[[2]]
    models[, c('Test Estimate', 'Std. Error',
               't value', 'Pr(>|t|)', 'df')] <- NA
    est_count <- 1
    
    for (i in 1:nrow(template)) {
        new_form <- form
        #test_var <- names(template)[suppressWarnings(which(template[i, ] == 'sstest'))]
        test_var_name <- names(template)[which(template[i, ] == 'sstest')]
        test_var <- mdata[[test_var_name]]
        
        for (j in 1:ncol(template)) {
            vname <- colnames(template)[j]
            if (vname != test_var_name) {
                if (is.factor(mdata[[vname]])) {
                    # for factors, we set the contrast, with reference group as
                    # the one for that test
                    contrasts(mdata[[vname]]) <- contr.treatment(
                        levels(mdata[[vname]]),
                        base=which(levels(mdata[[vname]]) == template[i, j])
                    )
                } else {
                    # for continuous, we replace the name of the variable in the
                    # formula to shift the 0 point
                    new_var <- paste0('I(', vname, ' - ', template[i, j], ')')
                    new_form <- gsub(vname, new_var, new_form)
                }
            }
        }
        new_model <- lm(new_form, mdata)
        
        if (is.factor(test_var)) {
            contr <- contrasts(test_var)
            dummy_names <- paste0(test_var_name, colnames(contr))
            
            estimates <- as.data.frame(
                summary(new_model)$coefficients[dummy_names, ])
            
            # when only one contrast, the coefficients will be a vector, not a
            # matrix, so estimates ends up transposed
            if (ncol(contr) < 2) {
                estimates <- as.data.frame(t(estimates))
                rownames(estimates) <- 1
            }
            
            estimates$df <- new_model$df.residual
            
            for (est in 1:nrow(estimates)) {
                models[est_count, (ncol(models)-4):ncol(models)] <- estimates[est, ]
                est_count <- est_count + 1
            }
        } else {
            models[est_count, (ncol(models)-4):ncol(models)] <- c(
                summary(new_model)$coefficients[int_vars[test_var_name], ],
                new_model$df.residual
            )
            est_count <- est_count + 1
        }
    }
    return(models)
}


#' Find points to test variables.
#' 
#' Helper function calculates points at which to test slopes of a variable. For
#' categorical variables, this includes all its levels. For continuous
#' variables, this is -1 SD, the mean, and +1 SD.
#' 
#' @param model The linear model being tested.
#' @param int_vars The variables involved in the interaction being tested.
#' @param user_levels Any user-specified levels to be used instead of the
#'   defaults.
#' @return A list with all the factor points for each variable in the
#'   interaction.
.set_factors <- function(model, int_vars, user_levels=NULL) {
    factors <- list()
    for (term in names(int_vars)) {
        term_data <- model$model[[term]]
        if (!is.null(user_levels) && term %in% names(user_levels)) {
            # if user specified levels, use those
            factors[[term]] <- user_levels[[term]]
        } else {
            if (attr(terms(model), 'dataClasses')[term] == 'factor') {
                # factors are plotted at all levels (plus 0)
                factors[[term]] <- c('sstest', levels(term_data))
            } else {
                # continuous vars are plotted at -1SD, mean, and +1 SD
                factors[[term]] <- c(
                    'sstest',
                    .offset_point(term_data, -1),
                    .offset_point(term_data, 0),
                    .offset_point(term_data, 1)
                )
            }
        }
    }
    return(factors)
}


#' Create grid of simple slope tests.
#' 
#' Helper function creates a data frame with a list of all simple slope tests to
#' be done.
#' 
#' @param data Data from the linear model being tested.
#' @param factors List of all points to test for each variable in the
#'   interaction.
#' @return A data frame with one line for each simple slope test, indicating
#'   what point each variable is set to in the test.
.create_grids <- function(data, factors) {
    grid <- with(data, expand.grid(factors))
    
    # we only want to use the models that are testing a single variable
    find_tests <- apply(grid, 1, function(x) {
        length(which(suppressWarnings(x == 'sstest'))) == 1
    })
    grid <- grid[find_tests, ]
    
    rownames(grid) <- seq(to=nrow(grid))
    
    # remove factor levels from factor variables
    grid <- as.data.frame(lapply(grid, function(x) {
        as.character(x)
    }), stringsAsFactors=FALSE)
    
    new_grid <- grid
    
    # look for factor variables with more than 2 levels -- they need extra rows
    for (var in names(factors)) {
        variable <- data[[var]]
        if (is.factor(variable) && length(levels(variable)) > 2) {
            find_rows <- which(grid[, var] == 'sstest')
            contr <- contrasts(variable)
            
            adj_find_rows <- find_rows +
                (ncol(contr)-1) * 0:(length(find_rows)-1)
                # adjust find_rows, since we are going to be adding rows in
                # between as we loop through
            
            for (row in 1:length(find_rows)) {
                old_row <- grid[find_rows[row], ]
                new_rows <- as.data.frame(t(sapply(1:ncol(contr), function(x) {
                    old_row
                })))  # kind of hacky way to copy rows
                
                # change rownames to letter subscripts, e.g., '4a', '4b'
                rownames(new_rows) <- paste0(
                    rownames(old_row),
                    letters[1:nrow(new_rows)])
                
                new_grid <- .df_row_splice(
                    new_grid,
                    adj_find_rows[row],
                    num_remove=1,
                    new_rows=new_rows)
            }
        }
    }
    
    return(list(grid, new_grid))
}


# Helper Functions -------------------------------------------------------------

#' Calculate points for testing simple slopes
#' 
#' Helper function calculates point at which to set a variable, based on its
#' mean and standard deviation.
#' 
#' @param var A vector of the variable to test.
#' @param offset_sd The value, in standard deviations, at which you wish to
#'   offset the variable.
#' @param digits Number of decimal places to round value.
#' @return The value of the variable at the offset point. For example, for a
#'   standard normal distribution, an offset point of -1 would return a value of
#'   -1.
.offset_point <- function(var, offset_sd, digits=6) {
    point <- mean(var, na.rm=TRUE) + offset_sd * sd(var, na.rm=TRUE)
    return(round(point, digits))
}


#' Remove and insert columns in data frame
#' 
#' Helper function allows columns to be removed and added at a particular splice
#' point. This function works similar to the Javascript function splice().
#' 
#' @param df The data frame to modify
#' @param splice_point The column at which to make changes. Removed columns will
#'   start with this one, and new columns will be added starting at this column
#'   index.
#' @param num_remove The number of columns to remove.
#' @param new_cols A data frame of new columns to be added.
#' @return A new data frame with the modifications made.
.df_splice <- function(df, splice_point, num_remove=0, new_cols=NULL) {
    old_colnames <- colnames(df)
    
    # remove columns
    if (splice_point > 0 && splice_point <= ncol(df) &&
        num_remove > 0 && (splice_point + num_remove - 1) <= ncol(df)) {
        
        new_df <- as.data.frame(df[,
            -c(splice_point:(splice_point+num_remove-1))])
        
        colnames(new_df) <- old_colnames[
            -c(splice_point:(splice_point+num_remove-1))]
    } else {
        new_df <- df
    }
    
    # add new columns
    if (!is.null(new_cols)) {
        new_cols <- as.data.frame(new_cols)
        
        if (splice_point == 1) {
            new_df2 <- cbind(new_cols, new_df)
        } else {
            new_df2 <- cbind(
                new_df[, 1:(new_splice-1)],
                new_cols,
                new_df[, -c(1:(new_splice-1))])
        }
    } else {
        new_df2 <- new_df
    }
    return(new_df2)
}


.df_row_splice <- function(df, splice_point, num_remove=0, new_rows=NULL,
    reset_rownames=FALSE) {
    old_rownames <- rownames(df)
    
    # remove rows
    if (splice_point > 0 && splice_point <= nrow(df) &&
            num_remove > 0 && (splice_point + num_remove - 1) <= nrow(df)) {
        
        new_df <- as.data.frame(
            df[-c(splice_point:(splice_point+num_remove-1)), ])
    } else {
        new_df <- df
    }
    
    # add new rows
    if (!is.null(new_rows)) {
        new_rows <- as.data.frame(new_rows)
        new_rownames <- rownames(new_df)
        
        if (splice_point == 1) {
            new_df2 <- rbind(new_rows, new_df)
        } else {
            new_df2 <- rbind(
                new_df[1:(splice_point-1), ],
                new_rows,
                new_df[-c(1:(splice_point-1)), ])
        }
        
        if (reset_rownames) {
            rownames(new_df2) <- 1:nrow(new_df2)
        } else {
            # check for rowname conflicts
            if (any(rownames(new_rows) %in% rownames(new_df))) {
                warning('Rownames in new rows conflict with original rownames. Rownames will be reset.')
                rownames(new_df2) <- 1:nrow(new_df2)
            }
        }
    } else {
        new_df2 <- new_df
        if (reset_rownames) {
            rownames(new_df2) <- 1:nrow(new_df2)
        }
    }
    return(new_df2)
}


