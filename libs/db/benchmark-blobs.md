# FlexDB external blob benchmark

Artifacts: `/home/teppo/Work/flexscript/build/flexdb/tmp/flexscript-tools-97bb9a9453f37432`

Native Flexscript; 4 MiB synthetic variable-sequence log records and deterministic high-entropy bytes. One measured sample per level, not a throughput ranking. Commit includes compression, extent writes and fsync; input construction excluded. Read validates the full blob using successive 64 KiB range requests; each compressed range request currently decodes from frame start. Stream-all uses a fresh connection, validates the stored CRC, and keeps one incremental decoder with a 64 KiB caller buffer. OS file cache remains warm; output byte validation is included. Compressed data is preserved through checkpoints/compaction.

| Payload | Level | Logical bytes | Stored bytes | Ratio | Codec | Compacted file bytes | Commit ms | Reopen+row ms | All ranges ms | Stream all ms | Metadata+checkpoint growth bytes | Compact ms |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| logs | 1 | 4194304 | 32674 | 128.36x | zstd | 33148 | 5.995 | 0.093 | 30.286 | 1.437 | 522 | 10.177 |
| logs | 6 | 4194304 | 32674 | 128.36x | zstd | 33148 | 18.729 | 0.049 | 29.901 | 1.432 | 522 | 10.091 |
| logs | 9 | 4194304 | 27880 | 150.44x | zstd | 28354 | 22.469 | 0.048 | 30.193 | 1.420 | 522 | 10.206 |
| logs | 14 | 4194304 | 27880 | 150.44x | zstd | 28354 | 21.857 | 0.051 | 30.253 | 1.415 | 522 | 10.125 |
| varied-logs | 1 | 4194304 | 535967 | 7.82x | zstd | 536441 | 9.882 | 0.048 | 93.414 | 2.660 | 522 | 10.404 |
| varied-logs | 6 | 4194304 | 568121 | 7.38x | zstd | 568595 | 25.765 | 0.050 | 99.456 | 2.753 | 522 | 10.405 |
| varied-logs | 9 | 4194304 | 553770 | 7.57x | zstd | 554244 | 37.321 | 0.050 | 93.774 | 2.670 | 522 | 10.518 |
| varied-logs | 14 | 4194304 | 545498 | 7.68x | zstd | 545972 | 139.084 | 0.054 | 93.904 | 2.647 | 522 | 10.410 |
| random | 1 | 4194304 | 4194304 | 1.00x | raw | 4194778 | 10.752 | 0.051 | 2.960 | 2.783 | 522 | 12.000 |
| random | 9 | 4194304 | 4194304 | 1.00x | raw | 4194778 | 12.813 | 0.055 | 2.967 | 2.755 | 522 | 11.891 |
| already-zstd14 | 9 | 27880 | 1475 | 18.90x | zstd | 1949 | 5.057 | 0.046 | 0.059 | 0.035 | 522 | 9.976 |

Ratios describe these synthetic inputs, not production logs. Compression depends on source redundancy. Random input must fall back to raw; library size and temporary compaction/pinned-inode space are excluded from final file bytes.

## Recorded execution (2026-10-17)

CPU: AMD Ryzen 9 5900X 12-Core Processor. Linux 7.2.5-3-omarchy. Zstd runtime: `libzstd.so.1.5.7`.
Unpinned single measured sample per case; timings are diagnostic, not a repeated
throughput comparison. Ratios and bytes were checked, and all decoded bytes are
compared with the original inputs in the benchmark.

Default level 1 on varied synthetic logs: 9.882 ms durable commit, 2.660 ms fresh-reader streaming/CRC/output validation with warm OS cache.
The 4 MiB high-entropy case stores raw and has 474 bytes of compacted-file overhead.
Metadata update plus checkpoint adds 522 bytes for this one-row schema.
Repetitive synthetic logs compress much more strongly; their 128–150x ratios
are not predictions for production data. Higher levels were not uniformly smaller.

Checks: 1,005 core plus 80 harness checks pass, including the dedicated blob
suite and a twice-run example. An additional three-round 1K-row SQLite smoke
comparison matched all operation counts/checksums; the full 355-case historical
SQLite matrix was not rerun for this feature. See `build/flexdb/test-external-final.log`
and `build/flexdb/bench/roadmap-blob-smoke.json`.

| Artifact | SHA-256 |
| --- | --- |
| `scripts/benchmark-flexdb-blobs.flex` | `4f43d2c73c4632c0e580534fd0a6f07035a669ca561a22e5f26b98fabaf57c2d` |
| `build/flexdb/benchmark-blobs` | `e75ebb3a601e357b85dac6a1f98616ef9e20a06c483c2d49279b88df2f48f9c3` |
| `libs/db/blob.flex` | `b5ed539cb0e4ae65339464d78b4b5063d3a128ca0af31c0b6812bc986ccf767b` |

Raw measurement output: `build/flexdb/benchmark-blobs-final.md`.

Initial limits: one compressed frame per blob, 64 MiB minus one byte logical
blob maximum, pending transaction payloads staged in memory, and reclamation by
compaction. Incremental readers avoid repeated decoding; random compressed range
reads restart the frame. Compaction/pinned old inodes can temporarily consume
additional disk space. Read [the API and storage design](blobs.md).
