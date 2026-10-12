#include "SylviaSQLiteShim.h"

int sylvia_sqlite_set_defensive(sqlite3 *db, int on) {
    int reported = -1;
    if (sqlite3_db_config(db, SQLITE_DBCONFIG_DEFENSIVE, on, &reported) != SQLITE_OK) {
        return -1;
    }
    return reported;
}

int sylvia_sqlite_defensive_state(sqlite3 *db) {
    // A negative value queries the setting without changing it.
    return sylvia_sqlite_set_defensive(db, -1);
}
