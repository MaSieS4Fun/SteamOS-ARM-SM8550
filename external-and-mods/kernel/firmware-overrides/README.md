# Firmware overrides for SM8550 Resolute
#
# qcom/a740_sqe.fw — Rocknix / upstream linux-firmware SQE (md5 0211fdf6…)
# Armbian's a740_sqe.fw (md5 c56bb7d4…) causes RPCS3 Vulkan glitches on Adreno 740.
# See: Desktop/rpcs3-glitches-full.txt
#
# Applied after FIRMWARE_SOURCE staging in lib/firmware.sh.
#
# ath12k/WCN7850/hw2.0 — 7.0.14-era WLAN.HMT.1.0.c5-00481 (not the 2.2M Armbian board-2).
#   amss.bin     d3750b67b1013fe82358d0538fb131b0
#   board-2.bin  c561004dff34720e8d388191830050e4
#   m3.bin       73056f1d2aff886ce9bff313f455e963
#   regdb.bin    e84783a5bcd720fa2634dd5f4192b046
# Source: Desktop/7.0.14-edge-sm8550-initial kernel/firmware/ath12k/
