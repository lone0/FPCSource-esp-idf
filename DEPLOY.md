# Deploy Free Pascal for ESP32 (ESP-IDF 6.1)

**Trigger:** “deploy free pascal for esp32” (and synonyms).  
**Branch:** `esp-idf-6.1-s3/s31` (this tree).  
**Wiki:** [Free Pascal Compiler for ESP32：从源码手动构建与安装](https://github.com/lone0/FPCSource-esp-idf/wiki/Free-Pascal-Compiler-for-ESP32：从源码手动构建与安装)

Companion agent rules: [`AGENTS.md`](./AGENTS.md). Application-side build
driver: [lone0/esp-units.pas](https://github.com/lone0/esp-units.pas)
`scripts/build.sh` (expects real `ppcross*` under `ESP_FPC_ROOT`).

## Goal

Produce ESP-IDF **6.1** + FPC **3.3.1** cross compilers so:

| SoC | ISA / ABI | FPC binary name |
| --- | --- | --- |
| ESP32-S3 | Xtensa LX7, `SUBARCH=lx7hf` (hard float single) | `ppcrossxtensa` |
| ESP32-S31 | RISC-V `rv32imafc`, ILP32F | `ppcrossrv32` |

…and so `esp-units.pas/scripts/build.sh` finds them via `ESP_FPC_ROOT`.

**Hard rule:** never create naming symlinks (`ppcxtensa`→`ppcrossxtensa`,
`ppcrv32`→`ppcrossrv32`, …). A full install must place the real
`CROSSINSTALL` binaries under `lib/fpc/<version>/`.

## Six required steps

1. Find or make a copy of ESP-IDF v6.1  
2. Configure it with xtensa and riscv (typical targets: s3 and s31)  
3. Deploy **two** IDF builds for those targets  
4. Cross-compile this tree against both targets with both IDF builds  
5. Cross-install both cross compilers so `esp-units.pas` `build.sh` finds them  
6. Create a hello-world Pascal program; build with both compilers; show both
   targets running (emulation or real hardware)

## Placeholders

| Name | Meaning |
| --- | --- |
| `$FPC_SRC` | This repository root |
| `$IDF_PATH` | ESP-IDF **v6.1** checkout |
| `$IDF_PROJECT_S3` | Built `idf.py` project, `CONFIG_IDF_TARGET=esp32s3` |
| `$IDF_PROJECT_S31` | Built `idf.py` project, `CONFIG_IDF_TARGET=esp32s31` |
| `$FPC_PREFIX_S3` | Install prefix for Xtensa (holds `lib/fpc/*/ppcrossxtensa`) |
| `$FPC_PREFIX_S31` | Install prefix for RISC-V (holds `lib/fpc/*/ppcrossrv32`) |
| `$ESP_UNITS` | Clone of `esp-units.pas` (optional but recommended) |

Wiki examples used `/workspace/…`. Any writable layout is fine; keep IDF/FPC
install trees **outside** unrelated Cursor/Origin project repos unless the
user explicitly wants them nested.

---

### 1–2. ESP-IDF v6.1 + toolchains

```sh
# clone --depth 1 --branch v6.1 --recursive if missing
cd "$IDF_PATH"
./install.sh esp32s3,esp32s31
. ./export.sh   # every new shell: idf.py, esptool, *esp-elf* on PATH
```

### 3. Two IDF application builds

Minimal apps must still `PRIV_REQUIRES` the components FPC RTL link-lists
(even if unused at C level), for example:

```cmake
idf_component_register(SRCS "hello_world_main.c"
                       PRIV_REQUIRES spi_flash
                         esp_driver_uart esp_driver_usb_serial_jtag
                         esp_ringbuf vfs esp_phy esp_psram espcoredump
                       INCLUDE_DIRS "")
```

Drop `esp_psram` on S31 when SPIRAM is off. Tip `$linklib` units omit
`esp_psram` / `espcoredump`; if SPIRAM is on, the Pascal program (or
`build.sh`) must still pull those archives.

sdkconfig notes:

- Disable idle-task WDT on CPU0/1 for long compute tests  
- `CONFIG_ESP_COREDUMP_ENABLE_TO_UART=y` when RTL needs coredump  
- S3: SPI PSRAM on (QEMU needs matching `-m`); S31: typically SPIRAM-less  
- S31 flash map (typical): bootloader `0x2000`, table `0x8000`, app `0x10000`

```sh
. "$IDF_PATH/export.sh"
cd "$IDF_PROJECT_S3"  && idf.py set-target esp32s3  && idf.py build
cd "$IDF_PROJECT_S31" && idf.py set-target esp32s31 && idf.py build
```

### 4–5. Cross-compile + install

Always `unset FPC CROSSOPT BINUTILSPREFIX` before switching SoCs. Do **not**
pass `OS_TARGET=freertos` to `make -C compiler` (only to `make -C rtl` /
packages). RTL `CROSSOPT` is CPU/FPU only — never `-Wpesp32s3` /
`-Wpesp32s31` (circular with `consoleio`). Prefer **separate** prefixes per
SoC so `ESP_FPC_ROOT` is unambiguous.

Two install shapes (not identical):

| | **Light (suite-ready)** | **Full** |
| --- | --- | --- |
| What | Cross compiler + freertos RTL + `rtl-objpas` + `rtl-generics` | `crossall` / `crossinstall` (compiler + RTL + **all** freertos packages) |
| Size (S3 order of magnitude) | ~100 `.ppu` | ~700 `.ppu` |
| When | Hello-world **and** `esp-units` suite (needs `Generics.*`) | Want every package FCL/rtl-* under the prefix |
| Without `rtl-generics` | `t_generics_*` **COMPFAIL** | — |

#### A. Light (suite-ready): cycle + RTL + two packages

Matches `esp-units` (`ppcrossxtensa` / `ppcrossrv32`):

```sh
unset FPC CROSSOPT BINUTILSPREFIX
cd "$FPC_SRC"
. "$IDF_PATH/export.sh"
NATIVE="$PWD/compiler/ppcx64"

make -C compiler cycle
make -C compiler PPC_TARGET=xtensa  EXENAME=ppcrossxtensa \
  FPC="$NATIVE" compiler
make -C compiler PPC_TARGET=riscv32 EXENAME=ppcrossrv32 \
  FPC="$NATIVE" compiler

make -C compiler exeinstall OS_TARGET=freertos CPU_TARGET=xtensa SUBARCH=lx7hf \
  PREFIX="$FPC_PREFIX_S3"  FPC="$NATIVE"
make -C compiler exeinstall OS_TARGET=freertos CPU_TARGET=riscv32 SUBARCH=rv32imafc \
  PREFIX="$FPC_PREFIX_S31" FPC="$NATIVE"
```

RTL (set `FPC=` to the matching `ppcross*` — empty `FPC=` makes make eat
`-C…` flags). S3: use `xtensa-esp32s3-elf-` (LSB); bare `xtensa-esp-elf-`
defaults MSB.

```sh
# S3
rm -rf rtl/units/xtensa-freertos
make -C rtl OS_TARGET=freertos CPU_TARGET=xtensa SUBARCH=lx7hf \
  FPC="$PWD/compiler/ppcrossxtensa" \
  "CROSSOPT=-Cplx7hf -Cfhard" BINUTILSPREFIX=xtensa-esp32s3-elf-
# Install via rtl/freertos — top-level `make -C rtl install` hits fpcmake
# “No targets set” on this tree.
make -C rtl/freertos install OS_TARGET=freertos CPU_TARGET=xtensa SUBARCH=lx7hf \
  PREFIX="$FPC_PREFIX_S3" FPC="$PWD/compiler/ppcrossxtensa" \
  "CROSSOPT=-Cplx7hf -Cfhard" BINUTILSPREFIX=xtensa-esp32s3-elf-
# fpmake needs Package.fpc beside the installed RTL units
install -m 644 rtl/Package.fpc \
  "$FPC_PREFIX_S3/lib/fpc/3.3.1/units/xtensa-freertos/rtl/Package.fpc"

# S31
rm -rf rtl/units/riscv32-freertos
make -C rtl OS_TARGET=freertos CPU_TARGET=riscv32 SUBARCH=rv32imafc \
  FPC="$PWD/compiler/ppcrossrv32" \
  CROSSOPT='-Cprv32imafc' BINUTILSPREFIX=riscv32-esp-elf-
make -C rtl/freertos install OS_TARGET=freertos CPU_TARGET=riscv32 SUBARCH=rv32imafc \
  PREFIX="$FPC_PREFIX_S31" FPC="$PWD/compiler/ppcrossrv32" \
  CROSSOPT='-Cprv32imafc' BINUTILSPREFIX=riscv32-esp-elf-
install -m 644 rtl/Package.fpc \
  "$FPC_PREFIX_S31/lib/fpc/3.3.1/units/riscv32-freertos/rtl/Package.fpc"
```

Suite packages only (`rtl-generics` depends on `rtl-objpas`). Build each
package’s standalone `fpmake` with the **in-tree** native compiler +
bootstrapped `fpmkunit` (host `/usr/bin/fpc` often mismatches this tree’s
RTL PPU version):

```sh
make -C packages/fpmkunit bootstrap FPC="$NATIVE"

pkg_buildinstall() {
  # $1=package dir  $2=ppcross  $3=PREFIX  $4=extra --options...
  local pkg=$1 ppc=$2 pref=$3; shift 3
  ( cd "packages/$pkg"
    rm -f fpmake fpmake.o
    "$NATIVE" -n -Fu../../rtl/units/x86_64-linux \
      -Fu../fpmkunit/units_bs/x86_64-linux -FE. fpmake.pp
    ./fpmake buildinstall --os=freertos --cpu="$CPU" \
      --compiler="$ppc" --prefix="$pref" \
      --baseinstalldir="$pref/lib/fpc/3.3.1" \
      --localunitdir=.. --globalunitdir="$pref/lib/fpc/3.3.1" \
      --skipcrossprograms "$@"
  )
}

# S3 — order matters: objpas then generics
CPU=xtensa
pkg_buildinstall rtl-objpas  "$PWD/compiler/ppcrossxtensa" "$FPC_PREFIX_S3" \
  --options=-Cplx7hf --options=-Cfhard --options=-XPxtensa-esp32s3-elf-
pkg_buildinstall rtl-generics "$PWD/compiler/ppcrossxtensa" "$FPC_PREFIX_S3" \
  --options=-Cplx7hf --options=-Cfhard --options=-XPxtensa-esp32s3-elf-

# S31
CPU=riscv32
pkg_buildinstall rtl-objpas  "$PWD/compiler/ppcrossrv32" "$FPC_PREFIX_S31" \
  --options=-Cprv32imafc --options=-XPriscv32-esp-elf-
pkg_buildinstall rtl-generics "$PWD/compiler/ppcrossrv32" "$FPC_PREFIX_S31" \
  --options=-Cprv32imafc --options=-XPriscv32-esp-elf-
```

Expect under each prefix: `units/<cpu>-freertos/{rtl,rtl-objpas,rtl-generics}/`
and `lib/fpc/*/ppcross*`.

#### B. Full: `crossall` / `crossinstall`

Installs compiler + RTL + **every** freertos-capable package (~10× the light
unit count). Use when you want the whole FCL/rtl-* set, not for suite
minimum.

```sh
unset FPC CROSSOPT BINUTILSPREFIX
cd "$FPC_SRC"
. "$IDF_PATH/export.sh"

make -j crossall OS_TARGET=freertos CPU_TARGET=xtensa SUBARCH=lx7hf \
  BINUTILSPREFIX=xtensa-esp32s3-elf- \
  CROSSOPT='-XPxtensa-esp32s3-elf- -Cfhard' FPC="$PWD/compiler/ppcx64"
make -j crossinstall OS_TARGET=freertos CPU_TARGET=xtensa SUBARCH=lx7hf \
  CROSSOPT='-XPxtensa-esp32s3-elf- -Cfhard' \
  BINUTILSPREFIX=xtensa-esp32s3-elf- PREFIX="$FPC_PREFIX_S3"

make -j crossall OS_TARGET=freertos CPU_TARGET=riscv32 SUBARCH=rv32imafc \
  CROSSOPT='-Cprv32imafc' BINUTILSPREFIX=riscv32-esp-elf- FPC="$PWD/compiler/ppcx64"
make -j crossinstall OS_TARGET=freertos CPU_TARGET=riscv32 SUBARCH=rv32imafc \
  CROSSOPT='-Cprv32imafc' BINUTILSPREFIX=riscv32-esp-elf- PREFIX="$FPC_PREFIX_S31"
```

Installed binaries must still be named `ppcrossxtensa` / `ppcrossrv32`
under `lib/fpc/<ver>/` (no rename symlinks).

### Link paths (wiki §3)

When not using `esp-units` `build.sh` (which derives `-Fl` from
`ESP32_SDK_PROJECT`), collect dirs:

```sh
find "$IDF_PROJECT_S3" \( -name 'lib*.a' -o -name '*.ld' \) -type f \
  | xargs -n1 dirname | sort -u | sed 's/^/-Fl/' > esp-fl.cfg
# append picolibc + chip esp_phy / esp_wifi / xtensa component lib dirs
```

Same pattern for S31 (`esp-fl-s31.cfg`). On S31, ar-merge duplicate
basenames (`libmbedtls.a`, `libtfpsacrypto.a`, …) before `-Fl`. Use
**picolibc** ILP32F multilib — not newlib `libc.a`.

### 6. Hello-world on both targets

Minimal program: write a line to UART and print a DONE marker
(e.g. `HELLO_WORLD_DONE`).

```sh
# S3 → QEMU (Espressif qemu-system-xtensa, machine esp32s3)
export ESP_FPC_ROOT="$FPC_PREFIX_S3" \
       ESP32_SDK_PROJECT="$IDF_PROJECT_S3" \
       ESP_IDF_PATH="$IDF_PATH" \
       ESP_IDF_VERSION=6.1
"$ESP_UNITS/scripts/build.sh" --soc esp32s3 hello.pas
"$ESP_UNITS/scripts/run-qemu.sh" --soc esp32s3 hello.bin

# S31 → esp-emu (or hardware)
export ESP_FPC_ROOT="$FPC_PREFIX_S31" ESP32_SDK_PROJECT="$IDF_PROJECT_S31"
"$ESP_UNITS/scripts/build.sh" --soc esp32s31 hello.pas
"$ESP_UNITS/scripts/run-esp-emu.sh" --soc esp32s31 hello.bin
# hardware: esptool write-flash + idf.py monitor -C "$IDF_PROJECT_S31"
```

Program flags (S3):  
`-Tfreertos -Pxtensa -Cplx7hf -CfHARD -Wpesp32s3 -WP6.1 -XPxtensa-esp32s3-elf- -Ch…`

Program flags (S31):  
`-Tfreertos -Priscv32 -Cprv32imafc -Wpesp32s31 -WP6.1 -XPriscv32-esp-elf- -Ch…`

Show UART/emulation evidence for **both** SoCs before declaring deploy done.

## Done criteria

- [ ] IDF v6.1 installed for `esp32s3` and `esp32s31`
- [ ] `$IDF_PROJECT_S3` and `$IDF_PROJECT_S31` built
- [ ] `$FPC_PREFIX_S3/lib/fpc/*/ppcrossxtensa` is a **real** binary
- [ ] `$FPC_PREFIX_S31/lib/fpc/*/ppcrossrv32` is a **real** binary
- [ ] RTL under `units/xtensa-freertos/…` and `units/riscv32-freertos/…`
- [ ] Light path: `rtl-objpas` + `rtl-generics` installed (else suite generics COMPFAIL)
- [ ] Hello-world evidence for **both** S3 and S31

## Deploy pitfalls (short)

1. Empty `FPC=` → make eats `-C…` as “ignore errors”. Always set `FPC=`.  
2. Leftover `export FPC=…/ppcrossxtensa` poisons S31 builds — `unset` between SoCs.  
3. S3 packages/RTL: `xtensa-esp32s3-elf-` (LE), not bare `xtensa-esp-elf-` (BE).  
4. After changing RTL `.inc` files, wipe `rtl/units/*-freertos` and rebuild.  
5. After `ncpuutil.pas` / `nrv32util.pas` changes, rebuild the matching cross
   compiler (finalize-order fixes are baked into binaries).  
6. Fix esptool shebang to the IDF 6.1 venv python if anything execs
   `esptool.py` directly.  
7. RTL-only light install is **not** suite-complete — install `rtl-objpas` then
   `rtl-generics` (or use full `crossinstall`). Generics COMPFAIL otherwise.
