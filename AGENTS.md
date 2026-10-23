# AGENTS.md — read me first (for AI agents, and humans too)

> **⚠ WHICH TREE IS THIS (2026-10-23)?** This is `/mnt/storage/fpc-esp/fpc` —
> the **ESP-IDF 6.1 development line** of the FPC-on-ESP32 work (3 local
> commits on top of `bc94d466c9`: "Add/Finish ESP-IDF 6.1 FreeRTOS support";
> toolchain installs into `/mnt/storage/fpc-esp/fpc-bin`). The document body
> below is a snapshot of the **sibling workspace**
> `/mnt/storage/fpc-esp/../rewind-fpc-esp/AGENTS.md` (the ESP-IDF **5.2.8**
> line) and describes THAT workspace's layout, suite, and toolchain — treat
> it as background knowledge, not as a description of this tree. The
> authoritative in-tree knowledge for THIS tree: the FPC build recipe and
> its traps are in the sibling AGENTS.md §9 step 5 (same makefile system,
> use `SUBARCH=lx7hf`, native `ppcx64` bootstrap, `CROSSOPT='-XPxtensa-esp32s3-elf- -Cfhard'`,
> RTL needs `OPT=-CfHARD`), and the rewind patch series is handled via
> **[`pending-patches/`](./pending-patches/README.md)**: freertos-01
> (thread-stub events) and freertos-03 (InitInternational) are **already
> applied** (history section there); freertos-02 (tthread-raise) and
> xtensa-04 (finalize-order) remain **pending — apply ONLY when a program
> hits the deficiency each one fixes**; each patch documents its own
> discriminator test. Project charter (§2 rule 3 below applies verbatim):
> minimal fixes to unblock ESP32 support; never improve FreeRTOS support.

**State one-liner (2026-10-23):** working FPC → ESP32-S3 cross toolchain
(FPC trunk 3.3.1 @ commit `bc94d466c9` + ESP-IDF 5.2.8) with a 4-patch series
and a freertos regression suite at
**36 PASS / 0 CRASH / 0 COMPFAIL**. All programs route heap allocation
through the IDF pool via the `idfheap` unit; the static `-Ch` heap is
opt-in only. *(The two State paragraphs describe the sibling
rewind-fpc-esp workspace — kept for the knowledge they carry.)*

If you are an agent resuming work here: you do **not** need to rediscover
anything below — it is verified fact as of the date above. Start at
[§7 Pending decisions](#7-pending-decisions--next-moves) and
[§9 Reproduce](#9-reproduce-copy-paste-verified-2026-10-23) if you just want proof.

---

## 1. What this is, and why it exists

Free Pascal has a `freertos` target, and xtensa/esp32s3 support exists in
trunk, but the combination is work-in-progress upstream: non-trivial programs
(anything touching SysUtils/Classes) crashed at init or exit. This workspace
(`rewind-fpc-esp`) is a **self-contained, rebuildable toolchain + proof suite**
that makes trunk usable on the ESP32-S3 with the *smallest possible* patch set,
documents every bug found, and regression-tests each one.

Practical goal beyond bug-fixing: route FPC's memory manager to ESP-IDF's
`heap_caps_*` allocator (`idfheap` unit) so Pascal programs get the IDF heap
pool (~340 KiB free at start) instead of a compiler-baked static block, and —
later, pending — PSRAM.

## 2. Ground rules (violating these breaks things silently)

2. **`fpc-main` worktree stays pristine upstream.** The fixes exist ONLY as the
   4 `*.patch` files (see §4). After any build you may `git restore` the four
   files. `build-xtensa-esp32s3.sh` and the `/tmp/opencode/rebuild-*.sh`
   scripts are apply-or-refuse guarded: a build from an unpatched tree would
   resurrect every suite crash, so the guards run `reapply-patches.sh` or die.
   Exception: `rtl/freertos/heapmgr.pp` carries an uncommitted, default-off
   `{$ifdef fpc_HEAPTRACE}` diagnostic (see §8, trap list) — instrumentation
   only, not part of the patch series.
3. **Patches stay minimal.** One fix per patch file, no drive-by refactors,
   no "while we're in there". Threading contract is fixed: *"unit init passes,
   explicit thread use fails loud"* — do not implement real threads.
4. **Test programs from trunk get renamed + provenance.** See §6.
5. **`fpc.cfg` must NOT contain `-Ch`.** See §4, item 5, for why this was an
   "impossible-looking" constraint that got resolved.

## 3. Directory map

| Path | What it is |
|---|---|
| `fpc-main/` | FPC trunk checkout @ `bc94d466c9`. Kept pristine (rule 2). Patches + `reapply-patches.sh` + `build-xtensa-esp32s3.sh` live here. Needs `msgtxt.inc`/`msgidx.inc` copies in `compiler/` for a compiler rebuild (build script auto-fetches). |
| `fpc-cross/` | **The installed toolchain.** Cross compiler `lib/fpc/3.3.1/ppcrossxtensa` (this binary contains fix 4), RTL + package ppus under `lib/fpc/3.3.1/units/xtensa-freertos/`, and `lib/fpc/etc/fpc.cfg` (no `-Ch`; documents the policy). |
| `fpc-hello/` | Minimal demo + `qemu-s3-load.sh`. **`fpc-hello/tests/`** is the regression suite (see §6); `tests/thread-stubs/` the designed-failure demos; `tests/trace-repro/` the heapmgr trace-ledger repro; `tests/static-heap-repro/probe-idfmm.pas` the only program needing `-Ch65536`. |
| `blink-s3/` | The ESP-IDF 5.2.8 project that provides the SDK libs every FPC binary links against (`espidf_50200`, `libheap.a`). Must be built once (`idf.py build`) before any `compile-s3.sh` works. `sdkconfig.defaults` carries `CONFIG_ESP_MAIN_TASK_STACK_SIZE=8192`; future PSRAM config goes there. |
| `esp-idf-v5.2.8/` | ESP-IDF, local copy. There is also a stale `esp-idf-v5.5.2`/similar ~2 GB copy elsewhere on the user's disk awaiting a delete decision (see §7) — do not touch it either way without asking. |
| `compile-s3.sh` | Compile helper: `compile-s3.sh [extra fpc options] prog.pas`. Hardwires `-Tfreertos -WpESP32S3 -WP5.2.8`; forwards your options (later options win, which is how `-Ch1024`/`-Ch65536` overrides are done). Writes `.o/.elf/.bin/.img` next to the source. |
| `README.md` | Full toolchain/build narrative (deepest detail). Tests detail in `fpc-hello/tests/README.md`. This file is the distilled agent view. |

## 4. The problems — symptom → root cause → fix (why it is what it is)

All four fixes ship as `fpc-main/*.patch`, applied **in this order** by
`reapply-patches.sh` (01→04). Deep narratives with disassembly evidence are in
`README.md` §"FPC side".

1. **`freertos-01-thread-stub-events.patch`** (`rtl/freertos/systhrd.inc`)
   - *Symptom:* every `uses Classes` program died at unit-init (`RunError 232`).
   - *Cause:* upstream freertos threading is an admitted stub; *every* vector
     points at `NoThreadError`, but unit init legitimately calls
     `RTLEventCreate` (via `Classes.CommonInit`) and
     `BasicEventCreate` (via `TMultiReadExclusiveWriteSynchronizer.Create`).
   - *Contract fix:* benign for init/housekeeping — create → nil, destroy/set/
     reset → no-ops, critical sections stay upstream's single-task no-ops;
     loud for explicit use — all `*WaitFor` and thread creation/threadvar
     surface keep `RunError(232)`. `SyncObjs.TEvent.Create` raises
     `ESyncObjectException` (FCL rejects the nil handle); `TThread.Create`
     raises (patch 2). Demos: `tests/thread-stubs/`.
2. **`freertos-02-tthread-raise.patch`** (`rtl/freertos/tthread.inc`)
   - Upstream `TThread.SysCreate` silently incremented a counter — fake
     threading. Now raises a clear exception instead of pretending.
3. **`freertos-03-sysutils-initinternational.patch`** (`rtl/freertos/sysutils.pp`)
   - *Symptom:* `callx8` through a nil pointer, `PC=0`,
     `InstrFetchProhibited` — only on `AnsiCompare*`/`TStringList.Sort` paths,
     which nothing in the old suite exercised (found by the memory-manager
     probe).
   - *Cause:* freertos sysutils init calls only `InitExceptions`; unlike
     unix/os2/amicommon it never calls `InitInternational`, so the
     `widestringmanager` compare/text/upper/lower proc pointers stay nil.
   - *Fix:* define `InitInternational` (delegating to
     `InitInternationalGeneric` in `sysutils.inc`) + call it in the
     initialization section, exactly like `rtl/unix/sysutils.pp`.
   - **Upstream-report candidate.**
4. **`xtensa-04-finalize-order.patch`** (`compiler/xtensa/ncpuutil.pas`)
   - *Symptom:* all seven suite teardown crashes: use-after-free →
     `LoadProhibited` at `vmt+0x30`, deterministic in every program with a
     live `TStringList` at exit.
   - *Cause:* `FPC_FINALIZE_FUNC_TABLE` was generated iterating init/finalize
     entries **forward** — finalization ran in the *same* order as
     initialization. SysUtils finalized before Classes: `TEncoding`'s class
     destructor freed+unregistered the standard-encoding singletons, then
     `TStrings.Destroy`'s `IsStandardEncoding` guard saw the emptied list,
     returned false and freed the dead singleton. The static heapmgr's 12-byte
     free-list header made the corpse's VMT slot read back as 0.
   - *Fix:* emit the finalize list in reverse init order, per FPC's contract.
     NOTE: this fix lives in the **compiler** — the *installed* patched
     `ppcrossxtensa` bakes it into every program; no RTL involvement.
   - **Upstream-report candidate:** the identical forward iterate exists in
     `naarch64util.pas`, `narmutil.pas`, `navrutil.pas`, `nrv32util.pas`.
5. **Toolchain knowledge, no source change: the freertos heap & `-Ch`.**
   The freertos heapmgr's ONLY memory source is a static block whose size the
   compiler bakes in per program via `-Ch<bytes>` (`__heapsize` const +
   `__fpc_initialheap` BSS array). Without `-Ch` the size is 0 and
   registration is a no-op (NOT an immediate crash — only the first `GetMem`
   is, `RunError 203`). History: `-Ch65536` sat in `fpc.cfg` globally "and
   must stay" — resolved by the idfheap adoption (below): **`fpc.cfg` now
   carries no `-Ch` at all.** Default path = `idfheap` first in uses; static
   heapmgr = explicit per-program `-Ch` (later `-Ch` on the command line
   wins; verified `-Ch1024` → 0x400 block, `-Ch65536` → 0x10000, both
   runtime-valid).

### The upstream boundary — who to blame for what

So a future agent stops re-litigating solved questions: categorize the bug
**before** digging. Four buckets:

**A. Upstream FPC bugs, fixed HERE via the patch series (still broken
upstream until reported — see §7 item 1):**
- unit-finalization order (`ncpuutil.pas` forward iterate; same bug copied
  into the aarch64/arm/avr/riscv generators) — patch `xtensa-04`.
- freertos sysutils missing `InitInternational` → nil `widestringmanager`
  proc pointers — patch `freertos-03`.
- freertos threading = stub-with-fatal-vectors; `TThread` = silent fake
  counter — patches `freertos-01/-02`. These are *design* patches: the
  "benign init / loud explicit use" contract is **our policy**, an honest
  local stance for a single-task single-RTL-thread MCU — expect discussion,
  not automatic upstream adoption as-is. Scope note: this loudness is for
  the **Pascal** thread API; OS-level threads through raw FreeRTOS
  externals (`xTaskCreatePinnedToCore`) work and are the supported escape
  hatch — rules in §10.7. Upstream's own `$WARNING "only a stub, and will
  not work!"` in `rtl/freertos/tthread.inc:18` still stands in our tree —
  we deliberately left it; upstream remains honest about the stub.
- Rule of thumb: a runtime crash at **unit init or exit** that touches
  Classes/SysUtils usually maps to bucket A — check §4 items 1–4 first.

**B. Upstream bugs, real, NOT fixed here — out of scope on purpose:**
- `tw16315b`: compiler const-folding evaluates `Infinity` under
  `{$ieeeerrors+}` with its own range check → spurious *compile error*
  `Range check error while evaluating constants` (archived as COMPFAIL;
  then removed as not applicable). A **compiler** (arith constant folding
  shared with i386/x86_64 paths) fix — beyond this workspace's
  minimal-patch scope; report upstream rather than patch casually.
- `tw3721`: needs `heaptrc`/debug-heap unit (`HaltOnNotReleased`);
  heaptrc is not built for xtensa-freertos — a missing-unit **feature
  gap** of the target, not a mismatch in anything we ship.
- Boundary rule: if the failure is at **compile time** in code the target
  RTL never sees (const folding, unavailable units), it is bucket B —
  removing/skipping the test is the right local move, upstream report the
  second half.

**C. Upstream observations recorded, no action needed:**
- `system.pp`'s `{$ifdef FPC_HAS_FEATURE_THREADING}` / `{$endif}` carry
  stray spaces and collapse into comments — behaviorally inert for
  freertos today because `rtl/freertos/system.cfg` enables `-SfTHREADING`
  in all profiles; if that ever changes, `uses Classes` breaks at init
  (the exact crash that motivated `freertos-01`).
- freertos target immaturity generally: no heaptrc, no real threads, no
  `msg2inc` cross-build hygiene (`-Cplx7hf` pollutes host-tool compiles;
  our `build-xtensa-esp32s3.sh` copies pre-generated `msgtxt.inc`/
  `msgidx.inc` instead), fpmake timestamp-only dependency tracking (hence
  the package wipe step in every RTL rebuild).

**D. NOT upstream — bugs in this workspace's own code, fix here:**
`idfheap.pp` (ours, load-bearing details in §5), the suite files and
runner, thread-stub demos, `fpc.cfg` policy, `compile-s3.sh`. If a crash
reproduces only with our files involved (e.g. the mid-run manager swap in
`static-heap-repro/`), suspect us first, upstream second.

Quick triage: **compile-time** failure → buckets B/C (+ our fpc.cfg
policy); **unit-init/exit** crash → bucket A; **mid-run** misbehavior →
D first, then A; **link-time** missing IDF symbol → our
externals/blink-s3 build, not upstream.

## 5. The memory-manager architecture (idfheap) — why test sources look the way they do

**Every runtime-tested program has `idfheap` FIRST in its `uses`** (all 35
suite webtbs tests incl. the 2 compile-only, `probe-enc`, `probe-idfheap`,
`idfheap-smoke`, and the 3 `thread-stubs/` demos — `idfheap.pp` is copied into
`thread-stubs/` so the unit resolves there). Only the compile-only
`u_generics_pubsub_events.pas` is untouched (never runs).

What that buys: all allocations — from the first unit init onward (~27 KB of
sysutils/classes init objects) — land in IDF's `MALLOC_CAP_8BIT|DEFAULT` pool
via `heap_caps_malloc/free/realloc`; no BSS reservation; `__fpc_initialheap`
is a 4-byte symbol instead of 64 KiB. `GetHeapStatus`/`GetFPCHeapStatus`
report real `heap_caps_get_info` numbers. Fail policy mirrors heapmgr (`nil`
when `ReturnNilIfGrowHeapFails`, else `RunError 203`).

Non-obvious load-bearing details (all hit the hard way during bring-up —
do not "simplify" them away):
- `idfheap`'s own `uses heapmgr` is **load-bearing**: it pins init order
  heapmgr → idfheap → sysutils → typinfo → classes, so heapmgr's unit init
  (which would otherwise run *later* and `SetMemoryManager(static)`) can never
  overwrite the IDF manager. Observed init order: system → consoleio →
  heapmgr → idfheap → sysutils → …
- `TMemoryManager.ReAllocMem` must write `p` **in place** (`p := result`),
  mirroring `SysReAllocMem` — the grand wrapper in `rtl/inc/heap.inc` does
  not. Missing this killed `TList.Insert` (`StoreProhibited`, `FItems=nil`)
  and would break `TFPList.SetCapacity`.
- Static-block-owned pointers (only possible in the hot-swap scenario) are
  delegated to the captured static manager **even for `Size = 0`**; sending a
  static-heap pointer to `heap_caps_free` aborts in IDF's multi-heap
  (`assert failed: <cached disabled>`).
- **`probe-idfmm` (now `tests/static-heap-repro/`) is the one exception** to
  "everything idfheap": its whole point is installing the IDF manager
  *mid-run*, after sysutils/classes already initialized on the static heap —
  so it structurally requires `-Ch65536` (under `-Ch0`, sysutils' own init
  allocations would `RunError 203` before the swap). It is out of the
  default suite for that reason, with its own README + exact commands.
- `heapmgr` itself is still exercised at runtime only by that probe's
  pre-swap allocations + the trace-ledger repro; the default suite never
  touches it. If you change `rtl/freertos/heapmgr.pp`, run
  `static-heap-repro` (needs rebuild, see §6) and `trace-repro` flows.

## 6. The test suite — taxonomy, provenance, current state

- 33 programs renamed from trunk `tests/webtbs/twXXXX.pas` to descriptive
  `t_<topic>_<what>.pas` (compile-only unit gets `u_`). Provenance is kept
  **twice**: a `{ webtbs provenance: trunk tests/webtbs/twXXXX.pas }` comment
  on line 1 of every renamed file, and the mapping table in
  `tests/README.md`. Internal `program`/`unit` identifiers are aligned.
- Runner is generic (`*.pas` glob); verdict = compile, then 15 s QEMU boot
  with no `Guru|panic|Backtrace|Runtime error|SIGILL|LoadProhibited|StoreProhibited`
  in serial. Per-test logs: `<name>.clog`, `<name>.qemu.log`.
- **Canonical last run: 36 PASS / 0 CRASH / 0 COMPFAIL** = `/tmp/opencode/
  suite-final9.txt`. Two former COMPFAILs were **removed as not
  applicable** (do NOT re-add them when syncing from trunk — the
  "Removed as not applicable" note in `tests/README.md` has the reasons:
  tw16315b = trunk const-folding range check under `{$ieeeerrors+}`, a
  compiler bug unreachable by RTL patches; tw3721 = needs the `-gh`
  heaptrc unit, unavailable for xtensa-freertos).
- Heap demand is tiny (max 2.6 KiB peak, `t_generics_dictionary_recordkey`;
  pure math tests peak at 112–136 B = consoleio's output buffer; LIVE=0 at
  exit on every test) — historic numbers from the static-heap era, allocation
  volumes are manager-independent.
- Rules when adding a trunk test: rename per above, add the provenance line,
  add `idfheap` FIRST in uses (or, if the test must exercise the static heap,
  do not add idfheap and give it an explicit `-Ch` — but then it cannot run
  in the default suite; the runner has no per-test flags).
- Thread demos live OUTSIDE the PASS/CRASH stats (their failures are
  designed): see §5 and `tests/thread-stubs/README.md`.

## 7. Pending decisions / next moves

These are *awaiting user input* — do not act unilaterally:
1. **Upstream reports** (bugtracker/email to fpc-devel): (a) forward-iterate
   finalize-table generators (xtensa + aarch64/arm/avr/riscv, patch 4), (b)
   freertos sysutils missing `InitInternational` (patch 3). The analysis text
   in `README.md` §4 items is report-ready.
2. **SPIRAM path**: `CONFIG_SPIRAM=y` (+`CONFIG_SPIRAM_MODE_OCT`) in
   `blink-s3/sdkconfig.defaults`, `idf.py build`; `idfheap` already routes via
   `heap_caps_*` so PSRAM appears through IDF config
   (`CONFIG_SPIRAM_USE_MALLOC`) with no Pascal-side change. Then probe with a
   multi-MB alloc + checksum. **QEMU status (verified 2026-10-23): the
   installed QEMU (`~/.espressif/tools/qemu-xtensa/esp_develop_9.2.2_20260417`)
   *has* an S3 PSRAM device model** — `-device ssi_psram,cs=0,is_octal=<bool>,size_mbytes=<n>`
   (incl. octal, `psram_octal_*` code) — so end-to-end emulation is plausible;
   only the actual boot with a SPIRAM-enabled sdkconfig has not been
   exercised yet. See also §10 (ESP32 experience) for how to detect/force
   PSRAM at runtime.
3. **Delete the ~2 GB duplicate IDF copy** (`esp-idf-v5.5.2`): user decision.
4. **`heapmgr.pp` FPC_HEAPTRACE diagnostics**: kept as opt-in instrumentation,
   uncommitted. Keep or strip — user decision (stripping retires the
   trace-ledger repro path in `tests/trace-repro/`).

## 8. Traps & lessons (each one actually burned us)

- **`/tmp/opencode/*.sh` scripts need `sh script.sh`, not direct exec.**
- **Runner glob is generic** — test renames need no runner change, but stale
  `.clog/.qemu.log` of old names must be deleted or they mislead.
- **`-Ch` interacts with the *default* manager only.** idfheap programs never
  touch the static block; never put `-Ch` back into `fpc.cfg` "for safety".
- **fpmake only tracks source timestamps** — after any RTL rebuild you MUST
  wipe `find packages -type d -path '*units/xtensa-freertos' -prune -exec
  rm -rf {} +` and rebuild packages, or stale ppus mask your change.
- **rtl Makefile feeds only the system unit with `@system.cfg`;** feature
  switches (`-Sf…`) are only accepted for the system unit and propagate via
  checksums. `fcl-base`'s syncobjs needs `THREADING` enabled in all profiles
  (hence patch 2 rather than disabling the feature).
- **Compiler rebuild** needs `msgtxt.inc`/`msgidx.inc` (copied from the
  bootstrap tree when missing by the build script) and the toolchain `bin/`
  in PATH; building host tools chokes on `-Cplx7hf` pollution otherwise.
- **Patch verification method** (used, reproducible): `git archive HEAD` →
  fresh `git init` → `git apply` the 4 patches in order → diff against the
  worktree → content-identical (CRLF warnings from archive extraction are
  benign). Re-verified 2026-10-23 after re-pristining the worktree:
  reapply from pristine reproduces byte-exact diffs.
- **Symbolization**: `~/.espressif/tools/xtensa-esp-elf/esp-13.2.0_20250707/
  xtensa-esp-elf/bin/xtensa-esp32s3-elf-{nm,objdump,addr2line}` on the
  program's `.elf` (QEMU crash PCs/registers come from the serial log).
- **Trace reproduction** for heap teardown analysis: RTL with
  `-dfpc_HEAPTRACE` via `sh /tmp/opencode/rebuild-rtl-trace.sh`; back to
  normal with `sh /tmp/opencode/rebuild-rtl.sh` + `sh
  /tmp/opencode/rebuild-pkgs.sh`. Trace output requires the uncommitted
  `heapmgr.pp` instrumentation (§2 rule 2 exception).
- **IDF symbols are already linked into every binary** via
  `espidf_50200`/`libheap.a` — just declare externals and call
  (`heap_caps_malloc/free/realloc/get_allocated_size/get_info`). Caps:
  `8BIT=1 shl 2`, `SPIRAM=1 shl 10` (currently OFF), `INTERNAL=1 shl 11`,
  `DEFAULT=1 shl 12`.

## 9. Reproduce (copy-paste), verified 2026-10-23

```sh
# 0) full regression suite (≈2 min):
cd /mnt/storage/rewind-fpc-esp/fpc-hello/tests && ./run-tests.sh
#    expect: 36 PASS / 0 CRASH / 0 COMPFAIL (see §6)

# 1) one test subset:
cd /mnt/storage/rewind-fpc-esp/fpc-hello/tests && ./run-tests.sh 't_generics*.pas'

# 2) thread-stub demos (run manually — the runner's relative qemu path
#    breaks in subdirs; use absolute):
cd /mnt/storage/rewind-fpc-esp/fpc-hello/tests/thread-stubs
for t in t_cs_noop t_event_waitfor t_thread_create; do
  /mnt/storage/rewind-fpc-esp/compile-s3.sh $t.pas &&
  timeout 10 /mnt/storage/rewind-fpc-esp/fpc-hello/qemu-s3-load.sh "$PWD/$t.elf"
done
#    expect: "cs ok ..." | "...as designed: ESyncObjectException" |
#            "...as designed: Exception (TThread stub)" — all three shown.

# 3) the static-heap hot-swap probe (the ONLY program needing -Ch):
cd /mnt/storage/rewind-fpc-esp/fpc-hello/tests/static-heap-repro
/mnt/storage/rewind-fpc-esp/compile-s3.sh -Ch65536 probe-idfmm.pas
timeout 15 /mnt/storage/rewind-fpc-esp/fpc-hello/qemu-s3-load.sh "$PWD/probe-idfmm.elf"
#    expect: alloc @3FC9Cxxx static block / @3FCB3xxx IDF pool ... OK, exit 0

# 4) patch round-trip on the pristine worktree:
cd /mnt/storage/rewind-fpc-esp/fpc-main
git diff --name-only HEAD | grep -v heapmgr   # must print nothing
sh reapply-patches.sh                         # 4x "patch applied"
git diff --name-only HEAD                     # now the 3 RTL files + ncpuutil.pas
#    (optionally verify byte-exactness, then:)
git restore rtl/freertos/systhrd.inc rtl/freertos/tthread.inc \
            rtl/freertos/sysutils.pp compiler/xtensa/ncpuutil.pas

# 5) full rebuild chain (patches auto-apply-or-refuse; scripts must be `sh`-run):
sh /tmp/opencode/rebuild-rtl.sh        # RTL (installs into fpc-cross)
sh /tmp/opencode/rebuild-pkgs.sh       # packages (after wiping unit dirs)
#    compiler rebuild (only when compiler sources change):
cd /mnt/storage/rewind-fpc-esp/fpc-main && sh build-xtensa-esp32s3.sh

# 6) single-program sanity:
cd /mnt/storage/rewind-fpc-esp/fpc-hello
/mnt/storage/rewind-fpc-esp/compile-s3.sh hello-s3.pas
timeout 15 ./qemu-s3-load.sh "$PWD/hello-s3.elf"
```

## 10. ESP32(-S3) Pascal experience — writing high-quality code for this target

This section is distilled, **verified** experience so the next agent starts
already knowing how to write good Pascal for the ESP32-S3 in this toolchain.
Every number below was read from the local IDF 5.2.8 headers or measured in
this workspace (not recalled from memory).

### 10.1 The memory model you inherit

| Region | Address window (verified: `components/soc/esp32s3/include/soc/soc.h`) | Role |
|---|---|---|
| Data SRAM (internal) | `0x3FC88000 – 0x3FD00000` (`SOC_DRAM_LOW/HIGH`) | Where **everything runs by default**: Pascal heap (RTOS stacks, IDF internals, FPC static data). Observed IDF pool for our programs: `3FCAD3A8..3FCE9710`. ~340 KiB free at program start. |
| Instruction SRAM | `0x40370000 – 0x403E0000` (`SOC_IRAM_LOW/HIGH`) | IRAM. Drivers/ISRs; FPC programs don't place code here explicitly. |
| External cache window | `0x3C000000 – 0x3E000000` (`SOC_EXTRAM_DATA_LOW/HIGH`) | Cache-mapped **flash data (DROM) *and* PSRAM** both live here — the window alone does *not* tell you which one a pointer is in (see 10.2). |
| Flash instruction | `0x42000000`+ | XIP flash code. |

Consequence for everyday Pascal code: an ESP32-S3 "DRAM pointer" you print
will look like `3FCxxxxx`/`3FCExxxx`-ish; once PSRAM is enabled and in use,
PSRAM-backed pointers appear in the `0x3Cxxxxxx/0x3Dxxxxxx` range. **Don't
write code that hardcodes these ranges** — use the checks in 10.3 — but do
use them when *reading* logs (instant orientation: 3FC… = internal SRAM,
3C/3D… = cache window [flash data or PSRAM]).

### 10.2 Dynamic allocation: the `idfheap` way

- **Write Pascal exactly as usual** — `GetMem`, `New`, `SetLength`,
  `AnsiString`/DynamicArray ops, `TObject`/`TStringList`/generics — all of it
  flows through `idfheap` → `heap_caps_*`. No special "embedded style" is
  needed; that is precisely what the routing bought us.
- **`uses idfheap` must be FIRST in the uses clause** of any program that does
  dynamic allocation (or even `writeln` — consoleio allocates). Not first →
  heapmgr's static manager (empty without `-Ch`) wins and the first GetMem is
  `RunError 203`. The compiler error for a *later* idfheap is only visible at
  runtime, so always eyeball the uses order when reviewing code.
- **Never assume memory exists.** Check `heap_caps_get_largest_free_block`
  before growing a big dynarray/TStringList unboundedly; the pool is `~340 KiB`
  internal SRAM today, up to MBs with PSRAM later. `idfheap` fails *loud and
  deterministic* (`RunError 203`, or `nil` only if the program itself set
  `ReturnNilIfGrowHeapFails := true`) — an OOM is a clean answer, not a Guru.

### 10.3 PSRAM: does it exist, is it there, can I force it

Allocation caps (verified in `esp_heap_caps.h`, and correct for externals):
`MALLOC_CAP_8BIT = 1 shl 2`, `MALLOC_CAP_SPIRAM = 1 shl 10`,
`MALLOC_CAP_INTERNAL = 1 shl 11`, `MALLOC_CAP_DEFAULT = 1 shl 12`.

Answer the three questions like this:

1. **"Does PSRAM exist on this build?"** — call
   `heap_caps_get_free_size(MALLOC_CAP_SPIRAM or MALLOC_CAP_8BIT)`(declared
   external as in `probe-idfheap.pas`; `0` = off) or
   `esp_psram_get_size` if linked. `tests/probe-idfheap.pas` already prints
   both free sizes + largest internal block — run it, read the log.
2. **"Did *this pointer* land in PSRAM?"** — the definitive check is
   `esp_ptr_external_ram(p)` (declared
   `function esp_ptr_external_ram(p: pointer): boolean; external name 'esp_ptr_external_ram';`).
   It is **PSRAM-specific**: internally it is `esp_psram_check_ptr_addr()`
   against the runtime-discovered mapped PSRAM regions, and it returns `false`
   when `CONFIG_SPIRAM` is off (verified source:
   `components/esp_hw_support/esp_memory_utils.c:76`,
   `components/esp_psram/esp_psram.c:341`). Do **not** hand-roll
   `p >= 0x3C000000` range tests — that window also holds flash DROM data.
   A raw range check is acceptable *only* as a log-orientation aid.
3. **"I want a large buffer in PSRAM *specifically*"** — don't rely on the
   default manager's luck; allocate with caps:
   `buf := heap_caps_malloc(n, MALLOC_CAP_SPIRAM or MALLOC_CAP_8BIT);`
   `nil` when PSRAM is off/smaller than n (check before use, always). Free
   with `heap_caps_free(buf)`. To make the *default* Pascal heap prefer PSRAM
   for big blocks, enable `CONFIG_SPIRAM_USE_MALLOC` in sdkconfig (with
   `CONFIG_SPIRAM_MALLOC_ALWAYSINTERNAL` threshold) — `idfheap` needs no
   changes and ~all Pascal allocations become PSRAM-eligible automatically.

Where for **what**: PSRAM is FPC's dream medium — big strings, dynarrays,
object graphs, maps, image/audio blobs; access is transparent to Pascal code.
But mind 10.4.

### 10.4 What PSRAM can and cannot do (hardware rules, S3)

- **Slow relative to SRAM** (~several× latency, cache-line granularity):
  keep hot loop state, small per-iteration data, and anything time-critical
  internal (`MALLOC_CAP_INTERNAL` or just small default allocations).
- **Not fault-preserving**: do **not** touch PSRAM from ISRs, NMIs, panic
  handlers, or while the flash cache is disabled (flash write/erase windows).
  During those windows external memory is unreachable — data access there
  faults or misbehaves. Rule: static/ISR/exception-path data stays internal.
- **DMA**: S3's GDMA *can* read/write PSRAM through the cache, with
  alignment requirements (IDF's own `async_memcpy_gdma.c` switches
  `psram_trans_align` based on `esp_ptr_external_ram`). Quality rule for an
  agent: **DMA buffers default to internal RAM** unless the specific driver
  documents PSRAM support — and keep the buffer 4-byte aligned minimum.
- **Task stacks**: external stacks are only possible with
  `CONFIG_SPIRAM_ALLOW_STACK_EXTERNAL_MEMORY` (off in our sdkconfig; and the
  FPC RTL has exactly one task anyway). Do not try to move the main-task
  stack to PSRAM.
- **Executability**: S3 hardware even supports XIP **from** PSRAM
  (`SOC_SPIRAM_XIP_SUPPORTED=y` in our sdkconfig) — but this toolchain places
  Pascal code in flash/IRAM as usual; don't engineer around it.
- **Persistence**: not across power cycles, not guaranteed across soft
  reboots. Allocate and initialize every run.

### 10.5 RTOS/stack limits that shape good Pascal code here

- **One task. Threading is loud**, by contract: `BeginThread`/`TThread.Create`
  → exception; `TEvent.WaitFor` etc. → `RunError 232`. Write single-task,
  non-blocking code. A long compute loop starves the RTOS idle housekeeping —
  our suite's compute tests are seconds-bounded and fine; if you ever add an
  unbounded loop, yield (declare `procedure vTaskDelay(t: uint32); external;`
  style externals from espidf) rather than spinning.
- **The Pascal stack = the IDF main task stack** = 8192 bytes
  (`CONFIG_ESP_MAIN_TASK_STACK_SIZE` in `blink-s3/sdkconfig.defaults`; raised
  from the 3584 default once, to fix a crash). Deep recursion or large local
  arrays → stack overflow → Guru `LoadProhibited/StoreProhibited`. Budget in
  kilobytes, not megabytes; allocate big things on the heap.
- Every binary ships the IDF glue (`espidf_50200`, `libheap.a`) — you pay
  nothing extra to call `heap_caps_*`/esp functions by declaring externals.
- `writeln` costs a dynamically-allocated console write buffer (~112 B
  observed) per program — keep that in mind when a "tiny" program surprises
  you with allocations: it is consoleio, not a leak.

### 10.6 QEMU facts (verified 2026-10-23, QEMU 9.2.2 esp_develop_9.2.2_20260417)

- The installed QEMU has a **real PSRAM device model** for the esp32s3
  machine: `-device ssi_psram,cs=0,is_octal=<bool>,size_mbytes=<n>`
  (defaults cs=0, is_octal=false, 4 MB; octal PSRAM supported). Not yet
  exercised end-to-end with a `CONFIG_SPIRAM` sdkconfig (§7 item 2).
- 15 s wall-clock cap per boot in the suite runner is enough for every suite
  program under QEMU.
- ESC/ANSI control sequences and Guru text appear verbatim in the serial log;
  symbolize crashes with `xtensa-esp32s3-elf-addr2line`/`nm` on the `.elf`
  (paths in §8).

### 10.7 The threading escape hatch: real tasks via FreeRTOS externals

The §4-A contract governs the **Pascal** thread API (`TThread`,
`BeginThread`, `TEvent.WaitFor` → exception / `RunError 232`). But the ESP32-S3
runs a real, dual-core FreeRTOS underneath, and Pascal can drive it directly
by declaring externals — no RTL threading involved. This is the legitimate
way to get parallelism in this toolchain:

```pascal
type
  TTaskFn = procedure(arg: pointer); cdecl;   { TaskFunction_t = void(*)(void*) }

function xTaskCreatePinnedToCore(fn: TTaskFn; name: pchar; stackDepth: uint32;
  param: pointer; prio: uint32; handle: ppvoid; coreId: longint): longint;
  cdecl; external name 'xTaskCreatePinnedToCore';
{ worker ends itself: vTaskDelete(xTaskGetCurrentTaskHandle()) }

procedure Worker(arg: pointer); cdecl; ... end;
begin
  if xTaskCreatePinnedToCore(@Worker, 'worker', 4096, nil, 5, nil, 1) <> 0 then ...
end.
```

Verified signatures (all in `esp-idf-v5.2.8/components/freertos/FreeRTOS-Kernel/include/freertos/task.h`):
- `stackDepth` is in **BYTES** — `task.h:315` literally says *"NUMBER OF
  BYTES. Note that this differs from vanilla FreeRTOS"*
  (`configSTACK_DEPTH_TYPE = uint32_t`, `FreeRTOSConfig.h:123`).
- **But `uxTaskGetStackHighWaterMark` returns WORDS** (`task.h:1509`) — the
  asymmetry is the trap; divide by 4 when comparing against stackDepth.
- cores are `0`/`1`, or `tskNO_AFFINITY = 0x7FFFFFFF` (`task.h:206`) for no
  pinning; S3 has two cores.
- Stack sizing: start ≥ 4096 and tune with the high-water mark (a Pascal
  worker with strings/objects uses several KB).

The rules that make this safe (and the traps that don't):

- **The memory manager is task-safe; the objects layer is not.** `idfheap`
  wraps `heap_caps_malloc/free/realloc`, which are IDF-internally locked
  (verified multi-heap) — `GetMem`/`FreeMem`/`SetLength` from two tasks won't
  corrupt the heap. But `TStringList`, containers, `TList` etc. have **no
  locks** (no `IsMultiThread`, no imc-style critical sections in this RTL):
  share objects only through FreeRTOS primitives you own:
  `xSemaphoreCreateMutex/Take/Give`, `xQueueCreate/xQueueSend/xQueueReceive`
  (+ `*FromISR` variants from actual ISRs).
- **Pascal `threadvar` is non-functional — loud, at access.** The RTL's
  `RelocateThreadVar`/`AllocateThreadVars` vectors point at `NoThreadError`
  → `RunError 232` at first touch (verified `rtl/freertos/systhrd.inc`). So
  no per-thread storage exists at the FPC level even for worker tasks:
  give a task its state via the `param` pointer (heap-allocated record),
  pass results through queues/pointers, and do not use `threadvar`.
- **Worker/task functions must be `cdecl`** (FreeRTOS calls them through C).
- **Exceptions in worker tasks: unproven path.** `try/finally` is fine to
  test, but do not *rely* on raising/catching exceptions inside a task —
  the exception machinery's stack/handler assumptions were only validated on
  the main task. Prefer: worker never raises; communicates failure in a
  queue message.
- **Exit discipline:** unit finalization and the manager teardown run on the
  main task at program end. Do not leave a worker still running into
  teardown: end the program only after the worker self-deletes (quit flag +
  `xQueueReceive`/queue timeout on the main side, or keep the worker handle
  and `vTaskDelete` it before returning).
- **`writeln` from two tasks interleaves** at the consoleio/UART level
  without any lock; guard with a mutex if ordering matters.
- Distinguish **task** (`xTaskCreatePinnedToCore`, normal priority) from
  **ISR**: a Pascal routine called directly by an ISR must be minimal, use
  `*FromISR` API variants, and never touch PSRAM (§10.4).

Also worth noting for code review: the loud-failure contract (§4-A) is a
property of the RTL's *thread API layer*; using raw FreeRTOS externals
bypasses that layer deliberately. That is fine for architecture-quality
code — just keep the loud semantics for the Pascal API (don't weaken
patch `freertos-01` into a silent no-op because "threads exist anyway";
the jobs that break at `RTLEventWaitFor` genuinely can't work here).

### 10.8 One-paragraph code review checklist for this target

Before approving a Pascal program for the ESP32-S3 in this tree:
`idfheap` first in uses? big allocations sanity-checked against
`heap_caps_get_free_size`/`largest_free_block`? no Pascal-level
threads/waitfor (raw FreeRTOS tasks only, per §10.7: `cdecl` workers,
no `threadvar`, shared objects behind a mutex, workers finished before
exit)? no deep recursion or multi-KB locals? ISR/panic-safe data kept
internal? DMA buffers internal + aligned unless proven otherwise?
externals declared with exact IDF signatures (`espidf_50200`)? if PSRAM
is used: existence checked (`nil` handled) and hot paths kept internal?
If all yes → it will boot in QEMU and on hardware with exit code 0.

## 11. Where the deep detail lives

- Root `README.md` — build history, all five fixes with evidence chains,
  `-Ch` semantics, worktree policy.
- `fpc-hello/tests/README.md` — suite structure, rename mapping table,
  per-crash root-cause table, heap measurements, idfheap unit details.
- `fpc-hello/tests/{static-heap-repro,trace-repro,thread-stubs}/README.md` —
  per-repro purpose + exact expected output.
- `/tmp/opencode/suite-final8.txt` — canonical suite table.
- **`/tmp` is volatile**: if the `/tmp/opencode/rebuild-*.sh` scripts are
  gone, reconstruct from README.md's rebuild notes (the commands in §9 step 5
  mirror them).
