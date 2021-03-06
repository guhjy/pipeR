eval_with <- function(expr, enclos, value, symbol = ".") {
  lambda_env <- new.env(FALSE, enclos, 1L)
  lambda_env[[symbol]] <- value
  lockEnvironment(lambda_env, bindings = FALSE)
  eval_envir <- new.env(parent = lambda_env)
  res <- withVisible(eval(expr, eval_envir))
  list2env(as.list.environment(eval_envir), enclos)
  if (res$visible) res$value else invisible(res$value)
}

# pipe to first argument
# x : object
# fun : the function name or call
# envir : environment for evaluation
pipe_first <- function(x, fun, envir) {
  fun <- setclass(fun, "list")

  ## insert x as the first argument to fun
  eval_with(as.call(c(.subset(fun, 1L), quote(.), .subset(fun, -1L))), envir, x)
}

# pipe to dot
# . : object
# expr : expression
# envir : environment for evaluation
pipe_dot <- function(x, expr, envir) {
  eval_with(expr, envir, x)
}

eval_formula <- function(x, expr, envir, side_effect) {
  if (length(expr) == 3L) {
    # (symbol ~ expr)
    lhs <- .subset2(expr, 2L)
    rhs <- .subset2(expr, 3L)
    if (is.side_effect(lhs)) {
      # ~ expr: side effect
      value <- eval_lambda(x, .subset2(lhs, 2L), rhs, envir)
      return(if (side_effect) x else value)
    } else {
      # expr: lambda piping
      return(eval_lambda(x, lhs, rhs, envir))
    }
  } else {
    expr <- .subset2(expr, 2L)
    if (is.symbol(expr)) {
      # ~ symbol: assign
      value <- envir[[as.character(expr)]] <- x
    } else {
      # ~ expr: side effect
      value <- pipe_dot(x, expr, envir)
    }
    return(if (side_effect) x else value)
  }
}

eval_question <- function(x, expr, envir) {
  if (length(expr) == 2L) {
    expr <- .subset2(expr, 2L)
    value <- pipe_lambda(x, expr, envir)
    cat("? ")
    print(expr)
  } else if (length(expr) == 3L && is.character(.subset2(expr, 2L))) {
    value <- pipe_lambda(x, .subset2(expr, 3L), envir)
    cat("?", .subset2(expr, 2L), "\n")
  } else {
    stop("Invalid question expression", call. = FALSE)
  }
  print(value)
  x
}

eval_equal <- function(x, expr, envir, side_effect) {
  lhs <- .subset2(expr, 2L)
  rhs <- .subset2(expr, 3L)
  op <- quote(`<-`)
  value <- pipe_lambda(x, rhs, envir)
  if (is.side_effect(lhs)) {
    call <- as.call(list(op, .subset2(lhs, 2L), value))
    value <- eval(call, envir)
    return(if (side_effect) x else value)
  } else {
    call <- as.call(list(op, lhs, value))
    return(eval(call, envir))
  }
}

eval_assign <- function(x, expr, envir, op, side_effect) {
  lhs <- .subset2(expr, 2L)
  rhs <- .subset2(expr, 3L)
  op <- as.symbol(op)
  value <- pipe_lambda(x, rhs, envir, FALSE)
  if (is.side_effect(lhs)) {
    # ~ x <- expr
    call <- as.call(list(op, .subset2(lhs, 2L), value))
    value <- eval(call, envir)
    return(if (side_effect) x else value)
  } else if (is.side_effect(rhs)) {
    call <- as.call(list(op, lhs, value))
    value <- eval(call, envir)
    return(if (side_effect) x else value)
  } else {
    call <- as.call(list(op, lhs, value))
    return(eval(call, envir))
  }
}

# evaluate lambda expression
# x : object
# symbol : symbol part
# expr : expression part
# envir : environment for evaluation
eval_lambda <- function(x, symbol, expr, envir) {
  if (!is.symbol(symbol))
    stop("Invalid symbol \"", deparse(symbol),
      "\" in lambda expression", call. = FALSE)
  eval_with(expr, envir, x, as.character(symbol))
}

# pipe by lambda expression
# x : object
# expr : lambda expression
# envir : environment for evaluation
# side_effect: TRUE to return x; FALSE to return value of expr
pipe_lambda <- function(x, expr, envir, side_effect = TRUE) {
  if (is.symbol(expr) || is.function(expr) || length(.subset2(expr, 1L)) > 1L)
    return(pipe_dot(x, expr, envir))
  pipe_symbol(x, expr, envir, side_effect, pipe_dot)
}

pipe_symbol <- function(x, expr, envir, side_effect, default) {
  switch(.subset2(as.character(expr), 1L),
    "~" = eval_formula(x, expr, envir, side_effect),
    "?" = eval_question(x, expr, envir),
    "=" = eval_equal(x, expr, envir, side_effect),
    "<-" = eval_assign(x, expr, envir, "<-", side_effect),
    "<<-" = eval_assign(x, expr, envir, "<<-", side_effect),
    default(x, expr, envir))
}

pipe_fun <- function(x, expr, envir) {
  if (is.symbol(expr))
    # ( symbol ): extract element
    getElement(x, as.character(expr))
  else
    # ( call ): pipe by lambda expression
    pipe_lambda(x, expr, envir)
}

# pipe function that determines the piping mechanism for the expression
# x : object
# expr : function name, call, or enclosed expression
pipe_op <- function(x, expr) {
  x # avoid lazy evaluation of x
  expr <- substitute(expr)
  envir <- parent.frame()
  switch(class(expr),
    "NULL" = NULL,
    "character" = {cat(expr, "\n"); x},
    "{" = pipe_dot(x, expr, envir),
    "(" = pipe_fun(x, .subset2(expr, 2L), envir),
    pipe_symbol(x, expr, envir, TRUE, pipe_first))
}
