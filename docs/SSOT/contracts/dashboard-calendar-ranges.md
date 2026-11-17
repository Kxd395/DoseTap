# Dashboard calendar reporting ranges

Status: Current shared domain contract
Owner: DOSETAP-45

Freeze the evaluation instant and explicit timezone. Use the Gregorian calendar and existing 18:00 treatment-night rollover. The current window ends exclusively at midnight following that treatment date. Fixed 7/14/30/90-day ranges subtract that many civil days. 6M and 1Y subtract six/twelve calendar months from the exclusive end; normal Gregorian month-end clamping applies. The prior window ends at the current start and subtracts the same calendar unit/count. Adjacent windows never overlap. All Time has no lower local-history bound and no prior comparison.

Examples: September 30, 2026 at/after rollover gives 6M April 1–September 30. September 26 gives March 27–September 26. February 28, 2027 gives September 1–February 28. 1Y ending February 29, 2024 gives March 1, 2023–February 29, 2024. Morning evaluation still belongs to the previous treatment date.

Supported bounds are Gregorian AD years 1–9999; reject a window whose generated bounds cross that domain. Strict Gregorian YYYY-MM-DD keys only; reject malformed, impossible and future treatment dates. Filtering preserves every eligible row and its identity; dates remain grouping labels, not unique observations. Phone evaluation uses its current instant; a received iPad report uses its captured instant. Equal instant/timezone/range must give equal membership. Neither range filtering nor a changed timezone rewrites stored timestamps.

Apple Health query length derives from both requested windows plus two boundary days and remains capped at 730 days. Record the requested query interval and as-of instant. Explicitly disclose when this cap omits the beginning of the preceding calendar period; successful querying does not establish complete provider data or permission. All Time is local history with limited provider retrieval. WHOOP remains limited to 30 days. Queries and labels use the same frozen inputs. These ranges do not modify medication timing, alarms, provider sleep calculations or the dosing baseline.
