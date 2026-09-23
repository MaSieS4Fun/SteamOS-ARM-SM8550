################################################################################
#
# batocera-qcom-motion
#
################################################################################

BATOCERA_QCOM_MOTION_VERSION = 1
BATOCERA_QCOM_MOTION_SOURCE =
BATOCERA_QCOM_MOTION_LICENSE = GPL-3.0+, Apache-2.0
BATOCERA_QCOM_MOTION_DEPENDENCIES = libglib2 libssc python3 python-pyxel zlib

BATOCERA_QCOM_MOTION_PATH = $(BR2_EXTERNAL_BATOCERA_PATH)/package/batocera/utils/batocera-qcom-motion

define BATOCERA_QCOM_MOTION_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -std=c11 -Wall -Wextra -Werror \
		-I$(STAGING_DIR)/usr/include/libssc \
		-I$(STAGING_DIR)/usr/include/glib-2.0 \
		-I$(STAGING_DIR)/usr/lib/glib-2.0/include \
		$(BATOCERA_QCOM_MOTION_PATH)/src/batocera-qcom-motion.c \
		-o $(@D)/batocera-qcom-motion \
		$(TARGET_LDFLAGS) -L$(STAGING_DIR)/usr/lib \
		-lssc -lgio-2.0 -lgobject-2.0 -lglib-2.0 -lz -lm
endef

define BATOCERA_QCOM_MOTION_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/batocera-qcom-motion \
		$(TARGET_DIR)/usr/bin/batocera-qcom-motion
	$(INSTALL) -D -m 0755 \
		$(BATOCERA_QCOM_MOTION_PATH)/src/batocera-qcom-motion-calibrator \
		$(TARGET_DIR)/usr/bin/batocera-qcom-motion-calibrator
	$(INSTALL) -D -m 0755 \
		$(BATOCERA_QCOM_MOTION_PATH)/src/motion-calibrator.py \
		$(TARGET_DIR)/usr/share/batocera/qcom-motion/motion-calibrator.py
	$(INSTALL) -D -m 0755 \
		$(BATOCERA_QCOM_MOTION_PATH)/src/Motion_Sensor_Calibration.sh \
		$(TARGET_DIR)/usr/share/batocera/qcom-motion/launcher/Motion_Sensor_Calibration.sh
	$(INSTALL) -D -m 0644 \
		$(BATOCERA_QCOM_MOTION_PATH)/src/motion-sensor-calibration.svg \
		$(TARGET_DIR)/usr/share/batocera/qcom-motion/launcher/images/motion-sensor-calibration.svg
endef

$(eval $(generic-package))
