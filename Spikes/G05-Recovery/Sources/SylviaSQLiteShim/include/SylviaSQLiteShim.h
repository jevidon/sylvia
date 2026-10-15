#ifndef SYLVIA_SQLITE_SHIM_H
#define SYLVIA_SQLITE_SHIM_H

#include <sqlite3.h>

/// Sets SQLITE_DBCONFIG_DEFENSIVE on `db` (1 = on, 0 = off) and returns the value SQLite reports
/// afterwards (1 or 0), or -1 if SQLite refused the call. sqlite3_db_config() is variadic, so Swift
/// cannot call it directly; GRDB 7.11.1 does not expose this option.
int sylvia_sqlite_set_defensive(sqlite3 *db, int on);

/// The connection's current SQLITE_DBCONFIG_DEFENSIVE value (1 or 0), or -1 on error.
int sylvia_sqlite_defensive_state(sqlite3 *db);

#endif
