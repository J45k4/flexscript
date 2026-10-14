# FlexDB optimized roadmap comparison (2026-10-14)

Five measured runs in this execution, with an excluded warmup and alternating engine order. Times below are median milliseconds; each row compares the same result checksum and operation count. See [benchmark.md](../../benchmark.md) for full target scope.

Native Flexscript vs C -O3 SQLite WAL/FULL/NOMUTEX/64MiB cache. One pinned CPU, fresh file/process per variant/round, alternating engine order, excluded warmup. Seeded logical rows and cross-engine case checksum/operation validation. Read-family repeated SELECTs use one SQLite read transaction, with index creation in its own durable phase; mixed workload reads between durable writes use ordinary statement transactions. FlexDB automatic index versus SQLite explicit B-tree; build phase costs differ. Middle pagination uses the generated predicate_page scan, avoiding the previous full-query-plus-limit intermediate; it is not an indexed cursor. Duplicate integer count queries include a bounded exact-key count memo learned by earlier calls; invalidating writes and rebuild costs are timed separately. Ordered result delivery consumes id,key,text length and nullable value in both engines; SQLite streams rows, FlexDB materializes immutable handles. Warm OS cache; no physical-cold claim. Whole session includes dataset key generation, schema/population, query preparation and close; compilation excluded. Latency samples use forced kernel clocks in both engines with measured empty-clock overhead. Integrity, schema and compaction APIs have different internal implementations. RSS uses /proc/self/status VmHWM after exec, avoiding inherited launcher ru_maxrss; I/O uses whole-worker /proc/self/io storage-byte counters and includes setup/maintenance. Mutation phases construct fresh FlexDB value vectors versus prepared SQLite bindings. Session totals also include the benchmark latency calibration/sorting where present. Each ID tags a related representative variant, not complete checklist coverage; integer rows do not constitute text-key measurements, and reopen-by-ID does not measure mapped equality-index access.

| Scenario | Case | Targets | Operations | FlexDB ms | SQLite ms | Faster (>10% margin) |
| --- | --- | --- | ---: | ---: | ---: | --- |
| read_1k | insert_reused | W01,M02,M04 | 1000 | 5.618 | 5.581 | Similar |
| read_1k | id_sequential | Q01 | 100000 | 3.231 | 18.081 | FlexDB |
| read_1k | id_random | Q01 | 100000 | 3.022 | 21.573 | FlexDB |
| read_1k | id_hot32 | Q01 | 100000 | 2.987 | 17.858 | FlexDB |
| read_1k | id_missing | Q01 | 100000 | 1.125 | 13.157 | FlexDB |
| read_1k | scan_matches_0 | Q06 | 20 | 0.123 | 0.378 | FlexDB |
| read_1k | scan_matches_1 | Q06 | 20 | 0.122 | 0.379 | FlexDB |
| read_1k | scan_matches_10 | Q06 | 20 | 0.122 | 0.384 | FlexDB |
| read_1k | scan_matches_100 | Q06 | 20 | 0.122 | 0.384 | FlexDB |
| read_1k | scan_matches_500 | Q06 | 20 | 0.126 | 0.406 | FlexDB |
| read_1k | scan_matches_1000 | Q06 | 20 | 0.131 | 0.435 | FlexDB |
| read_1k | combined_scan | Q08 | 20 | 0.353 | 0.570 | FlexDB |
| read_1k | null_scan | Q05 | 20 | 0.232 | 0.414 | FlexDB |
| read_1k | learn_integer | A01,A02,A05 | 34 | 0.261 | 5.983 | FlexDB |
| read_1k | integer_hit | Q02,Q04 | 10000 | 1.581 | 2.925 | FlexDB |
| read_1k | integer_miss | Q02,Q04 | 10000 | 0.590 | 1.890 | FlexDB |
| read_1k | integer_materialized | Q04,Q09 | 100 | 0.049 | 0.054 | FlexDB |
| read_1k | offset_page_middle | Q10 | 10 | 0.045 | 0.113 | FlexDB |
| read_1k | aggregate_sum_loop | Q15 | 20 | 0.627 | 0.459 | SQLite |
| read_1k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| read_1k | final_close | S04 | 1000 | 5.557 | 10.204 | FlexDB |
| read_1k | session_total | S05 | 1 | 48.542 | 139.504 | FlexDB |
| read_10k | insert_reused | W01,M02,M04 | 10000 | 10.042 | 9.960 | Similar |
| read_10k | id_sequential | Q01 | 100000 | 3.178 | 18.196 | FlexDB |
| read_10k | id_random | Q01 | 100000 | 3.741 | 25.006 | FlexDB |
| read_10k | id_hot32 | Q01 | 100000 | 2.990 | 18.699 | FlexDB |
| read_10k | id_missing | Q01 | 100000 | 1.124 | 13.878 | FlexDB |
| read_10k | scan_matches_0 | Q06 | 20 | 1.251 | 3.814 | FlexDB |
| read_10k | scan_matches_1 | Q06 | 20 | 1.251 | 3.833 | FlexDB |
| read_10k | scan_matches_100 | Q06 | 20 | 1.268 | 3.849 | FlexDB |
| read_10k | scan_matches_1000 | Q06 | 20 | 1.265 | 3.886 | FlexDB |
| read_10k | scan_matches_5000 | Q06 | 20 | 1.298 | 4.145 | FlexDB |
| read_10k | scan_matches_10000 | Q06 | 20 | 1.348 | 4.422 | FlexDB |
| read_10k | combined_scan | Q08 | 20 | 3.571 | 5.814 | FlexDB |
| read_10k | null_scan | Q05 | 20 | 2.409 | 4.214 | FlexDB |
| read_10k | learn_integer | A01,A02,A05 | 5 | 0.977 | 11.239 | FlexDB |
| read_10k | integer_hit | Q02,Q04 | 10000 | 1.519 | 3.298 | FlexDB |
| read_10k | integer_miss | Q02,Q04 | 10000 | 0.591 | 1.962 | FlexDB |
| read_10k | integer_materialized | Q04,Q09 | 100 | 0.047 | 0.065 | FlexDB |
| read_10k | offset_page_middle | Q10 | 10 | 0.369 | 1.041 | FlexDB |
| read_10k | aggregate_sum_loop | Q15 | 20 | 6.379 | 4.510 | SQLite |
| read_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| read_10k | final_close | S04 | 10000 | 8.806 | 7.266 | SQLite |
| read_10k | session_total | S05 | 1 | 77.388 | 188.376 | FlexDB |
| read_100k | insert_reused | W01,M02,M04 | 100000 | 43.848 | 63.659 | FlexDB |
| read_100k | id_sequential | Q01 | 100000 | 3.226 | 24.845 | FlexDB |
| read_100k | id_random | Q01 | 100000 | 6.638 | 34.016 | FlexDB |
| read_100k | id_hot32 | Q01 | 100000 | 2.978 | 21.060 | FlexDB |
| read_100k | id_missing | Q01 | 100000 | 1.131 | 17.279 | FlexDB |
| read_100k | scan_matches_0 | Q06 | 20 | 12.680 | 39.414 | FlexDB |
| read_100k | scan_matches_1 | Q06 | 20 | 12.601 | 39.424 | FlexDB |
| read_100k | scan_matches_1000 | Q06 | 20 | 12.675 | 39.520 | FlexDB |
| read_100k | scan_matches_10000 | Q06 | 20 | 12.743 | 39.993 | FlexDB |
| read_100k | scan_matches_50000 | Q06 | 20 | 13.167 | 42.298 | FlexDB |
| read_100k | scan_matches_100000 | Q06 | 20 | 13.616 | 45.175 | FlexDB |
| read_100k | combined_scan | Q08 | 20 | 36.084 | 58.419 | FlexDB |
| read_100k | null_scan | Q05 | 20 | 24.132 | 43.044 | FlexDB |
| read_100k | learn_integer | A01,A02,A05 | 5 | 10.129 | 37.529 | FlexDB |
| read_100k | integer_hit | Q02,Q04 | 10000 | 1.789 | 4.155 | FlexDB |
| read_100k | integer_miss | Q02,Q04 | 10000 | 0.592 | 2.115 | FlexDB |
| read_100k | integer_materialized | Q04,Q09 | 100 | 0.052 | 0.107 | FlexDB |
| read_100k | offset_page_middle | Q10 | 10 | 3.600 | 10.318 | FlexDB |
| read_100k | aggregate_sum_loop | Q15 | 20 | 64.239 | 45.748 | SQLite |
| read_100k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| read_100k | final_close | S04 | 100000 | 33.911 | 9.639 | SQLite |
| read_100k | session_total | S05 | 1 | 344.958 | 670.794 | FlexDB |
| text8_10k | insert_reused | W01,M02,M04 | 10000 | 9.293 | 9.227 | Similar |
| text8_10k | id_sequential | Q01 | 100000 | 3.186 | 18.069 | FlexDB |
| text8_10k | id_random | Q01 | 100000 | 3.647 | 24.347 | FlexDB |
| text8_10k | id_hot32 | Q01 | 100000 | 2.983 | 18.484 | FlexDB |
| text8_10k | id_missing | Q01 | 100000 | 1.123 | 13.907 | FlexDB |
| text8_10k | scan_matches_0 | Q06 | 20 | 1.243 | 3.746 | FlexDB |
| text8_10k | scan_matches_1 | Q06 | 20 | 1.245 | 3.727 | FlexDB |
| text8_10k | scan_matches_100 | Q06 | 20 | 1.252 | 3.754 | FlexDB |
| text8_10k | scan_matches_1000 | Q06 | 20 | 1.281 | 3.800 | FlexDB |
| text8_10k | scan_matches_5000 | Q06 | 20 | 1.295 | 4.000 | FlexDB |
| text8_10k | scan_matches_10000 | Q06 | 20 | 1.334 | 4.318 | FlexDB |
| text8_10k | combined_scan | Q08 | 20 | 3.614 | 5.736 | FlexDB |
| text8_10k | null_scan | Q05 | 20 | 2.377 | 4.012 | FlexDB |
| text8_10k | learn_text | A01,A02,A05 | 5 | 2.304 | 12.044 | FlexDB |
| text8_10k | text_hit | Q03,Q04 | 10000 | 1.921 | 3.842 | FlexDB |
| text8_10k | text_miss | Q03,Q04 | 10000 | 1.401 | 2.126 | FlexDB |
| text8_10k | text_materialized | Q04,Q09 | 100 | 0.052 | 0.071 | FlexDB |
| text8_10k | offset_page_middle | Q10 | 10 | 0.367 | 1.026 | FlexDB |
| text8_10k | aggregate_sum_loop | Q15 | 20 | 6.374 | 4.754 | SQLite |
| text8_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| text8_10k | final_close | S04 | 10000 | 8.682 | 6.957 | SQLite |
| text8_10k | session_total | S05 | 1 | 78.211 | 187.054 | FlexDB |
| text32_utf8_10k | insert_reused | W01,M02,M04 | 10000 | 10.137 | 10.079 | Similar |
| text32_utf8_10k | id_sequential | Q01 | 100000 | 3.199 | 18.231 | FlexDB |
| text32_utf8_10k | id_random | Q01 | 100000 | 3.728 | 24.743 | FlexDB |
| text32_utf8_10k | id_hot32 | Q01 | 100000 | 2.985 | 18.512 | FlexDB |
| text32_utf8_10k | id_missing | Q01 | 100000 | 1.125 | 14.102 | FlexDB |
| text32_utf8_10k | scan_matches_0 | Q06 | 20 | 1.247 | 3.839 | FlexDB |
| text32_utf8_10k | scan_matches_1 | Q06 | 20 | 1.266 | 3.831 | FlexDB |
| text32_utf8_10k | scan_matches_100 | Q06 | 20 | 1.245 | 3.852 | FlexDB |
| text32_utf8_10k | scan_matches_1000 | Q06 | 20 | 1.258 | 3.902 | FlexDB |
| text32_utf8_10k | scan_matches_5000 | Q06 | 20 | 1.294 | 4.129 | FlexDB |
| text32_utf8_10k | scan_matches_10000 | Q06 | 20 | 1.346 | 4.429 | FlexDB |
| text32_utf8_10k | combined_scan | Q08 | 20 | 3.569 | 5.671 | FlexDB |
| text32_utf8_10k | null_scan | Q05 | 20 | 2.401 | 4.112 | FlexDB |
| text32_utf8_10k | learn_text | A01,A02,A05 | 5 | 3.012 | 13.090 | FlexDB |
| text32_utf8_10k | text_hit | Q03,Q04 | 10000 | 2.137 | 4.215 | FlexDB |
| text32_utf8_10k | text_miss | Q03,Q04 | 10000 | 0.974 | 2.144 | FlexDB |
| text32_utf8_10k | text_materialized | Q04,Q09 | 100 | 0.054 | 0.073 | FlexDB |
| text32_utf8_10k | offset_page_middle | Q10 | 10 | 0.370 | 1.025 | FlexDB |
| text32_utf8_10k | aggregate_sum_loop | Q15 | 20 | 6.387 | 4.689 | SQLite |
| text32_utf8_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| text32_utf8_10k | final_close | S04 | 10000 | 8.769 | 7.637 | SQLite |
| text32_utf8_10k | session_total | S05 | 1 | 80.632 | 191.841 | FlexDB |
| text256_10k | insert_reused | W01,M02,M04 | 10000 | 16.006 | 17.273 | Similar |
| text256_10k | id_sequential | Q01 | 100000 | 3.201 | 20.306 | FlexDB |
| text256_10k | id_random | Q01 | 100000 | 3.743 | 28.764 | FlexDB |
| text256_10k | id_hot32 | Q01 | 100000 | 2.997 | 20.293 | FlexDB |
| text256_10k | id_missing | Q01 | 100000 | 1.125 | 16.392 | FlexDB |
| text256_10k | scan_matches_0 | Q06 | 20 | 1.396 | 4.908 | FlexDB |
| text256_10k | scan_matches_1 | Q06 | 20 | 1.377 | 4.862 | FlexDB |
| text256_10k | scan_matches_100 | Q06 | 20 | 1.373 | 4.896 | FlexDB |
| text256_10k | scan_matches_1000 | Q06 | 20 | 1.388 | 4.938 | FlexDB |
| text256_10k | scan_matches_5000 | Q06 | 20 | 1.437 | 5.190 | FlexDB |
| text256_10k | scan_matches_10000 | Q06 | 20 | 1.499 | 5.517 | FlexDB |
| text256_10k | combined_scan | Q08 | 20 | 3.717 | 6.996 | FlexDB |
| text256_10k | null_scan | Q05 | 20 | 2.472 | 5.612 | FlexDB |
| text256_10k | learn_text | A01,A02,A05 | 5 | 7.747 | 34.178 | FlexDB |
| text256_10k | text_hit | Q03,Q04 | 10000 | 4.719 | 6.187 | FlexDB |
| text256_10k | text_miss | Q03,Q04 | 10000 | 1.116 | 2.390 | FlexDB |
| text256_10k | text_materialized | Q04,Q09 | 100 | 0.083 | 0.116 | FlexDB |
| text256_10k | offset_page_middle | Q10 | 10 | 0.403 | 1.410 | FlexDB |
| text256_10k | aggregate_sum_loop | Q15 | 20 | 6.424 | 5.955 | Similar |
| text256_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| text256_10k | final_close | S04 | 10000 | 11.921 | 0.923 | SQLite |
| text256_10k | session_total | S05 | 1 | 103.709 | 238.365 | FlexDB |
| text256_collision_1k | insert_reused | W01,M02,M04 | 1000 | 6.357 | 6.439 | Similar |
| text256_collision_1k | id_sequential | Q01 | 100000 | 3.086 | 18.550 | FlexDB |
| text256_collision_1k | id_random | Q01 | 100000 | 3.048 | 21.864 | FlexDB |
| text256_collision_1k | id_hot32 | Q01 | 100000 | 3.012 | 18.389 | FlexDB |
| text256_collision_1k | id_missing | Q01 | 100000 | 1.127 | 13.816 | FlexDB |
| text256_collision_1k | scan_matches_0 | Q06 | 20 | 0.130 | 0.451 | FlexDB |
| text256_collision_1k | scan_matches_1 | Q06 | 20 | 0.129 | 0.443 | FlexDB |
| text256_collision_1k | scan_matches_10 | Q06 | 20 | 0.130 | 0.441 | FlexDB |
| text256_collision_1k | scan_matches_100 | Q06 | 20 | 0.130 | 0.453 | FlexDB |
| text256_collision_1k | scan_matches_500 | Q06 | 20 | 0.135 | 0.468 | FlexDB |
| text256_collision_1k | scan_matches_1000 | Q06 | 20 | 0.141 | 0.502 | FlexDB |
| text256_collision_1k | combined_scan | Q08 | 20 | 0.362 | 0.652 | FlexDB |
| text256_collision_1k | null_scan | Q05 | 20 | 0.234 | 0.511 | FlexDB |
| text256_collision_1k | learn_text | A01,A02,A05 | 34 | 6.934 | 7.851 | FlexDB |
| text256_collision_1k | text_hit | Q03,Q04,A06 | 10000 | 4.294 | 4.390 | Similar |
| text256_collision_1k | text_miss | Q03,Q04 | 10000 | 0.972 | 2.333 | FlexDB |
| text256_collision_1k | text_materialized | Q04,Q09 | 100 | 0.085 | 0.077 | SQLite |
| text256_collision_1k | offset_page_middle | Q10 | 10 | 0.048 | 0.125 | FlexDB |
| text256_collision_1k | aggregate_sum_loop | Q15 | 20 | 0.634 | 0.524 | SQLite |
| text256_collision_1k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| text256_collision_1k | final_close | S04 | 1000 | 5.946 | 6.319 | Similar |
| text256_collision_1k | session_total | S05 | 1 | 60.395 | 143.914 | FlexDB |
| duplicates10_10k | insert_reused | W01,M02,M04 | 10000 | 10.145 | 9.957 | Similar |
| duplicates10_10k | id_sequential | Q01 | 100000 | 3.091 | 18.319 | FlexDB |
| duplicates10_10k | id_random | Q01 | 100000 | 3.740 | 24.936 | FlexDB |
| duplicates10_10k | id_hot32 | Q01 | 100000 | 2.983 | 18.493 | FlexDB |
| duplicates10_10k | id_missing | Q01 | 100000 | 1.124 | 13.633 | FlexDB |
| duplicates10_10k | scan_matches_0 | Q06 | 20 | 1.253 | 3.868 | FlexDB |
| duplicates10_10k | scan_matches_0 | Q06 | 20 | 1.258 | 3.896 | FlexDB |
| duplicates10_10k | scan_matches_100 | Q06 | 20 | 1.252 | 3.896 | FlexDB |
| duplicates10_10k | scan_matches_1000 | Q06 | 20 | 1.267 | 3.919 | FlexDB |
| duplicates10_10k | scan_matches_5000 | Q06 | 20 | 1.306 | 4.183 | FlexDB |
| duplicates10_10k | scan_matches_10000 | Q06 | 20 | 1.343 | 4.436 | FlexDB |
| duplicates10_10k | combined_scan | Q08 | 20 | 3.627 | 5.815 | FlexDB |
| duplicates10_10k | null_scan | Q05 | 20 | 2.392 | 4.005 | FlexDB |
| duplicates10_10k | learn_integer | A01,A02,A05 | 5 | 1.315 | 8.554 | FlexDB |
| duplicates10_10k | integer_hit | Q02,Q04 | 10000 | 2.233 | 4.838 | FlexDB |
| duplicates10_10k | integer_miss | Q02,Q04 | 10000 | 0.589 | 1.892 | FlexDB |
| duplicates10_10k | integer_materialized | Q04,Q09 | 100 | 0.180 | 0.292 | FlexDB |
| duplicates10_10k | offset_page_middle | Q10 | 10 | 0.373 | 1.026 | FlexDB |
| duplicates10_10k | aggregate_sum_loop | Q15 | 20 | 6.392 | 4.537 | SQLite |
| duplicates10_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| duplicates10_10k | final_close | S04 | 10000 | 9.041 | 7.274 | SQLite |
| duplicates10_10k | session_total | S05 | 1 | 78.534 | 187.470 | FlexDB |
| duplicates100_10k | insert_reused | W01,M02,M04 | 10000 | 9.945 | 9.853 | Similar |
| duplicates100_10k | id_sequential | Q01 | 100000 | 3.225 | 18.393 | FlexDB |
| duplicates100_10k | id_random | Q01 | 100000 | 3.783 | 24.365 | FlexDB |
| duplicates100_10k | id_hot32 | Q01 | 100000 | 2.989 | 18.764 | FlexDB |
| duplicates100_10k | id_missing | Q01 | 100000 | 1.126 | 13.527 | FlexDB |
| duplicates100_10k | scan_matches_0 | Q06 | 20 | 1.251 | 3.832 | FlexDB |
| duplicates100_10k | scan_matches_0 | Q06 | 20 | 1.255 | 3.824 | FlexDB |
| duplicates100_10k | scan_matches_100 | Q06 | 20 | 1.292 | 3.860 | FlexDB |
| duplicates100_10k | scan_matches_1000 | Q06 | 20 | 1.283 | 3.891 | FlexDB |
| duplicates100_10k | scan_matches_5000 | Q06 | 20 | 1.340 | 4.120 | FlexDB |
| duplicates100_10k | scan_matches_10000 | Q06 | 20 | 1.350 | 4.375 | FlexDB |
| duplicates100_10k | combined_scan | Q08 | 20 | 3.665 | 5.780 | FlexDB |
| duplicates100_10k | null_scan | Q05 | 20 | 2.397 | 4.069 | FlexDB |
| duplicates100_10k | learn_integer | A01,A02,A05 | 5 | 3.892 | 8.648 | FlexDB |
| duplicates100_10k | integer_hit | Q02,Q04 | 10000 | 3.033 | 19.389 | FlexDB |
| duplicates100_10k | integer_miss | Q02,Q04 | 10000 | 0.592 | 1.948 | FlexDB |
| duplicates100_10k | integer_materialized | Q04,Q09 | 100 | 1.613 | 2.285 | FlexDB |
| duplicates100_10k | offset_page_middle | Q10 | 10 | 0.372 | 1.017 | FlexDB |
| duplicates100_10k | aggregate_sum_loop | Q15 | 20 | 6.362 | 4.529 | SQLite |
| duplicates100_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| duplicates100_10k | final_close | S04 | 10000 | 8.636 | 6.873 | SQLite |
| duplicates100_10k | session_total | S05 | 1 | 82.212 | 202.616 | FlexDB |
| duplicates1000_10k | insert_reused | W01,M02,M04 | 10000 | 10.208 | 9.742 | Similar |
| duplicates1000_10k | id_sequential | Q01 | 100000 | 3.178 | 18.457 | FlexDB |
| duplicates1000_10k | id_random | Q01 | 100000 | 3.731 | 25.089 | FlexDB |
| duplicates1000_10k | id_hot32 | Q01 | 100000 | 2.990 | 18.824 | FlexDB |
| duplicates1000_10k | id_missing | Q01 | 100000 | 1.123 | 14.085 | FlexDB |
| duplicates1000_10k | scan_matches_0 | Q06 | 20 | 1.249 | 4.120 | FlexDB |
| duplicates1000_10k | scan_matches_0 | Q06 | 20 | 1.266 | 4.112 | FlexDB |
| duplicates1000_10k | scan_matches_0 | Q06 | 20 | 1.260 | 4.138 | FlexDB |
| duplicates1000_10k | scan_matches_1000 | Q06 | 20 | 1.256 | 4.028 | FlexDB |
| duplicates1000_10k | scan_matches_5000 | Q06 | 20 | 1.302 | 4.288 | FlexDB |
| duplicates1000_10k | scan_matches_10000 | Q06 | 20 | 1.345 | 4.585 | FlexDB |
| duplicates1000_10k | combined_scan | Q08 | 20 | 3.610 | 6.116 | FlexDB |
| duplicates1000_10k | null_scan | Q05 | 20 | 2.385 | 4.075 | FlexDB |
| duplicates1000_10k | learn_integer | A01,A02,A05 | 5 | 29.224 | 11.157 | SQLite |
| duplicates1000_10k | integer_hit | Q02,Q04 | 10000 | 1.014 | 167.368 | FlexDB |
| duplicates1000_10k | integer_miss | Q02,Q04 | 10000 | 0.593 | 1.956 | FlexDB |
| duplicates1000_10k | integer_materialized | Q04,Q09 | 100 | 17.672 | 19.912 | FlexDB |
| duplicates1000_10k | offset_page_middle | Q10 | 10 | 0.372 | 1.053 | FlexDB |
| duplicates1000_10k | aggregate_sum_loop | Q15 | 20 | 6.389 | 4.507 | SQLite |
| duplicates1000_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| duplicates1000_10k | final_close | S04 | 10000 | 9.123 | 10.429 | FlexDB |
| duplicates1000_10k | session_total | S05 | 1 | 122.484 | 375.799 | FlexDB |
| nulls50_10k | insert_reused | W01,M02,M04 | 10000 | 10.250 | 10.147 | Similar |
| nulls50_10k | id_sequential | Q01 | 100000 | 3.201 | 18.386 | FlexDB |
| nulls50_10k | id_random | Q01 | 100000 | 3.721 | 24.764 | FlexDB |
| nulls50_10k | id_hot32 | Q01 | 100000 | 2.988 | 19.029 | FlexDB |
| nulls50_10k | id_missing | Q01 | 100000 | 1.127 | 13.796 | FlexDB |
| nulls50_10k | scan_matches_0 | Q06 | 20 | 1.254 | 3.794 | FlexDB |
| nulls50_10k | scan_matches_1 | Q06 | 20 | 1.257 | 3.800 | FlexDB |
| nulls50_10k | scan_matches_100 | Q06 | 20 | 1.248 | 3.852 | FlexDB |
| nulls50_10k | scan_matches_1000 | Q06 | 20 | 1.252 | 3.859 | FlexDB |
| nulls50_10k | scan_matches_5000 | Q06 | 20 | 1.296 | 4.125 | FlexDB |
| nulls50_10k | scan_matches_10000 | Q06 | 20 | 1.341 | 4.411 | FlexDB |
| nulls50_10k | combined_scan | Q08 | 20 | 3.374 | 5.367 | FlexDB |
| nulls50_10k | null_scan | Q05 | 20 | 2.436 | 4.406 | FlexDB |
| nulls50_10k | learn_integer | A01,A02,A05 | 5 | 0.993 | 11.278 | FlexDB |
| nulls50_10k | integer_hit | Q02,Q04 | 10000 | 1.518 | 3.308 | FlexDB |
| nulls50_10k | integer_miss | Q02,Q04 | 10000 | 0.592 | 1.929 | FlexDB |
| nulls50_10k | integer_materialized | Q04,Q09 | 100 | 0.046 | 0.067 | FlexDB |
| nulls50_10k | offset_page_middle | Q10 | 10 | 0.371 | 1.023 | FlexDB |
| nulls50_10k | aggregate_sum_loop | Q15 | 20 | 6.378 | 4.503 | SQLite |
| nulls50_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| nulls50_10k | final_close | S04 | 10000 | 8.922 | 7.142 | SQLite |
| nulls50_10k | session_total | S05 | 1 | 77.479 | 188.254 | FlexDB |
| nulls90_10k | insert_reused | W01,M02,M04 | 10000 | 9.918 | 9.962 | Similar |
| nulls90_10k | id_sequential | Q01 | 100000 | 3.148 | 18.125 | FlexDB |
| nulls90_10k | id_random | Q01 | 100000 | 3.721 | 24.872 | FlexDB |
| nulls90_10k | id_hot32 | Q01 | 100000 | 2.988 | 18.386 | FlexDB |
| nulls90_10k | id_missing | Q01 | 100000 | 1.122 | 13.776 | FlexDB |
| nulls90_10k | scan_matches_0 | Q06 | 20 | 1.262 | 3.786 | FlexDB |
| nulls90_10k | scan_matches_1 | Q06 | 20 | 1.270 | 3.794 | FlexDB |
| nulls90_10k | scan_matches_100 | Q06 | 20 | 1.252 | 3.832 | FlexDB |
| nulls90_10k | scan_matches_1000 | Q06 | 20 | 1.256 | 3.868 | FlexDB |
| nulls90_10k | scan_matches_5000 | Q06 | 20 | 1.305 | 4.115 | FlexDB |
| nulls90_10k | scan_matches_10000 | Q06 | 20 | 1.346 | 4.363 | FlexDB |
| nulls90_10k | combined_scan | Q08 | 20 | 3.114 | 4.840 | FlexDB |
| nulls90_10k | null_scan | Q05 | 20 | 2.465 | 4.548 | FlexDB |
| nulls90_10k | learn_integer | A01,A02,A05 | 5 | 0.996 | 11.376 | FlexDB |
| nulls90_10k | integer_hit | Q02,Q04 | 10000 | 1.521 | 3.413 | FlexDB |
| nulls90_10k | integer_miss | Q02,Q04 | 10000 | 0.589 | 1.937 | FlexDB |
| nulls90_10k | integer_materialized | Q04,Q09 | 100 | 0.046 | 0.063 | FlexDB |
| nulls90_10k | offset_page_middle | Q10 | 10 | 0.374 | 1.027 | FlexDB |
| nulls90_10k | aggregate_sum_loop | Q15 | 20 | 6.376 | 4.479 | SQLite |
| nulls90_10k | id_latency_sample | Q01 | 2000 | 0.000 | 0.000 | FlexDB |
| nulls90_10k | final_close | S04 | 10000 | 8.617 | 7.254 | SQLite |
| nulls90_10k | session_total | S05 | 1 | 76.974 | 187.228 | FlexDB |
| write_10k | insert_reused | W01,M02,M04 | 10000 | 10.052 | 10.250 | Similar |
| write_10k | learn_integer | A01,A02,A05 | 5 | 1.169 | 7.906 | FlexDB |
| write_10k | update_unindexed_field | W04 | 1000 | 6.030 | 6.365 | Similar |
| write_10k | update_indexed_field | W04 | 1000 | 6.369 | 6.316 | Similar |
| write_10k | rollback_mixed_1002 | W08 | 1002 | 0.947 | 0.847 | SQLite |
| write_10k | grow_text_256 | W06 | 1000 | 6.971 | 7.605 | Similar |
| write_10k | shrink_text_5 | W06 | 1000 | 6.167 | 6.907 | FlexDB |
| write_10k | delete_batch | W07 | 1000 | 5.536 | 6.617 | FlexDB |
| write_10k | deleted_id_reads | Q01,W07 | 10000 | 0.275 | 17.105 | FlexDB |
| write_10k | empty_transactions | W09 | 200 | 2.348 | 0.068 | SQLite |
| write_10k | indexed_insert_batch | W03 | 1000 | 5.782 | 5.807 | Similar |
| write_10k | final_close | S04 | 10000 | 9.324 | 7.794 | SQLite |
| write_10k | session_total | S05 | 1 | 78.230 | 119.539 | FlexDB |
| lifecycle_100k | insert_reused | W01,M02,M04 | 100000 | 43.972 | 61.653 | FlexDB |
| lifecycle_100k | learn_integer | A01,A02,A05 | 5 | 11.006 | 35.402 | FlexDB |
| lifecycle_100k | checkpoint_close | S04 | 100000 | 31.392 | 9.563 | SQLite |
| lifecycle_100k | reopen_first_id | S01,S02,D01 | 1 | 0.110 | 0.232 | FlexDB |
| lifecycle_100k | first_full_scan | S03 | 1 | 15.125 | 3.396 | SQLite |
| lifecycle_100k | cached_full_scan | S03 | 1 | 0.945 | 2.229 | FlexDB |
| lifecycle_100k | matching_schema_1000 | D01 | 1000 | 0.259 | 3.084 | FlexDB |
| lifecycle_100k | mapped_first_write | A08,W04 | 1000 | 10.690 | 16.332 | FlexDB |
| lifecycle_100k | mapped_later_write | A08,W04 | 1000 | 6.427 | 6.270 | Similar |
| lifecycle_100k | integrity | S08 | 100000 | 35.659 | 19.938 | SQLite |
| lifecycle_100k | compaction | S07,S09 | 100000 | 33.257 | 48.632 | FlexDB |
| lifecycle_100k | session_total | S05 | 1 | 218.841 | 248.164 | FlexDB |
| join_unique_1k | insert_reused | W01,M02,M04 | 1000 | 5.652 | 5.651 | Similar |
| join_unique_1k | self_join | Q11 | 1 | 0.290 | 0.558 | FlexDB |
| join_unique_1k | final_close | S04 | 1000 | 0.027 | 5.365 | FlexDB |
| join_unique_1k | session_total | S05 | 1 | 21.276 | 46.949 | FlexDB |
| join_duplicates10_1k | insert_reused | W01,M02,M04 | 1000 | 5.628 | 5.659 | Similar |
| join_duplicates10_1k | self_join | Q11 | 1 | 1.388 | 2.367 | FlexDB |
| join_duplicates10_1k | final_close | S04 | 1000 | 0.021 | 5.350 | FlexDB |
| join_duplicates10_1k | session_total | S05 | 1 | 22.252 | 48.825 | FlexDB |
| schema_10k | insert_reused | W01,M02,M04 | 10000 | 10.121 | 9.981 | Similar |
| schema_10k | schema_noop | D01 | 1000 | 0.249 | 2.623 | FlexDB |
| schema_10k | schema_add_nullable | D02,D03,D04 | 10000 | 13.331 | 5.163 | SQLite |
| schema_10k | schema_add_default | D02,D03,D04 | 10000 | 14.382 | 5.090 | SQLite |
| schema_10k | schema_rename_reorder_drop | D02,D03,D04 | 10000 | 12.905 | 11.937 | Similar |
| schema_10k | schema_convert | D02,D03,D04 | 10000 | 15.432 | 12.185 | SQLite |
| schema_10k | final_close | S04 | 10000 | 9.673 | 7.994 | SQLite |
| schema_10k | session_total | S05 | 1 | 92.693 | 90.716 | Similar |
| mixed95read_10k | insert_reused | W01,M02,M04 | 10000 | 10.041 | 9.966 | Similar |
| mixed95read_10k | learn_integer | A01,A02,A05 | 5 | 1.152 | 7.819 | FlexDB |
| mixed95read_10k | mixed_writes_5 | X01,A03 | 1000 | 250.853 | 258.433 | Similar |
| mixed95read_10k | final_close | S04 | 10000 | 9.102 | 7.446 | SQLite |
| mixed95read_10k | session_total | S05 | 1 | 287.855 | 320.005 | FlexDB |
| mixed80read_10k | insert_reused | W01,M02,M04 | 10000 | 10.074 | 9.991 | Similar |
| mixed80read_10k | learn_integer | A01,A02,A05 | 5 | 1.195 | 7.893 | FlexDB |
| mixed80read_10k | mixed_writes_20 | X01,A03 | 1000 | 1003.551 | 1036.463 | Similar |
| mixed80read_10k | final_close | S04 | 10000 | 9.217 | 8.009 | SQLite |
| mixed80read_10k | session_total | S05 | 1 | 1040.348 | 1098.492 | Similar |
| mixed50read_10k | insert_reused | W01,M02,M04 | 10000 | 10.069 | 10.059 | Similar |
| mixed50read_10k | learn_integer | A01,A02,A05 | 5 | 1.126 | 7.806 | FlexDB |
| mixed50read_10k | mixed_writes_50 | X01,A03 | 1000 | 2553.059 | 2600.638 | Similar |
| mixed50read_10k | final_close | S04 | 10000 | 9.223 | 8.910 | Similar |
| mixed50read_10k | session_total | S05 | 1 | 2590.030 | 2664.344 | Similar |
| adaptive_10k | insert_reused | W01,M02,M04 | 10000 | 10.239 | 10.069 | Similar |
| adaptive_10k | budget_0 | A01,A02,A04,A05 | 200 | 11.288 | 38.791 | FlexDB |
| adaptive_10k | budget_262144 | A01,A02,A04,A05 | 200 | 11.235 | 8.623 | SQLite |
| adaptive_10k | budget_1048576 | A01,A02,A04,A05 | 200 | 1.021 | 8.346 | FlexDB |
| adaptive_10k | budget_4194304 | A01,A02,A04,A05 | 200 | 1.007 | 8.162 | FlexDB |
| adaptive_10k | budget_8388608 | A01,A02,A04,A05 | 200 | 1.003 | 8.073 | FlexDB |
| adaptive_10k | switch_to_text | A03,A10 | 2000 | 3.352 | 13.868 | FlexDB |
| adaptive_10k | return_to_integer | A03,A10 | 200 | 0.777 | 0.391 | SQLite |
| adaptive_10k | demand_becomes_broad | A03,Q04 | 100 | 0.200 | 14.911 | FlexDB |
| adaptive_10k | final_close | S04 | 10000 | 13.515 | 7.981 | SQLite |
| adaptive_10k | session_total | S05 | 1 | 324.952 | 190.373 | SQLite |
| recovery_10k | process_exit_recovery | R01,S06,A09 | 1 | 0.103 | 0.441 | FlexDB |
| recovery_10k | first_equality_after_tail | A09 | 1 | 3.101 | 0.006 | SQLite |
| recovery_10k | final_close | S04 | 10000 | 9.017 | 10.080 | FlexDB |
| recovery_10k | session_total | S05 | 1 | 12.403 | 10.537 | SQLite |
| batch_1k | insert_reused | W01,M02,M04 | 1000 | 5.709 | 5.651 | Similar |
| batch_1k | insert_batch_1 | W02,W05 | 1000 | 5022.410 | 5179.974 | Similar |
| batch_1k | insert_batch_10 | W02,W05 | 1000 | 502.642 | 509.500 | Similar |
| batch_1k | insert_batch_100 | W02,W05 | 1000 | 51.323 | 51.490 | Similar |
| batch_1k | insert_batch_1000 | W02,W05 | 1000 | 5.642 | 5.610 | Similar |
| batch_1k | final_close | S04 | 1000 | 6.648 | 7.053 | Similar |
| batch_1k | session_total | S05 | 1 | 5611.897 | 5795.115 | Similar |
| churn100_1k | insert_reused | W01,M02,M04 | 1000 | 5.640 | 5.657 | Similar |
| churn100_1k | learn_integer | A01,A02,A05 | 34 | 0.329 | 6.182 | FlexDB |
| churn100_1k | churn_cycle_25 | W10,M01 | 25500 | 158.874 | 152.380 | Similar |
| churn100_1k | churn_compact_25 | W10,S07 | 1000 | 10.892 | 5.470 | SQLite |
| churn100_1k | churn_cycle_50 | W10,M01 | 25500 | 168.968 | 151.571 | SQLite |
| churn100_1k | churn_compact_50 | W10,S07 | 1000 | 10.814 | 5.488 | SQLite |
| churn100_1k | churn_cycle_75 | W10,M01 | 25500 | 161.348 | 151.287 | Similar |
| churn100_1k | churn_compact_75 | W10,S07 | 1000 | 10.907 | 5.496 | SQLite |
| churn100_1k | churn_cycle_100 | W10,M01 | 25500 | 161.537 | 162.371 | Similar |
| churn100_1k | churn_compact_100 | W10,S07 | 1000 | 10.887 | 5.546 | SQLite |
| churn100_1k | churn_total | W10 | 102000 | 696.176 | 650.010 | Similar |
| churn100_1k | final_close | S04 | 1000 | 3.713 | 6.201 | FlexDB |
| churn100_1k | session_total | S05 | 1 | 721.784 | 703.847 | Similar |

## Provenance and resources

262 timing rows favor FlexDB by >10%, 48 fall within 10%, and 45 favor SQLite
by >10%. Resource metrics below are separate from these timing counts.

Raw report: `build/flexdb/bench/roadmap-optimized-final.json`.
Preserved workers: `/home/teppo/Work/flexscript/build/flexdb/tmp/flexscript-tools-86dbede7819bf11e`.

| Worker | SHA-256 |
| --- | --- |
| flexdb | `316cb362913c1adefbe2860aafcd97b4e410520f55ffa26e84be62b02839e821` |
| sqlite | `56e317bd562bd229574b615f9bfaf2ca6900d3af6518feb4681be69debd29d92` |

| Scenario | FlexDB peak KiB | SQLite peak KiB | FlexDB final bytes | SQLite final bytes | FlexDB storage write bytes | SQLite storage write bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| read_1k | 2,856 | 4,172 | 175,906 | 73,728 | 335,872 | 581,632 |
| read_10k | 6,236 | 5,024 | 1,950,274 | 577,536 | 2,179,072 | 1,785,856 |
| read_100k | 38,276 | 16,300 | 18,446,266 | 5,988,352 | 18,771,968 | 12,939,264 |
| text8_10k | 5,580 | 4,544 | 1,486,274 | 397,312 | 1,794,048 | 1,507,328 |
| text32_utf8_10k | 6,228 | 5,600 | 1,950,274 | 884,736 | 2,244,608 | 2,535,424 |
| text256_10k | 17,024 | 14,756 | 6,446,274 | 5,492,736 | 6,770,688 | 11,792,384 |
| text256_collision_1k | 3,520 | 4,972 | 625,506 | 561,152 | 884,736 | 1,835,008 |
| duplicates10_10k | 6,128 | 4,720 | 1,966,274 | 581,632 | 2,310,144 | 1,957,888 |
| duplicates100_10k | 5,900 | 4,720 | 1,966,274 | 561,152 | 2,326,528 | 1,916,928 |
| duplicates1000_10k | 5,724 | 4,592 | 1,966,274 | 552,960 | 2,277,376 | 1,900,544 |
| nulls50_10k | 6,232 | 5,000 | 1,886,274 | 569,344 | 2,146,304 | 1,769,472 |
| nulls90_10k | 6,220 | 5,028 | 1,822,274 | 561,152 | 2,080,768 | 1,802,240 |
| write_10k | 8,312 | 5,252 | 2,639,666 | 831,488 | 3,317,760 | 3,743,744 |
| lifecycle_100k | 49,564 | 20,072 | 12,187,001 | 6,017,024 | 31,707,136 | 25,759,744 |
| join_unique_1k | 2,076 | 4,268 | 64,297 | 57,344 | 286,720 | 753,664 |
| join_duplicates10_1k | 2,848 | 4,448 | 64,297 | 57,344 | 270,336 | 770,048 |
| schema_10k | 13,052 | 5,476 | 6,223,497 | 995,328 | 6,844,416 | 5,378,048 |
| mixed95read_10k | 5,652 | 5,024 | 1,972,574 | 581,632 | 5,763,072 | 5,967,872 |
| mixed80read_10k | 5,660 | 4,988 | 1,991,474 | 581,632 | 16,211,968 | 19,693,568 |
| mixed50read_10k | 5,832 | 5,028 | 2,029,274 | 581,632 | 37,138,432 | 46,141,440 |
| adaptive_10k | 11,132 | 5,796 | 3,499,746 | 995,328 | 3,911,680 | 4,907,008 |
| recovery_10k | 6,244 | 4,116 | 3,292,415 | 581,632 | 1,409,024 | 208,896 |
| batch_1k | 3,048 | 4,152 | 594,466 | 151,552 | 78,315,520 | 97,837,056 |
| churn100_1k | 31,060 | 4,304 | 102,273 | 45,056 | 15,364,096 | 11,857,920 |

Storage read-byte counters were zero in these warm-cache trials. Storage I/O
covers the whole worker, including setup and maintenance. Final size is after
close and excludes temporary/sidecar peak sizes. RSS is post-exec process VmHWM.
These metrics do not imply equivalent lifetime or memory-budget scopes.

## Churn memory progression

| Completed cycles | FlexDB current RSS KiB | SQLite current RSS KiB |
| ---: | ---: | ---: |
| 25 | 9,288 | 4,152 |
| 50 | 16,468 | 4,288 |
| 75 | 23,648 | 4,288 |
| 100 | 30,828 | 4,288 |

FlexDB still retains immutable row versions and database-arena input values until
close. Compaction removes old file contents, not captured in-memory values.
SQLite's returned-value lifetime and prepared input bindings differ. Beating
this memory metric requires a deliberate ownership/reclamation design.

## Interpretation

See [the roadmap results](benchmark-results.md) for the before/after comparison,
implementation changes, limitations and all 75 targets' coverage. Predicate pages,
scalar views and integer count memos are actual optimized API paths; they should
not be described as measurements of the prior full materialization/cold-count
implementation. SQLite still wins a number of storage/schema/aggregate timings
and most large-workload memory/file-size comparisons. No overall winner across
all workloads or unsupported features is claimed.
