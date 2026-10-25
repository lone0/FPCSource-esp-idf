# Pending patches — apply ONLY when needed

One freertos deficiency still awaits a triggering program on this
ESP-IDF 6.1 line. Ground rule: minimal, non-invasive, one fix per patch —
unblock ESP32-family support, never “improve FreeRTOS support” for its
own sake (see `../AGENTS.md` §2).

## How to apply

```sh
# From this repository root (the FPC source tree that contains pending-patches/).
git apply pending-patches/freertos-02-tthread-raise.patch
```

After applying: rebuild the freertos RTL (`cd rtl && make clean all …` for
the target). See `../AGENTS.md` §2 (`.inc` wipe) and §5 (RISC-V / S31).
Run `git apply --check` first: this tree already carries ESP-IDF 6.1
commits that touch `rtl/freertos/`.

The RTL makefile does not track `.inc` includes: after any
`systhrd.inc`-style change, wipe `rtl/units/xtensa-freertos` and/or
`rtl/units/riscv32-freertos` and rebuild clean, or the compiler dies with
`Internal error 2026032615` on a stale `system.ppu`.

## Pending

### `freertos-02-tthread-raise.patch` → `rtl/freertos/tthread.inc`

- **Deficiency:** upstream `TThread.SysCreate` silently bumps a counter —
  a fake thread that never runs. Code using TThread appears to work and
  silently does nothing.
- **Fix:** `TThread.Create` raises a clear exception instead of pretending.
- **Discriminator test:** `TThread.Create`. Unpatched → silent fake;
  patched → exception. (Requires the already-applied freertos-01 — without
  it `uses Classes` dies at unit init first.)
- **Status:** no program in this tree has created a TThread yet — apply
  when one does.

## Applied from this series (history)

- **freertos-01 (thread-stub events) → `rtl/freertos/systhrd.inc` —
  APPLIED.** Upstream points the whole event surface at `NoThreadError`,
  but unit initialization legitimately calls events (`Classes.CommonInit`,
  `TMultiReadExclusiveWriteSynchronizer.Create`), so every `uses Classes`
  program died at init. Fix: create → nil, destroy/set/reset → no-ops
  (`Sys*` stubs); all WaitFor vectors stay loud. The need comes from
  Classes' own lifecycle housekeeping, not from program threads.

- **freertos-03 (InitInternational) → `rtl/freertos/sysutils.pp` —
  APPLIED.** Upstream freertos SysUtils init never calls
  `InitInternational`, leaving `widestringmanager` compare/text proc
  pointers nil — first `TStringList.Sort` / `AnsiCompareStr` calls through
  nil (`PC=0`, InstrFetchProhibited). Upstream-report candidate.

- **xtensa-04 (finalize order) → `compiler/xtensa/ncpuutil.pas` —
  APPLIED (2026-10-24, on `esp32s3-esp-idf-6.1-support`).**
  `FPC_FINALIZE_FUNC_TABLE` iterated init/finalize entries **forward**;
  SysUtils' `TEncoding` destructor freed standard encodings before Classes
  teardown → use-after-free at exit with live `TStrings`. Fix: separate
  reverse pass for finalize calls. Verified on ESP32-S3 (QEMU + hardware):
  linked finalize order `CLASSES → TYPINFO → SYSUTILS → OBJPAS → CONSOLEIO`.
  The patch file was removed after apply. **Xtensa-only** — RISC-V needs
  the same contract in `compiler/riscv32/nrv32util.pas` (see
  `AGENTS.md` §5.6); that is not this patch file.

## Baseline record

A trivial helloworld (no Classes / AnsiCompare / live `TStrings` at exit)
can pass without these fixes — that is why remaining work stays gated by
dedicated discriminator programs.
