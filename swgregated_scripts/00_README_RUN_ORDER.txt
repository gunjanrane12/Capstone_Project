CLAIMGUARD 360 / INSURANCE POLICY LIFECYCLE - ARRANGED SOURCE PACKAGE

Purpose
-------
This package preserves every supplied source file in full. Files have been renamed and numbered only to make the project stages/processes easy to understand and present.
No source code was intentionally removed, deduplicated, or rewritten.

Suggested logical order
-----------------------
01  BRONZE raw tables
02  AUDIT error/duplicate/warning tables
03  SILVER typed tables and standard Bronze-to-Silver loads
04  Additional Bronze-to-Silver fraud load
05  Claims SCD Type 2 incremental processing, stream and procedure
06  GOLD dimensions, facts, marts and fraud-risk task
07  Security/RBAC, users, roles and secure-consumption layer
08  Dashboard secure views, KPI views, app-owner grants and validation
09  Fraud network feature
10  Threshold email alert implementation
11  Cortex Analyst notes/details
12  Integrated email-alert + Streamlit deployment add-on (kept intact for completeness)
13  Final Streamlit application source

Important
---------
Some original files contain development/test statements, overlapping definitions, and integrated copies of code that also appear in other files. They are intentionally retained so that no supplied code is lost.
The numeric prefixes describe presentation/deployment stages; they do not guarantee that every file can be executed blindly top-to-bottom in a fresh account without adapting role names, users, warehouses, emails, and environment-specific objects.
