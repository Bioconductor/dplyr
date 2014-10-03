#' Connect to a sqlite database.
#'
#' Use \code{src_sqlite} to connect to an existing sqlite database,
#' and \code{tbl} to connect to tables within that database.
#' If you are running a local sqliteql database, leave all parameters set as
#' their defaults to connect. If you're connecting to a remote database,
#' ask your database administrator for the values of these variables.
#'
#' @template db-info
#' @param path Path to SQLite database
#' @param create if \code{FALSE}, \code{path} must already exist. If
#'   \code{TRUE}, will create a new SQlite3 database at \code{path}.
#' @param src a sqlite src created with \code{src_sqlite}.
#' @param from Either a string giving the name of table in database, or
#'   \code{\link{sql}} described a derived table or compound join.
#' @param ... Included for compatibility with the generic, but otherwise
#'   ignored.
#' @export
#' @examples
#' \dontrun{
#' # Connection basics ---------------------------------------------------------
#' # To connect to a database first create a src:
#' my_db <- src_sqlite(path = tempfile(), create = TRUE)
#' # Then reference a tbl within that src
#' my_tbl <- tbl(my_db, "my_table")
#' }
#'
#' # Here we'll use the Lahman database: to create your own local copy,
#' # run lahman_sqlite()
#'
#' \donttest{
#' if (require("RSQLite") && has_lahman("sqlite")) {
#' # Methods -------------------------------------------------------------------
#' batting <- tbl(lahman_sqlite(), "Batting")
#' dim(batting)
#' colnames(batting)
#' head(batting)
#'
#' # Data manipulation verbs ---------------------------------------------------
#' filter(batting, yearID > 2005, G > 130)
#' select(batting, playerID:lgID)
#' arrange(batting, playerID, desc(yearID))
#' summarise(batting, G = mean(G), n = n())
#' mutate(batting, rbi2 = 1.0 * R / AB)
#'
#' # note that all operations are lazy: they don't do anything until you
#' # request the data, either by `print()`ing it (which shows the first ten
#' # rows), by looking at the `head()`, or `collect()` the results locally.
#'
#' system.time(recent <- filter(batting, yearID > 2010))
#' system.time(collect(recent))
#'
#' # Group by operations -------------------------------------------------------
#' # To perform operations by group, create a grouped object with group_by
#' players <- group_by(batting, playerID)
#' group_size(players)
#'
#' # sqlite doesn't support windowed functions, which means that only
#' # grouped summaries are really useful:
#' summarise(players, mean_g = mean(G), best_ab = max(AB))
#'
#' # When you group by multiple level, each summarise peels off one level
#' per_year <- group_by(batting, playerID, yearID)
#' stints <- summarise(per_year, stints = max(stint))
#' filter(ungroup(stints), stints > 3)
#' summarise(stints, max(stints))
#'
#' # Joins ---------------------------------------------------------------------
#' player_info <- select(tbl(lahman_sqlite(), "Master"), playerID, birthYear)
#' hof <- select(filter(tbl(lahman_sqlite(), "HallOfFame"), inducted == "Y"),
#'  playerID, votedBy, category)
#'
#' # Match players and their hall of fame data
#' inner_join(player_info, hof)
#' # Keep all players, match hof data where available
#' left_join(player_info, hof)
#' # Find only players in hof
#' semi_join(player_info, hof)
#' # Find players not in hof
#' anti_join(player_info, hof)
#'
#' # Arbitrary SQL -------------------------------------------------------------
#' # You can also provide sql as is, using the sql function:
#' batting2008 <- tbl(lahman_sqlite(),
#'   sql("SELECT * FROM Batting WHERE YearID = 2008"))
#' batting2008
#' }
#' }
src_sqlite <- function(path, create = FALSE) {
  if (!requireNamespace("RSQLite", quietly = TRUE)) {
    stop("RSQLite package required to connect to sqlite db", call. = FALSE)
  }

  if (!create && !file.exists(path)) {
    stop("Path does not exist and create = FALSE", call. = FALSE)
  }

  con <- dbConnect(RSQLite::SQLite(), path)
  load_extension(con)

  info <- dbGetInfo(con)

  src_sql("sqlite", con, path = path, info = info)
}

load_extension <- function(con) {
  if (packageVersion("RSQLite") >= 1) {
    RSQLite::initExtension(con)
    return()
  }

  require("RSQLite")
  if (!require("RSQLite.extfuns")) {
    stop("RSQLite.extfuns package required to effectively use sqlite db",
      call. = FALSE)
  }

  RSQLite.extfuns::init_extensions(con)
}

#' @export
#' @rdname src_sqlite
tbl.src_sqlite <- function(src, from, ...) {
  tbl_sql("sqlite", src = src, from = from, ...)
}

#' @export
src_desc.src_sqlite <- function(x) {
  paste0("sqlite ", x$info$serverVersion, " [", x$path, "]")
}

#' @export
src_translate_env.src_sqlite <- function(x) {
  sql_variant(
    base_scalar,
    sql_translator(.parent = base_agg,
      sd = sql_prefix("stdev")
    )
  )
}

# DBI methods ------------------------------------------------------------------

# Doesn't include temporary tables
#' @export
db_list_tables.SQLiteConnection <- function(con) {
  sql <- "SELECT name FROM
    (SELECT * FROM sqlite_master UNION ALL
     SELECT * FROM sqlite_temp_master)
    WHERE type = 'table' OR type = 'view'
    ORDER BY name"

  dbGetQuery(con, sql)[[1]]
}

# Doesn't return TRUE for temporary tables
#' @export
db_has_table.SQLiteConnection <- function(con, table, ...) {
  table %in% db_list_tables(con)
}

#' @export
db_query_fields.SQLiteConnection <- function(con, sql, ...) {
  rs <- dbSendQuery(con, paste0("SELECT * FROM ", sql))
  on.exit(dbClearResult(rs))

  names(fetch(rs, 0L))
}

# http://sqlite.org/lang_explain.html
#' @export
db_explain.SQLiteConnection <- function(con, sql, ...) {
  exsql <- build_sql("EXPLAIN QUERY PLAN ", sql)
  expl <- dbGetQuery(con, exsql)
  rownames(expl) <- NULL
  out <- capture.output(print(expl))

  paste(out, collapse = "\n")
}

#' @export
db_begin.SQLiteConnection <- function(con, ...) {
  if (packageVersion("RSQLite") < 1) {
    RSQLite::dbBeginTransaction(con)
  } else {
    DBI::dbBegin(con)
  }
}

#' @export
db_insert_into.SQLiteConnection <- function(con, table, values, ...) {
  params <- paste(rep("?", ncol(values)), collapse = ", ")

  sql <- build_sql("INSERT INTO ", table, " VALUES (", sql(params), ")")

  res <- RSQLite::dbSendPreparedQuery(con, sql, bind.data = values)
  DBI::dbClearResult(res)

  TRUE
}
