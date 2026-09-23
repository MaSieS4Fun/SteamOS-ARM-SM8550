# Arranque seguro — por qué pantalla negra y cómo evitarla

## Regla de oro

**Nunca copies solo `boot/KERNEL` a otra tarjeta SD.**  
En cada consola: `sudo ./update.sh` (desde `kernel-new-base`).

## Dos tipos de fallo

### A) Antes de Linux (sin log en `/boot/masi-boot.log`)

- ABL tiene **otro modelo** en «Set the Device»
- Odin 2 vs Mini vs Portal comparten IDs; ABL usa el **nombre guardado**, no autodetect
- Solución: Vol Abajo → Set the Device → modelo exacto → Linux → START
- **Odin 2 Mini:** el slot 3 del `KERNEL` MaSi usa el DTB de referencia (no el DTB kbuild Armbian), porque hubo reportes de pantalla negra sin log solo en Mini. Tras `./make.sh` + `update.sh`, reprobar Mini.
- **Mini + GPU / gamescope:** el DTB de referencia pide ZAP en `qcom/sm8550/a740_zap.mbn`. El árbol Armbian/MaSi solo trae `qcom/sm8550/ayn/a740_zap.mbn`. Sin el alias que crea `./make.sh` en `output/.../firmware/`, Turnip falla (`could not get GPU ID`) y gamescope cae a **llvmpipe**. Solución: reinstalar firmware con `sudo ./update.sh` (o `ln -sfn ayn/a740_zap.mbn /lib/firmware/qcom/sm8550/a740_zap.mbn`).
- **Glitches / freezes (RPCS3, etc.):** en 7.0 el dmesg muestra timeouts GMU `HFI_H2F_MSG_GX_BW_PERF_VOTE` (GPU colgada → stutter + teclas “retrasadas”). Mitigación MaSi: omite ACD + QoS interconnect Armbian, reintenta espera HFI (`patches/masi/1030-…`), keepalive GPU/GMU `power/control=on`, aliases ZAP. Rebuild: `./make.sh && sudo ./update.sh`. Re-activar ACD/QoS: `PATCH_SKIP=none ./make.sh`.

### B) Initramfs no encuentra root (a veces pantalla negra con `quiet`)

- `KERNEL` lleva el UUID de **otra** SD
- Solución: `sudo ./update.sh` en **esa** SD antes de reiniciar

## Checklist distribuidor

1. `./make.sh` en el PC  
2. Copiar **toda** la carpeta `output/…-masi/` (o repo) al tester  
3. Tester ejecuta `sudo ./update.sh` en su consola  
4. Tester configura ABL (modelo exacto)  
5. Reiniciar  

## Pocket FIT / ventilador al 100%

KONKR Pocket FIT = **SM8650** (slot 7). Este kernel es **SM8550**.  
Necesita otro proyecto base (`kernel-new-base-sm8650` — no incluido).

## UFS interno (tu Odin 2)

Funciona con `masi.ufsroot=PARTLABEL=STORAGE` + `update.sh` + `masi-install-to-ufs`.  
Otros usuarios con la misma consola pero **solo SD** deben igualmente repack UUID de **su** SD.

## ROCKNIX vs MaSi

ROCKNIX flashea imagen completa por dispositivo. MaSi compila un kernel universal con 14 DTBs; el operador debe:

- Elegir modelo en ABL  
- Repack UUID por dispositivo  

`kernel-new-base` hace obligatorio el repack (no instala si falla).
