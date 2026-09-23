################################################################################
#
# hexagonrpc
#
################################################################################

HEXAGONRPC_VERSION = dd9ac70c026e1bad93e8cffa3801255b8ceb551e
HEXAGONRPC_SITE = $(call github,linux-msm,hexagonrpc,$(HEXAGONRPC_VERSION))
HEXAGONRPC_LICENSE = GPL-3.0+
HEXAGONRPC_LICENSE_FILES = COPYING
HEXAGONRPC_DEPENDENCIES = json-c
HEXAGONRPC_INSTALL_STAGING = YES
HEXAGONRPC_CONF_OPTS = -Dhexagonrpcd_verbose=false

define HEXAGONRPC_INSTALL_SSCREGISTRYGEN
	$(INSTALL) -D -m 0755 $(@D)/build/tools/sscregistrygen \
		$(TARGET_DIR)/usr/bin/sscregistrygen
endef

HEXAGONRPC_POST_INSTALL_TARGET_HOOKS += HEXAGONRPC_INSTALL_SSCREGISTRYGEN

$(eval $(meson-package))
