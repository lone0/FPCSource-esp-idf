{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2026 by Florian Klaempfl
    member of the Free Pascal development team.

    System unit for FreeRTOS systems

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{$IFNDEF FPC_DOTTEDUNITS}
unit espidf_60100;
{$ENDIF FPC_DOTTEDUNITS}

interface

{ Aligned with espidf_50200, using IDF v6.1 library names.
  Minimal closure: every entry below is pulled by the linked test programs
  (console/heap/sysutils/classes/math sample). Archives never pulled by any
  of them are deliberately absent -- SDK projects that skip their components
  (e.g. wifi-less hello_world) then still satisfy this list. Programs that
  use further IDF libraries declare their own {$linklib} in application
  units, exactly like idfheap does for esp_psram. }

{$linklib app_update,static}
{$linklib bootloader_support,static}
//{$linklib core,static}
{$linklib esp_driver_dma,static}
{$linklib esp_driver_gpio,static}
{$linklib esp_driver_uart,static}
{$linklib esp_driver_usb_serial_jtag,static}
{$linklib efuse,static}
{$linklib esp_app_format,static}
{$linklib esp_common,static}
{$linklib esp_hw_support,static}
{$linklib esp_mm,static}
{$linklib esp_partition,static}
{$linklib esp_phy,static}
//{$linklib esp_pm,static}
{$linklib esp_psram,static}
{$linklib esp_ringbuf,static}
{$linklib esp_rom,static}
{$linklib esp_stdio,static}
{$linklib esp_system,static}
{$linklib esp_timer,static}
{$linklib freertos,static}
{$linklib hal,static}
{$linklib esp_hal_ana_conv,static}
{$linklib esp_hal_clock,static}
{$linklib esp_hal_dma,static}
{$linklib esp_hal_gpio,static}
{$linklib esp_hal_gpspi,static}
{$linklib esp_hal_mspi,static}
{$linklib esp_hal_pmu,static}
{$linklib esp_hal_security,static}
{$linklib esp_hal_systimer,static}
{$linklib esp_hal_touch_sens,static}
{$linklib esp_hal_uart,static}
{$linklib heap,static}
{$linklib log,static}
{$linklib mbedcrypto,static}
{$linklib esp_libc,static}
{$linklib pthread,static}
{$linklib soc,static}
{$linklib spi_flash,static}
{$linklib vfs,static}
{$linklib xt_hal,static}
{$linklib xtensa,static}

{$linklib c,static}
{$linklib m,static}
{$linklib gcc,static}
{$linklib espcoredump,static}

implementation

end.
