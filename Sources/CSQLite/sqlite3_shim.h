#ifndef ASV_SQLITE3_SHIM_H
#define ASV_SQLITE3_SHIM_H

// Resolve SQLite from the active platform SDK (macOS) or system include path
// (Linux), while keeping one Swift import name for both builds.
#include <sqlite3.h>

#endif
