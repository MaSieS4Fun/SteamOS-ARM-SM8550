# Firmware overrides for SM8550 Resolute
#
# qcom/a740_sqe.fw — Rocknix / upstream linux-firmware SQE (md5 0211fdf6…)
# Armbian's a740_sqe.fw (md5 c56bb7d4…) causes RPCS3 Vulkan glitches on Adreno 740.
# See: Desktop/rpcs3-glitches-full.txt
#
# Applied after FIRMWARE_SOURCE staging in lib/firmware.sh.
