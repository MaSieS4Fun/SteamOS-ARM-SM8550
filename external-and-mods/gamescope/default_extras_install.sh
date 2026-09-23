#!/usr/bin/env sh

# Remove old Gamescope default configs and add our own.
mkdir -p "${DESTDIR}/${MESON_INSTALL_PREFIX}/share/gamescope"
rm -rf "${DESTDIR}/${MESON_INSTALL_PREFIX}/share/gamescope/scripts" || true
rm -rf "${DESTDIR}/${MESON_INSTALL_PREFIX}/share/gamescope/looks" || true
cp -r "${MESON_SOURCE_ROOT}/scripts" "${DESTDIR}/${MESON_INSTALL_PREFIX}/share/gamescope/scripts"
cp -r "${MESON_SOURCE_ROOT}/looks" "${DESTDIR}/${MESON_INSTALL_PREFIX}/share/gamescope/looks"

if [ -f "${MESON_SOURCE_ROOT}/scripts/udev/60-gamescope-backlight.rules" ]; then
	udev_dir="${DESTDIR}/usr/lib/udev/rules.d"
	if [ -d "${DESTDIR}/lib/udev/rules.d" ] && [ ! -d "${udev_dir}" ]; then
		udev_dir="${DESTDIR}/lib/udev/rules.d"
	fi
	mkdir -p "${udev_dir}"
	cp "${MESON_SOURCE_ROOT}/scripts/udev/60-gamescope-backlight.rules" "${udev_dir}/60-gamescope-backlight.rules"
fi
