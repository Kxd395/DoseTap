# CRUD and restore acceptance

Status: Current acceptance boundary

DOSETAP-39 owns whole-project deletion, backup, and content-equal restore acceptance. Per-session mutations must preserve unrelated UUIDs. The work/wake schedule is configuration shared across sessions: session deletion retains it and Clear All Data removes it. It is included in whole-database copies; partial CSV exports are not full backups. Private device inventories remain local.
