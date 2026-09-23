################################################################################
#
# libssc
#
################################################################################

LIBSSC_VERSION = 3befde3ef215bdb78c4a48aa72c99cd458c2aed0
LIBSSC_SITE = https://codeberg.org/DylanVanAssche/libssc.git
LIBSSC_SITE_METHOD = git
LIBSSC_LICENSE = GPL-3.0+
LIBSSC_LICENSE_FILES = LICENSE
LIBSSC_DEPENDENCIES = host-protobuf host-protobuf-c libglib2 libqrtr-glib libqmi protobuf-c
LIBSSC_INSTALL_STAGING = YES
LIBSSC_CONF_OPTS = -Dtests=false -Dintrospection=false -Dauto_features=disabled

$(eval $(meson-package))
