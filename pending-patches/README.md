# Pending patches — apply ONLY when needed

One fix for FPC-trunk/freertos+xtensa deficiencies still awaiting a
triggering program in this tree (ESP-IDF-6.1 line). They originate from
the `rewind-fpc-esp` workspace (`rewind-fpc-esp/fpc-main/*.patch`), where
the identical series is applied and verified by a 36-test regression
suite. Ground rule: minimal, non-invasive, one fix per patch — the goal
of this project is to make FPC support the ESP32 family, never to improve
FPC's freertos support (see `../AGENTS.md` §2 rule 3).

## How to apply

```sh
cd /mnt/storage/fpc-esp/fpc
git apply pending-patches/freertos-02-tthread-raise.patch
```

After applying: rebuild what the patch touches — the patch below is RTL
(`cd rtl && make clean all install ...`). Rebuild recipe with all traps
documented: `../AGENTS.md` §9 step 5 (sibling doc, same makefile system)
or the notes at the bottom of this file. **Caveat:** the patches were
authored against the `bc94d466c9` baseline; this tree carries three extra
ESP-IDF-6.1 commits that touch `rtl/freertos/` - run
`git apply --check <patch>` first. Note also that the RTL makefile does
not track `.inc` includes: after any `systhrd.inc`-style change, wipe
`rtl/units/xtensa-freertos` and rebuild clean, or the compiler's parallel
task machinery dies with `Internal error 2026032615` (ctask.pas
finishmodule) on the stale `system.ppu`.

## Pending

### `freertos-02-tthread-raise.patch` -> `rtl/freertos/tthread.inc`

- **Deficiency:** upstream `TThread.SysCreate` silently bumps a counter -
  a fake thread that never runs. Code using TThread appears to work and
  silently does nothing.
- **Fix:** `TThread.Create` raises a clear exception instead of pretending.
- **Discriminator test:** `TThread.Create`. Unpatched -> silent fake;
  patched -> exception. (Requires the already-applied patch 01 - without
  it `uses Classes` dies at unit init first.)
- **Status:** no program in this tree has created a TThread yet - apply
  when one does.

## Applied from this series (history)

- **freertos-01 (thread-stub events) -> `rtl/freertos/systhrd.inc` -
  APPLIED.** Upstream points the whole event surface at `NoThreadError`,
  but unit initialization legitimately calls events (`Classes.CommonInit`,
  `TMultiReadExclusiveWriteSynchronizer.Create`), so every `uses Classes`
  program died at init. Fix: create -> nil, destroy/set/reset -> no-ops
  (`Sys*` stubs); all WaitFor vectors stay loud. Verified by
  revert-retest on hardware: without it, `idfheap-smoke` (which never
  uses threads!) crashed in `Classes.CommonCleanup` at unit finalization
  - the need comes from Classes' own lifecycle housekeeping, not from
  program threads.
- **freertos-03 (InitInternational) -> `rtl/freertos/sysutils.pp` -
  APPLIED.** Upstream freertos SysUtils init never calls
  `InitInternational`, leaving `widestringmanager` compare/text proc
  pointers nil - first `TStringList.Sort`/`AnsiCompareStr` calls through
  nil (PC=0, InstrFetchProhibited). Hit organically on hardware by
  `idfheap-smoke`; with the fix it sorts and exits clean. Upstream-report
  candidate.
- **xtensa-04 (finalize order) -> `compiler/xtensa/ncpuutil.pas` -
  APPLIED (2026-10-24).** Deficiency: `FPC_FINALIZE_FUNC_TABLE` iterated
  the init/finalize entries **forward** - finalization ran in init order;
  SysUtils' `TEncoding` class destructor freed the standard-encoding
  singletons before Classes' teardown touched them (`TStrings.Destroy` ->
  `IsStandardEncoding` false against the emptied list -> freed the dead
  singleton -> use-after-free, PC=8 through a zeroed VMT). Reproduced on
  QEMU+hardware with an unpatched compiler build (`t_classes_minimal`
  and TEncoding-touching probes); with the fix the linked finalize call
  order is CLASSES -> TYPINFO -> SYSUTILS -> OBJPAS -> CONSOLEIO and all
  canaries exit clean. Upstream-report candidate (same forward iterate
  in aarch64/arm/avr/riscv generators).

## Baseline record

An entirely unpatched build (no pending patch applied) compiled and ran
`helloworld` correctly on QEMU (octal PSRAM) and real hardware -
helloworld exercises none of these paths, which is exactly why the
patches are gated by dedicated discriminator programs instead.
