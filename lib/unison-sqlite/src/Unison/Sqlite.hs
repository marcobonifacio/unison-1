-- | The Unison monorepo interface to SQLite.
--
-- This module provides a high(-er) level interface to SQLite than the @sqlite-simple@ library, which it wraps. Code
-- that interacts with SQLite in this monorepo should use this interface, rather than @sqlite-simple@ or @direct-sqlite@
-- directly.
--
-- Three variants of the main query interface are provided:
--
--   * "Unison.Sqlite.Connection" provides an interface in @IO@, which takes the 'Connection' argument as an explicit
--     argument.
--   * "Unison.Sqlite.Transaction" provides a safer interface that executes queries in transactions, with automatic
--     retries on @SQLITE_BUSY@ due to concurrent writers.
module Unison.Sqlite
  ( -- * Connection management
    Connection,
    withConnection,

    -- * Transaction interface
    Transaction,
    runTransaction,
    runReadOnlyTransaction,
    runWriteTransaction,
    unsafeUnTransaction,
    savepoint,
    unsafeIO,

    -- * Executing queries
    Sql (..),
    sql,
    Sql2,
    sql2,
    Values (..),
    valuesSql,

    -- ** Without results

    -- *** With parameters
    execute,
    execute2,
    executeMany,

    -- *** Without parameters
    executeStatements,
    execute_,

    -- ** With results
    -- $query-naming-convention

    -- *** With parameters
    queryStreamRow,
    queryStreamCol,
    queryListRow,
    queryListRow2,
    queryListCol,
    queryListCol2,
    queryMaybeRow,
    queryMaybeRow2,
    queryMaybeCol,
    queryMaybeCol2,
    queryOneRow,
    queryOneRow2,
    queryOneCol,
    queryOneCol2,
    queryManyListRow,

    -- **** With checks
    queryListRowCheck,
    queryListColCheck,
    queryListColCheck2,
    queryMaybeRowCheck,
    queryMaybeRowCheck2,
    queryMaybeColCheck,
    queryMaybeColCheck2,
    queryOneRowCheck,
    queryOneRowCheck2,
    queryOneColCheck,
    queryOneColCheck2,

    -- *** Without parameters
    queryListRow_,
    queryListCol_,
    queryMaybeRow_,
    queryMaybeCol_,
    queryOneRow_,
    queryOneCol_,

    -- **** With checks
    queryListRowCheck_,
    queryListColCheck_,
    queryMaybeRowCheck_,
    queryMaybeColCheck_,
    queryOneRowCheck_,
    queryOneColCheck_,

    -- * Rows modified
    rowsModified,

    -- * Data version
    DataVersion (..),
    getDataVersion,

    -- * Journal mode
    JournalMode (..),
    trySetJournalMode,

    -- * Vacuum
    vacuum,
    vacuumInto,

    -- * Exceptions
    SomeSqliteException (..),
    isCantOpenException,
    SqliteConnectException,
    SqliteQueryException,
    SqliteExceptionReason,
    SomeSqliteExceptionReason (..),
    ExpectedAtMostOneRowException (..),
    ExpectedExactlyOneRowException (..),
    SetJournalModeException (..),

    -- * Re-exports
    Sqlite.Simple.field,
    (Sqlite.Simple.:.) (..),
    Sqlite.Simple.FromField (fromField),
    Sqlite.Simple.FromRow (fromRow),
    Sqlite.Simple.Only (..),
    Sqlite.Simple.RowParser,
    Sqlite.Simple.SQLData (..),
    Sqlite.Simple.ToField (toField),
    Sqlite.Simple.ToRow (toRow),
  )
where

import Database.SQLite.Simple qualified as Sqlite.Simple
import Database.SQLite.Simple.FromField qualified as Sqlite.Simple
import Database.SQLite.Simple.FromRow qualified as Sqlite.Simple
import Database.SQLite.Simple.ToField qualified as Sqlite.Simple
import Unison.Sqlite.Connection
  ( Connection,
    ExpectedAtMostOneRowException (..),
    ExpectedExactlyOneRowException (..),
    vacuum,
    vacuumInto,
    withConnection,
  )
import Unison.Sqlite.DataVersion (DataVersion (..), getDataVersion)
import Unison.Sqlite.Exception
  ( SomeSqliteException (..),
    SomeSqliteExceptionReason (..),
    SqliteConnectException,
    SqliteExceptionReason,
    SqliteQueryException,
    isCantOpenException,
  )
import Unison.Sqlite.JournalMode (JournalMode (..), SetJournalModeException (..), trySetJournalMode)
import Unison.Sqlite.Sql (Sql (..), sql)
import Unison.Sqlite.Sql2 (Sql2, sql2)
import Unison.Sqlite.Transaction
import Unison.Sqlite.Values (Values (..), valuesSql)

-- $query-naming-convention
--
-- Queries that return results have many different variants.
--
-- Every function name begins with the string @__query__@.
--
--   1. /Row count/. The caller may expect /exactly one/, /zero or one/, or /zero or more/ rows, in which case the
--      function name includes the string @__One__@, @__Maybe__@, or (@__List__@ or @__Stream__@), respectively.
--      Example: @query__List__Row@.
--
--   2. /Row width/. The caller may expect the returned rows may contain /exactly one/ or /more than one/ column, in
--      which case the function name includes the string @__Col__@ or @__Row__@, respectively.
--      Example: @queryOne__Col__@.
--
--   3. /Result checks/. The caller may want to perform additional validation on the returned rows, in which case the
--      function name includes the string @__Check__@.
--      Example: @queryMaybeCol__Check__@.
--
--   4. /Parameter count/. The query may contain /zero/ or /one or more/ parameters. In the former case, the function
--      name includes the string @__\___@.
--      Example: @queryListRow__\___@.
--
-- All together, the full anatomy of a query function is:
--
-- @
-- query(List|Maybe|One)(Row|Col)[Check][_]
-- @
