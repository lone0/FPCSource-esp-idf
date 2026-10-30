# AGENTS.md — read me first (for AI agents, and humans too)

**This tree:** Free Pascal trunk 3.3.1 with **ESP-IDF 6.1** FreeRTOS support
for ESP32-S3 (Xtensa) and ESP32-S31 (RISC-V ILP32F).

**Public branch:** `esp-idf-6.1-s3/s31` — the only active line for this work
(freertos-01/03, xtensa-04 + RISC-V reverse finalize, ILP32F, trimmed IDF 6.1
`$linklib` sets). Do not document or steer work onto other named branches.

Do **not** edit the upstream root `README.md`. Authoritative in-tree agent
docs: this file and [`pending-patches/`](./pending-patches/README.md).

---

## 1. What this is

Upstream FPC has a `freertos` target and ESP32 controller support, but
non-trivial programs (anything touching SysUtils/Classes) historically
crashed at init or exit. This line carries the **smallest** set of fixes
needed to run ESP-IDF 6.1 images on ESP32-S3 and ESP32-S31.

## 2. Ground rules

1. **Patches stay minimal.** One deficiency per change, no drive-by
   refactors. Goal: unblock ESP32-family support — never “improve FreeRTOS
   support” for its own sake.
2. **Threading contract:** *unit init passes, explicit thread use fails
   loud.* Do not implement real Pascal threads. Benign event create /
   destroy / set / reset for Classes housekeeping; all `*WaitFor` and
   thread-create / threadvar vectors stay `RunError(232)` / raise.
3. **Pending patches are gated.** See
   [`pending-patches/README.md`](./pending-patches/README.md). Apply
   freertos-02 only when a program hits its deficiency. Run
   `git apply --check` first.
4. **RTL `.inc` rebuild trap.** The RTL makefile does not track `.inc`
   includes. After changing `systhrd.inc` (or similar), wipe
   `rtl/units/xtensa-freertos` and/or `rtl/units/riscv32-freertos` and
   rebuild clean — otherwise `Internal error 2026032615`.
5. **Do not pass `OS_TARGET=freertos` to `make -C compiler`.** Only to
   `make -C rtl`.
6. **Finalize-order fixes live in the compiler.** After changing
   `ncpuutil.pas` / `nrv32util.pas`, rebuild the matching cross compiler
   (`ppcxtensa` / `ppcrv32`); the fix is baked into every program it emits.

## 3. Freertos / Classes deficiencies (this line)

Tracked under `pending-patches/`. On this line (`esp-idf-6.1-s3/s31`):
freertos-01, freertos-03, and **xtensa-04 are applied**; only freertos-02
remains pending.

1. **freertos-01 — thread-stub events** (`rtl/freertos/systhrd.inc`) — **APPLIED**
   - *Symptom:* every `uses Classes` program died at unit init (`RunError 232`).
   - *Cause:* upstream freertos threading is a stub; every vector pointed at
     `NoThreadError`, but Classes init legitimately calls `RTLEventCreate` /
     `BasicEventCreate` (+ reset).
   - *Fix:* create → nil; destroy/set/reset → no-ops; WaitFor / thread APIs
     stay loud.

2. **freertos-02 — TThread raise** (`rtl/freertos/tthread.inc`) — **PENDING**
   - Upstream `TThread.SysCreate` silently fakes a thread. Patch makes
     `TThread.Create` raise. Apply when a program creates `TThread`.

3. **freertos-03 — InitInternational** (`rtl/freertos/sysutils.pp`) — **APPLIED**
   - *Symptom:* nil `widestringmanager` compare procs → `PC=0` /
     `InstrFetchProhibited` on `AnsiCompare*` / `TStringList.Sort`.
   - *Cause:* freertos SysUtils init called only `InitExceptions`.
   - *Fix:* call `InitInternational` → `InitInternationalGeneric` (same as
     unix). Upstream-report candidate.

4. **xtensa-04 — finalize order** (`compiler/xtensa/ncpuutil.pas`) — **APPLIED**
   (2026-10-24)
   - *Symptom (Xtensa):* use-after-free at exit with a live `TStrings`
     (SysUtils finalized before Classes → dead `TEncoding` singleton).
   - *Fix:* emit finalize calls in a **separate reverse pass** over the
     init/finalize table (FPC last-initialized-first-finalized contract).
   - *Verified (ESP32-S3, QEMU + hardware):* linked finalize order is
     `CLASSES → TYPINFO → SYSUTILS → OBJPAS → CONSOLEIO`; canaries with
     live `TStrings` exit clean. Upstream-report candidate (same forward
     iterate in aarch64/arm/avr/riscv generators).
   - *S31 note:* this file is **Xtensa-only**. RISC-V needs the same
     contract in `compiler/riscv32/nrv32util.pas` (see §5.6).

### Triage quick guide

- Crash at **unit init** touching Classes → check freertos-01.
- Crash on **AnsiCompare / Sort** → check freertos-03.
- Crash at **Xtensa exit** with live `TStrings` → should be fixed by
  xtensa-04 on this base; rebuild `ppcxtensa` if an old compiler binary.
- Crash at **S31 / RISC-V exit** after Classes work → apply/verify the
  `nrv32util.pas` reverse-finalize change and rebuild `ppcrv32` (§5.6).
- Want Pascal `TThread` → freertos-02 (still loud / raise, not real threads).
- Want real concurrency → FreeRTOS C API via `cdecl` externals
  (`xTaskCreatePinnedToCore`, …); do not weaken freertos-01.

## 4. ESP32-S3 notes (IDF 6.1 / this tree)

- Controller: `-Wpesp32s3 -WP6.1`, subarch `lx7hf`, hard float (`-Cfhard` /
  `OPT=-CfHARD` on RTL as required by this tree’s build).
- Compiler: `compiler/ppcxtensa` (must include applied xtensa-04).
  RTL: `rtl/units/xtensa-freertos`.
- IDF 6.1 on S3 uses picolibc for the app image; match the C link set from
  a built IDF project (keep-alives and `$linklib` lists live in
  `rtl/freertos/xtensa/espidf_60100.pp` / `compiler/systems/t_freertos.pas`).
- Emulator commonly used with this line: Espressif QEMU xtensa
  (`qemu-system-xtensa`, machine `esp32s3`). Prefer the toolchain version
  that ships with the IDF 6.1 install.

## 5. ESP32-S31 (RISC-V ILP32F) — build, link, and run

Verified on ESP-IDF **v6.1**, Espressif gcc **15.2.0_20251204**,
`esp-emu` **0.50.0**, on branch **`esp-idf-6.1-s3/s31`**.

Placeholders:

| Name | Meaning |
| --- | --- |
| `$FPC_SRC` | This repository root (the FPC source tree) |
| `$FPC_PREFIX` | **Install prefix** — directory you pass to `make install PREFIX=…` (or equivalent). Holds the installed cross compiler under `lib/fpc/<version>/` and units under `lib/fpc/<version>/units/…`. Choose any writable location; there is no required host path. |
| `$IDF_PATH` | ESP-IDF v6.1 checkout |
| `$IDF_PROJECT` | An `idf.py` project with `CONFIG_IDF_TARGET=esp32s31` |
| Espressif tools | Wherever `./install.sh` / `idf_tools.py` placed the RISC-V gcc (override with `IDF_TOOLS_PATH` if non-default) |

You may also drive builds from the **in-tree** binaries (`$FPC_SRC/compiler/ppcrv32` and `$FPC_SRC/rtl/units/riscv32-freertos`) without installing; `$FPC_PREFIX` is only needed once you `make install`.

### 5.1 What S31 is in this toolchain

| Piece | Fact |
| --- | --- |
| CPU / ISA | RISC-V `rv32imafc` (F present; **no D**) |
| ABI | **ILP32F** — 32-bit float in F registers; 64-bit float is an integer register pair (libgcc / ROM RVFPLIB) |
| Compiler | In-tree `$FPC_SRC/compiler/ppcrv32`, or `$FPC_PREFIX/lib/fpc/<version>/ppcrv32` after install (symlink `ppcriscv32` OK) |
| RTL | In-tree `$FPC_SRC/rtl/units/riscv32-freertos`, or `$FPC_PREFIX/lib/fpc/<version>/units/riscv32-freertos` |
| Program flags | `-Tfreertos -Priscv32 -Cprv32imafc -Wpesp32s31 -WP6.1 -XPriscv32-esp-elf-` plus explicit `-Ch…` (static freertos heap for now) |
| RTL `CROSSOPT` | **`-Cprv32imafc` only** — never `-Wpesp32s31` here (circular with `consoleio`) |
| Emulator | [`esp-emu`](https://github.com/espressif/esp-emulator) `--chip esp32s31` |
| Flash map (typical) | bootloader `0x2000`, partition table `0x8000`, app `0x10000` |

ILP32F must **not** emit D opcodes (`FSD`/`FLD`/`FSQRT.D`, …). Guards:
`compiler/riscv/cgrv.pas` / `nrvinl.pas` (`ilp32f_no_d`). Register save:
`rtl/riscv32/setjump.inc`.

### 5.2 Rebuild compiler + RTL

Put the Espressif `riscv32-esp-elf` toolchain `bin/` on `PATH` (from your
Espressif tools install; version pin as required by IDF 6.1).

```sh
unset FPC CROSSOPT BINUTILSPREFIX
cd "$FPC_SRC"
make -C compiler cycle
make -C compiler riscv32
export FPC="$FPC_SRC/compiler/ppcrv32"
export CROSSOPT='-Cprv32imafc'
export BINUTILSPREFIX=riscv32-esp-elf-
rm -rf rtl/units/riscv32-freertos
make -C rtl OS_TARGET=freertos CPU_TARGET=riscv32 SUBARCH=rv32imafc
# Optional install into a prefix of your choosing:
# make -C compiler install PREFIX="$FPC_PREFIX"
# make -C rtl install OS_TARGET=freertos CPU_TARGET=riscv32 SUBARCH=rv32imafc \
#   PREFIX="$FPC_PREFIX"
```

### 5.3 IDF project + libraries

```sh
unset IDF_PATH IDF_PYTHON_ENV_PATH IDF_TOOLS_PATH
export IDF_PATH=…/esp-idf-v6.1          # tag v6.1
cd "$IDF_PATH" && ./install.sh esp32s31 && . ./export.sh
cd "$IDF_PROJECT"
idf.py --preview set-target esp32s31
# sdkconfig: CONFIG_SPIRAM=y, OCT, boot init/malloc/memtest as needed
idf.py --preview build
```

Flatten `$IDF_PROJECT/build/esp-idf/**/lib*.a` onto the FPC `-Fl` path
(skip `libmain.a`). **Duplicate basenames** (mbedtls wrapper + full copy)
must be `ar`-merged. Symlink coexist if present:
`$IDF_PATH/components/esp_coex/lib/esp32s31/libcoexist.a`, plus IDF
`memory.ld` / `sections.ld`.

S31-oriented `$linklib` set:
`rtl/freertos/riscv32/esp32s31idf_60100.pp` — includes `esp_hal_regi2c`
(flash-side regi2c; S3 uses ROM) and `mbedcrypto` / `mbedtls` /
`tfpsacrypto` / `esp_security` for PSA bring-up.

### 5.4 Linker / ROM scripts — picolibc traps

IDF 6.1 on S31 uses **picolibc**. In `compiler/systems/t_freertos.pas`
(`ct_esp32s31`):

- **Pull:** `esp32s31.rom.rvfp.ld`, `esp32s31.rom.libc.ld`, phy/coexist/
  net80211/pp, `rom.heap`, `esp_hal_wdt/.../rom.wdt.ld`,
  `esp_hal_systimer/.../rom.systimer.ld`, keep-alives such as
  `-u esp_vfs_include_nullfs_register`
  `-u mbedtls_psa_crypto_init_include_impl`.
- **Never pull:** `esp32s31.rom.newlib.ld` /
  `esp32s31.rom.newlib-nano.ld` — ROM newlib-nano `printf`/`fflush`
  **abort** on picolibc `FILE*` (seen during `coex_pre_init`).
- **Never pull:** `esp32s31.rom.libgcc.ld` — use RVFPLIB via `rom.rvfp.ld`.

Link the **ILP32F** picolibc and libgcc multilibs (paths relative to the
Espressif gcc install / whatever `riscv32-esp-elf-gcc -print-sysroot` /
`-print-libgcc-file-name` report):

```text
<gcc-install>/picolibc/riscv32-esp-elf/lib/rv32imafc_zicsr_zifencei_zaamo_zalrsc/ilp32f
$(dirname $(riscv32-esp-elf-gcc -march=rv32imafc -mabi=ilp32f -print-libgcc-file-name))
```

### 5.5 Boot in `esp-emu`

```sh
esp-emu --chip esp32s31 --firmware flash.bin \
  --psram-size 8M --exit-on _haltproc
```

Smoke success markers: `HELLO_WORLD_DONE`, `HELLO_FPU_DONE`, clean
`_haltproc`. Fail on `Guru Meditation`, `abort(`, or `*_FAIL`.

### 5.6 Patch series vs S31 / RISC-V finalize order

| Patch | Status on S3 base | S31 note |
| --- | --- | --- |
| freertos-01 | Applied | Required for `uses Classes` |
| freertos-03 | Applied | Required for `AnsiCompare*` / Sort |
| freertos-02 | Pending | When something creates `TThread` |
| xtensa-04 | **Applied** (Xtensa `ncpuutil.pas`) | Does not touch RISC-V |

**RISC-V analogue:** the same forward-iterate bug lives in
`compiler/riscv32/nrv32util.pas`. Mirror xtensa-04 there (init forward,
finalize reverse) and **rebuild `ppcrv32`**. With that change applied and
the compiler rebuilt, `hello_classes` (TStringList + AnsiCompare*, no
Sort) reaches `HELLO_CLASSES_DONE` and clean `_haltproc` on `esp-emu`
(verified 2026-10-25). Without it, exit was a Core1 Cache / finalize
Guru. Sort on tiny `-Ch8192` remains a separate heap-size issue.

### 5.7 S31 review checklist

1. `-Cprv32imafc -Wpesp32s31 -WP6.1` and ILP32F libgcc/picolibc?
2. No `rom.newlib` / `rom.newlib-nano` on the link line?
3. regi2c + crypto trio present when the IDF image needs them?
4. `esp-emu --chip esp32s31` with adequate `--psram-size`?
5. DONE marker **and** no Guru/abort?
6. No D-extension opcodes on Double paths?
7. `ppcrv32` rebuilt after any `nrv32util.pas` finalize-order change?
8. After a change to the ILP32F float assignment or `x*x` rewrite (§5.8), rebuild the cross compiler and the riscv32-freertos RTL. `fpc_sqr_real` is part of the system unit.

## 5.8 Single FPU, soft double

On ILP32F, Pascal `Real`, `ValReal`, best-real, and `Extended` are double, as on Xtensa. The FPU is single-precision. A 32-bit float lives in an F register. A 64-bit float is an integer pair and uses libgcc or ROM RVFPLIB (`__adddf3`, `__muldf3`, `__extendsfdf2`, `__truncdfsf2`, and the rest of that set). The compiler sets `fputype` to `fpu_fd` so shared RISC-V code can name those operations. `ilp32f_soft_double` is true for an s64real on the ILP32F or LP64F ABI, and that predicate suppresses D opcodes. It is false on Xtensa.

Xtensa has no double FPU in this tree either. `fpu_hard` is `[FPUXTENSA_SINGLE]`. `FPUXTENSA_DOUBLE` is declared and unset. `fpu_fd` on ILP32F means the soft-double helpers are selected, which is a different fact from a hardware double FPU.

`compiler/nld.pas` sends a width-changing float assignment through the convert helpers when either side is `ilp32f_soft_double`. Delphi excess precision promotes unary minus of a single to double and then stores it back. A direct store of that integer pair into a single slot raises `internalerror 2002090904`. The helpers are `__extendsfdf2` and `__truncdfsf2`. A same-width double assignment stays a pair move. Xtensa already takes the convert path when only `FPUXTENSA_SINGLE` is set.

`compiler/nadd.pas` leaves `x*x` as a multiply when the operand is a soft double. `fpc_sqr_real` is `result := d*d`, so rewriting that body to `sqr` tail-calls itself and never returns. The multiply stays `__muldf3`. A single `x*x` still becomes `sqr` and uses `FMUL.S`. Xtensa skips the rewrite for every real width, because its condition requires `FPUXTENSA_DOUBLE`. `fpc_sqr_real` is compiled into the system unit, so this change needs a riscv32-freertos RTL rebuild as well as a new cross compiler.

## 6. Where detail lives

- [`pending-patches/README.md`](./pending-patches/README.md) — apply gates,
  discriminators, applied history (xtensa-04 recorded as applied).
- `compiler/systems/t_freertos.pas` — per-controller ROM/script link lines.
- `rtl/freertos/riscv32/esp32s31idf_60100.pp` /
  `rtl/freertos/xtensa/espidf_60100.pp` — `$linklib` sets for IDF 6.1.
