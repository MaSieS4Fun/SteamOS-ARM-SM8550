/*
 * qcom-sdl-pad — DualSense UHID bridge for AYN Odin 2 / Thor.
 *
 * Forwards the handheld gamepad buttons/sticks into a virtual DualSense over
 * /dev/uhid so hid-playstation creates a real Motion Sensors sibling. SDL and
 * Cemu then expose Use motion on that single controller.
 *
 * Motion samples are read from the local DSU server (qcom-motion :26760).
 *
 * DualSense USB report descriptor + feature replies are from inputtino
 * (Apache-2.0, games-on-whales/inputtino), Copyright ABeltramo et al.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later AND Apache-2.0
 */
#define _GNU_SOURCE

#include "dualsense_blobs.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <glib-unix.h>
#include <glib.h>
#include <linux/input.h>
#include <linux/uhid.h>
#include <math.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>
#include <zlib.h>

#define DSU_PORT 26760
#define DSU_PROTOCOL_VERSION 1001
#define DSU_HEADER_BASE 16
#define DSU_HEADER_FULL 20
#define DSU_MSG_VERSION 0x100000U
#define DSU_MSG_PORTS 0x100001U
#define DSU_MSG_DATA 0x100002U
#define DSU_REG_SLOT 1

#define DS_VENDOR 0x054c
#define DS_PRODUCT 0x0ce6
#define DS_ACCEL_RES_PER_G 8192
#define DS_GYRO_RES_PER_DEG_S 1024

#define REPORT_HZ 100

#pragma pack(push, 1)
/* Matches hid-playstation: contact byte bit7 = inactive, bits0-6 = id. */
struct dualsense_touch_point {
	uint8_t contact;
	uint8_t x_lo;
	uint8_t x_hi : 4, y_lo : 4;
	uint8_t y_hi;
};

/* Matches hid-playstation dualsense_input_report (USB body, no report id). */
struct dualsense_input_report {
	uint8_t x, y;
	uint8_t rx, ry;
	uint8_t z, rz;
	uint8_t seq_number;
	uint8_t buttons[4];
	uint8_t reserved[4];
	uint16_t gyro[3];
	uint16_t accel[3];
	uint32_t sensor_timestamp;
	uint8_t reserved2;
	struct dualsense_touch_point points[2];
	uint8_t reserved3[12];
	uint8_t status[3];
	uint8_t reserved4[8];
};
#pragma pack(pop)

_Static_assert(sizeof(struct dualsense_input_report) == 63,
	       "DualSense USB body must be 63 bytes");

typedef struct {
	int uhid_fd;
	int pad_fd;
	int dsu_fd;
	gboolean grab_pad;
	gboolean verbose;
	GMainLoop *loop;
	struct dualsense_input_report report;
	uint8_t mac[6];
	uint32_t dsu_client_id;
	uint32_t sensor_tick;
	float accel_g[3];
	float gyro_dps[3];
	gboolean have_motion;
	/* Live pad state from Odin evdev */
	int32_t abs[ABS_CNT];
	uint8_t key_down[KEY_MAX / 8 + 1];
	gchar *pad_dev_path; /* /dev/input/eventN of native pad */
	mode_t pad_dev_mode; /* restore chmod after hide */
	gboolean pad_hidden;
	gchar *hidraw_path; /* DualSense hidraw (optional hide; leave open for Steam HIDAPI) */
	mode_t hidraw_mode;
	gboolean hidraw_hidden;
	int ff_effect_id; /* native pad FF_RUMBLE effect id, or -1 */
} PadBridge;

static void
write_le16 (uint8_t *p, uint16_t v)
{
	p[0] = (uint8_t) (v & 0xff);
	p[1] = (uint8_t) (v >> 8);
}

static void
write_le32 (uint8_t *p, uint32_t v)
{
	p[0] = (uint8_t) (v & 0xff);
	p[1] = (uint8_t) ((v >> 8) & 0xff);
	p[2] = (uint8_t) ((v >> 16) & 0xff);
	p[3] = (uint8_t) ((v >> 24) & 0xff);
}

static uint32_t
read_le32 (const uint8_t *p)
{
	return (uint32_t) p[0] | ((uint32_t) p[1] << 8) |
	       ((uint32_t) p[2] << 16) | ((uint32_t) p[3] << 24);
}

static float
read_float_le (const uint8_t *p)
{
	uint32_t bits = read_le32 (p);
	float value;
	memcpy (&value, &bits, sizeof (value));
	return value;
}

static void
finish_crc (uint8_t *packet, size_t length)
{
	write_le32 (packet + 8, 0);
	write_le32 (packet + 8, (uint32_t) crc32 (0L, packet, (uInt) length));
}

static void
fill_dsu_header (uint8_t *packet, size_t length, uint32_t client_id, uint32_t type)
{
	memset (packet, 0, length);
	memcpy (packet, "DSUC", 4);
	write_le16 (packet + 4, DSU_PROTOCOL_VERSION);
	write_le16 (packet + 6, (uint16_t) (length - DSU_HEADER_BASE));
	write_le32 (packet + 12, client_id);
	write_le32 (packet + 16, type);
}

static gboolean
uhid_write (int fd, const struct uhid_event *ev)
{
	ssize_t n = write (fd, ev, sizeof (*ev));
	if (n < 0) {
		g_warning ("uhid write failed: %s", g_strerror (errno));
		return FALSE;
	}
	return TRUE;
}

static int
find_odin_gamepad (PadBridge *bridge)
{
	for (unsigned int i = 0; i < 64; i++) {
		g_autofree gchar *path = g_strdup_printf ("/sys/class/input/event%u/device/name", i);
		g_autofree gchar *phys_path = g_strdup_printf ("/sys/class/input/event%u/device/phys", i);
		g_autofree gchar *dev = g_strdup_printf ("/dev/input/event%u", i);
		g_autofree gchar *name = NULL;
		g_autofree gchar *phys = NULL;
		gsize len = 0;

		if (!g_file_get_contents (path, &name, &len, NULL))
			continue;
		while (len > 0 && (name[len - 1] == '\n' || name[len - 1] == '\0'))
			name[--len] = '\0';
		/* Skip our own UHID instance (same display name). */
		if (g_file_get_contents (phys_path, &phys, NULL, NULL) &&
		    phys && strstr (phys, "qcom-sdl-pad"))
			continue;
		if (g_strcmp0 (name, "AYN Odin2 Gamepad") == 0 ||
		    g_strcmp0 (name, "AYN Thor Gamepad") == 0) {
			/* O_RDWR: needed to replay DualSense rumble onto native FF. */
			int fd = open (dev, O_RDWR | O_NONBLOCK | O_CLOEXEC);
			if (fd >= 0) {
				struct stat st;
				g_message ("Using native gamepad %s (%s)", dev, name);
				bridge->pad_dev_path = g_strdup (dev);
				if (fstat (fd, &st) == 0)
					bridge->pad_dev_mode = st.st_mode & 0777;
				else
					bridge->pad_dev_mode = 0640;
				return fd;
			}
		}
	}
	return -1;
}

static void
hide_native_pad_from_sdl (PadBridge *bridge)
{
	g_autofree gchar *cmd = NULL;
	g_autofree gchar *err = NULL;

	if (!bridge->pad_dev_path || bridge->pad_hidden)
		return;
	/* Drop ACLs (udev uaccess) then permissions so SDL cannot open the
	 * sensor-less native pad. We keep an open fd for button reads. */
	cmd = g_strdup_printf ("setfacl -b %s", bridge->pad_dev_path);
	g_spawn_command_line_sync (cmd, NULL, &err, NULL, NULL);
	if (chmod (bridge->pad_dev_path, 0) == 0) {
		bridge->pad_hidden = TRUE;
		g_message ("Hid native %s from other processes (chmod 0 + clear ACL)",
			   bridge->pad_dev_path);
	} else {
		g_warning ("chmod %s failed: %s", bridge->pad_dev_path,
			   g_strerror (errno));
	}
}

static void
restore_native_pad (PadBridge *bridge)
{
	if (bridge->pad_hidden && bridge->pad_dev_path) {
		chmod (bridge->pad_dev_path, bridge->pad_dev_mode);
		bridge->pad_hidden = FALSE;
	}
}

static gchar *
find_uhid_hidraw (const char *uniq)
{
	for (unsigned int i = 0; i < 64; i++) {
		g_autofree gchar *uevent_path =
			g_strdup_printf ("/sys/class/hidraw/hidraw%u/device/uevent", i);
		g_autofree gchar *dev = g_strdup_printf ("/dev/hidraw%u", i);
		g_autofree gchar *uevent = NULL;
		g_autofree gchar *needle = g_strdup_printf ("HID_UNIQ=%s", uniq);
		g_auto(GStrv) lines = NULL;

		if (!g_file_get_contents (uevent_path, &uevent, NULL, NULL))
			continue;
		lines = g_strsplit (uevent, "\n", -1);
		for (guint n = 0; lines && lines[n]; n++) {
			if (g_ascii_strcasecmp (lines[n], needle) == 0)
				return g_steal_pointer (&dev);
		}
	}
	return NULL;
}

static void
expose_dualsense_hidraw (PadBridge *bridge, const char *uniq)
{
	/* Steam/GameScope + SDL HIDAPI need users in group "input" to open hidraw. */
	for (int try = 0; try < 50 && !bridge->hidraw_path; try++) {
		bridge->hidraw_path = find_uhid_hidraw (uniq);
		if (!bridge->hidraw_path)
			g_usleep (20000);
	}
	if (!bridge->hidraw_path) {
		g_warning ("UHID hidraw not found — Steam may not see PS5 HIDAPI layout");
		return;
	}
	if (chmod (bridge->hidraw_path, 0660) == 0) {
		g_autoptr(GError) err = NULL;
		g_autofree gchar *cmd =
			g_strdup_printf ("chgrp input %s", bridge->hidraw_path);
		g_spawn_command_line_sync (cmd, NULL, NULL, NULL, &err);
		g_message ("Exposed %s (0660 input) for SDL/Steam HIDAPI",
			   bridge->hidraw_path);
	} else {
		g_warning ("chmod %s failed: %s", bridge->hidraw_path,
			   g_strerror (errno));
	}
}

static void
hide_uhid_evdev_duplicates (const char *uniq)
{
	/*
	 * hid-playstation creates evdev gamepad + touchpad alongside hidraw.
	 * If both are visible, Steam/SDL often bind twice and scramble controls.
	 * Keep hidraw for HIDAPI (correct PS5 layout + sensors + rumble path);
	 * hide the duplicate evdev nodes (not Motion Sensors — RPCS3 may use it).
	 */
	for (unsigned int i = 0; i < 64; i++) {
		g_autofree gchar *name_path =
			g_strdup_printf ("/sys/class/input/event%u/device/name", i);
		g_autofree gchar *uniq_path =
			g_strdup_printf ("/sys/class/input/event%u/device/uniq", i);
		g_autofree gchar *dev = g_strdup_printf ("/dev/input/event%u", i);
		g_autofree gchar *name = NULL;
		g_autofree gchar *u = NULL;
		gsize len = 0;

		if (!g_file_get_contents (uniq_path, &u, &len, NULL))
			continue;
		while (len > 0 && (u[len - 1] == '\n' || u[len - 1] == '\0'))
			u[--len] = '\0';
		if (g_ascii_strcasecmp (u, uniq) != 0)
			continue;
		if (!g_file_get_contents (name_path, &name, &len, NULL))
			continue;
		while (len > 0 && (name[len - 1] == '\n' || name[len - 1] == '\0'))
			name[--len] = '\0';
		if (strstr (name, "Motion Sensors"))
			continue;
		if (chmod (dev, 0) == 0)
			g_message ("Hid duplicate UHID evdev %s (%s)", dev, name);
	}
}

static void
restore_hidraw (PadBridge *bridge)
{
	(void) bridge;
}

static void
native_rumble (PadBridge *bridge, uint8_t motor_left, uint8_t motor_right)
{
	struct ff_effect effect;
	struct input_event play;
	int id;

	if (bridge->pad_fd < 0)
		return;

	memset (&effect, 0, sizeof (effect));
	effect.type = FF_RUMBLE;
	effect.id = bridge->ff_effect_id;
	effect.u.rumble.strong_magnitude = (uint16_t) motor_left * 256U;
	effect.u.rumble.weak_magnitude = (uint16_t) motor_right * 256U;

	if (ioctl (bridge->pad_fd, EVIOCSFF, &effect) < 0) {
		if (bridge->verbose)
			g_warning ("EVIOCSFF: %s", g_strerror (errno));
		return;
	}
	bridge->ff_effect_id = effect.id;
	id = effect.id;

	memset (&play, 0, sizeof (play));
	play.type = EV_FF;
	play.code = (uint16_t) id;
	/* value = 1 plays; 0 stops. Zero magnitudes → stop. */
	play.value = (motor_left || motor_right) ? 1 : 0;
	if (write (bridge->pad_fd, &play, sizeof (play)) != (ssize_t) sizeof (play) &&
	    bridge->verbose)
		g_warning ("FF play write: %s", g_strerror (errno));
}

static void
handle_dualsense_output (PadBridge *bridge, const uint8_t *data, size_t size)
{
	uint8_t flag0, flag2, motor_right, motor_left;

	/* USB output report id 0x02 + dualsense_output_report_common. */
	if (size < 5 || data[0] != 0x02)
		return;
	flag0 = data[1];
	/* valid_flag2 is at offset 38 within common → byte 39 of USB report. */
	flag2 = (size > 39) ? data[39] : 0;
	motor_right = data[3];
	motor_left = data[4];
	if ((flag0 & 0x01) || (flag2 & 0x04) || motor_left || motor_right)
		native_rumble (bridge, motor_left, motor_right);
}

static int
open_uhid_dualsense (PadBridge *bridge, GError **error)
{
	struct uhid_event ev;
	int fd;
	g_autofree gchar *uniq = NULL;

	fd = open ("/dev/uhid", O_RDWR | O_CLOEXEC | O_NONBLOCK);
	if (fd < 0) {
		g_set_error (error, G_FILE_ERROR, g_file_error_from_errno (errno),
			     "Unable to open /dev/uhid: %s", g_strerror (errno));
		return -1;
	}

	bridge->mac[0] = 0x02;
	bridge->mac[1] = 0x41;
	bridge->mac[2] = 0x59;
	bridge->mac[3] = 0x4e;
	bridge->mac[4] = 0x53;
	bridge->mac[5] = 0x44;
	uniq = g_strdup_printf ("%02x:%02x:%02x:%02x:%02x:%02x",
				bridge->mac[0], bridge->mac[1], bridge->mac[2],
				bridge->mac[3], bridge->mac[4], bridge->mac[5]);

	memset (&ev, 0, sizeof (ev));
	ev.type = UHID_CREATE2;
	/* Keep Sony VID/PID so hid-playstation binds and exposes Motion Sensors.
	 * Name is what SDL/Cemu show — match the handheld pad identity. */
	g_strlcpy ((char *) ev.u.create2.name,
		   "AYN Odin2 Gamepad",
		   sizeof (ev.u.create2.name));
	g_strlcpy ((char *) ev.u.create2.phys, "qcom-sdl-pad", sizeof (ev.u.create2.phys));
	g_strlcpy ((char *) ev.u.create2.uniq, uniq, sizeof (ev.u.create2.uniq));
	ev.u.create2.rd_size = sizeof (ps5_rdesc);
	ev.u.create2.bus = BUS_USB;
	ev.u.create2.vendor = DS_VENDOR;
	ev.u.create2.product = DS_PRODUCT;
	ev.u.create2.version = 0x0100;
	ev.u.create2.country = 0;
	memcpy (ev.u.create2.rd_data, ps5_rdesc, sizeof (ps5_rdesc));

	if (!uhid_write (fd, &ev)) {
		g_set_error (error, G_FILE_ERROR, G_FILE_ERROR_FAILED,
			     "UHID_CREATE2 failed");
		close (fd);
		return -1;
	}

	bridge->uhid_fd = fd;
	g_message ("Created AYN Odin2 Gamepad UHID (DualSense HID) uniq=%s", uniq);
	expose_dualsense_hidraw (bridge, uniq);
	/* Evdev duplicates: only hide when explicitly requested. Steam Game Mode
	 * should stop this service instead (qcom-sdl-pad-gamescope). */
	if (g_getenv ("QCOM_SDL_PAD_HIDE_EVDEV"))
		hide_uhid_evdev_duplicates (uniq);
	return fd;
}

static void
handle_uhid_get_report (PadBridge *bridge, const struct uhid_event *ev)
{
	struct uhid_event reply;

	memset (&reply, 0, sizeof (reply));
	reply.type = UHID_GET_REPORT_REPLY;
	reply.u.get_report_reply.id = ev->u.get_report.id;
	reply.u.get_report_reply.err = 0;

	switch (ev->u.get_report.rnum) {
	case 0x05:
		memcpy (reply.u.get_report_reply.data, ps5_calibration_info,
			sizeof (ps5_calibration_info));
		reply.u.get_report_reply.size = sizeof (ps5_calibration_info);
		break;
	case 0x09:
		memcpy (reply.u.get_report_reply.data, ps5_pairing_info,
			sizeof (ps5_pairing_info));
		/* MAC is big-endian at bytes 1..6 in pairing blob; overwrite. */
		reply.u.get_report_reply.data[1] = bridge->mac[5];
		reply.u.get_report_reply.data[2] = bridge->mac[4];
		reply.u.get_report_reply.data[3] = bridge->mac[3];
		reply.u.get_report_reply.data[4] = bridge->mac[2];
		reply.u.get_report_reply.data[5] = bridge->mac[1];
		reply.u.get_report_reply.data[6] = bridge->mac[0];
		reply.u.get_report_reply.size = sizeof (ps5_pairing_info);
		break;
	case 0x20:
		memcpy (reply.u.get_report_reply.data, ps5_firmware_info,
			sizeof (ps5_firmware_info));
		reply.u.get_report_reply.size = sizeof (ps5_firmware_info);
		break;
	default:
		reply.u.get_report_reply.err = (uint16_t) -EINVAL;
		break;
	}
	uhid_write (bridge->uhid_fd, &reply);
}

static gboolean
uhid_ready (gint fd, GIOCondition condition, gpointer user_data)
{
	PadBridge *bridge = user_data;
	struct uhid_event ev;

	(void) condition;
	for (;;) {
		ssize_t n = read (fd, &ev, sizeof (ev));
		if (n < 0) {
			if (errno == EAGAIN || errno == EWOULDBLOCK)
				break;
			g_warning ("uhid read failed: %s", g_strerror (errno));
			break;
		}
		if ((size_t) n < sizeof (ev.type))
			continue;
		switch (ev.type) {
		case UHID_START:
			if (bridge->verbose)
				g_message ("UHID_START flags=0x%llx",
					   (unsigned long long) ev.u.start.dev_flags);
			break;
		case UHID_STOP:
		case UHID_OPEN:
		case UHID_CLOSE:
			break;
		case UHID_GET_REPORT:
			handle_uhid_get_report (bridge, &ev);
			break;
		case UHID_SET_REPORT: {
			struct uhid_event reply = { .type = UHID_SET_REPORT_REPLY };
			reply.u.set_report_reply.id = ev.u.set_report.id;
			reply.u.set_report_reply.err = 0;
			uhid_write (bridge->uhid_fd, &reply);
			if (ev.u.set_report.rtype == UHID_OUTPUT_REPORT)
				handle_dualsense_output (bridge, ev.u.set_report.data,
							 ev.u.set_report.size);
			break;
		}
		case UHID_OUTPUT:
			handle_dualsense_output (bridge, ev.u.output.data, ev.u.output.size);
			break;
		default:
			break;
		}
	}
	return G_SOURCE_CONTINUE;
}

static gboolean
key_is_down (const PadBridge *bridge, unsigned int code)
{
	return (bridge->key_down[code / 8] >> (code % 8)) & 1;
}

static void
set_key (PadBridge *bridge, unsigned int code, int value)
{
	if (code > KEY_MAX)
		return;
	if (value)
		bridge->key_down[code / 8] |= (uint8_t) (1u << (code % 8));
	else
		bridge->key_down[code / 8] &= (uint8_t) ~(1u << (code % 8));
}

static uint8_t
scale_stick (int32_t value, int32_t min_v, int32_t max_v)
{
	double mid = (min_v + max_v) / 2.0;
	double half = (max_v - min_v) / 2.0;
	double n = (value - mid) / half;
	if (n < -1.0)
		n = -1.0;
	if (n > 1.0)
		n = 1.0;
	return (uint8_t) lround ((n + 1.0) * 127.5);
}

static uint8_t
scale_trigger (int32_t value, int32_t max_v)
{
	if (value < 0)
		value = 0;
	if (max_v <= 0)
		return 0;
	if (value > max_v)
		value = max_v;
	return (uint8_t) ((value * 255) / max_v);
}

static uint8_t
hat_from_dpad (const PadBridge *bridge)
{
	gboolean up = key_is_down (bridge, BTN_DPAD_UP);
	gboolean down = key_is_down (bridge, BTN_DPAD_DOWN);
	gboolean left = key_is_down (bridge, BTN_DPAD_LEFT);
	gboolean right = key_is_down (bridge, BTN_DPAD_RIGHT);

	if (up && right)
		return 0x1;
	if (down && right)
		return 0x3;
	if (down && left)
		return 0x5;
	if (up && left)
		return 0x7;
	if (up)
		return 0x0;
	if (right)
		return 0x2;
	if (down)
		return 0x4;
	if (left)
		return 0x6;
	return 0x8;
}

static int16_t
clamp_i16 (double value)
{
	if (value > 32767.0)
		return 32767;
	if (value < -32768.0)
		return -32768;
	return (int16_t) lround (value);
}

static void
build_report (PadBridge *bridge)
{
	struct dualsense_input_report *r = &bridge->report;
	uint8_t b0, b1, b2;

	memset (r, 0, sizeof (*r));
	/* DualSense / Linux: Y axes grow downward in report space; Odin ABS_Y
	 * is typically inverted relative to that, so flip both sticks. */
	r->x = scale_stick (bridge->abs[ABS_X], -1408, 1408);
	r->y = (uint8_t) (255 - scale_stick (bridge->abs[ABS_Y], -1408, 1408));
	r->rx = scale_stick (bridge->abs[ABS_RX], -1408, 1408);
	r->ry = (uint8_t) (255 - scale_stick (bridge->abs[ABS_RY], -1408, 1408));
	r->z = scale_trigger (bridge->abs[ABS_Z], 1830);
	r->rz = scale_trigger (bridge->abs[ABS_RZ], 1830);
	r->seq_number = (uint8_t) (bridge->sensor_tick & 0xff);

	b0 = hat_from_dpad (bridge);
	if (key_is_down (bridge, BTN_WEST))
		b0 |= 0x10; /* Square */
	if (key_is_down (bridge, BTN_SOUTH))
		b0 |= 0x20; /* Cross */
	if (key_is_down (bridge, BTN_EAST))
		b0 |= 0x40; /* Circle */
	if (key_is_down (bridge, BTN_NORTH))
		b0 |= 0x80; /* Triangle */

	b1 = 0;
	if (key_is_down (bridge, BTN_TL))
		b1 |= 0x01;
	if (key_is_down (bridge, BTN_TR))
		b1 |= 0x02;
	if (r->z > 30)
		b1 |= 0x04; /* L2 digital */
	if (r->rz > 30)
		b1 |= 0x08; /* R2 digital */
	if (key_is_down (bridge, BTN_SELECT))
		b1 |= 0x10;
	if (key_is_down (bridge, BTN_START))
		b1 |= 0x20;
	if (key_is_down (bridge, BTN_THUMBL))
		b1 |= 0x40;
	if (key_is_down (bridge, BTN_THUMBR))
		b1 |= 0x80;

	b2 = 0;
	if (key_is_down (bridge, BTN_MODE))
		b2 |= 0x01;
	if (key_is_down (bridge, BTN_BACK))
		b2 |= 0x02; /* touchpad click */

	r->buttons[0] = b0;
	r->buttons[1] = b1;
	r->buttons[2] = b2;
	r->buttons[3] = 0;

	/* DualSense motion: accel in units of 1/8192 G, gyro 1/1024 deg/s. */
	r->accel[0] = (uint16_t) clamp_i16 (bridge->accel_g[0] * DS_ACCEL_RES_PER_G);
	r->accel[1] = (uint16_t) clamp_i16 (bridge->accel_g[1] * DS_ACCEL_RES_PER_G);
	r->accel[2] = (uint16_t) clamp_i16 (bridge->accel_g[2] * DS_ACCEL_RES_PER_G);
	r->gyro[0] = (uint16_t) clamp_i16 (bridge->gyro_dps[0] * DS_GYRO_RES_PER_DEG_S);
	r->gyro[1] = (uint16_t) clamp_i16 (bridge->gyro_dps[1] * DS_GYRO_RES_PER_DEG_S);
	r->gyro[2] = (uint16_t) clamp_i16 (bridge->gyro_dps[2] * DS_GYRO_RES_PER_DEG_S);
	/* hid-playstation: timestamp units are 0.33 µs → tick * period_us * 3 */
	r->sensor_timestamp = GUINT32_TO_LE (
		bridge->sensor_tick * (uint32_t) (1000000u / REPORT_HZ) * 3u);
	r->points[0].contact = 0x80; /* inactive (bit7) */
	r->points[1].contact = 0x80;
	r->status[0] = 0x1; /* USB / battery nibble */
}

static void
send_input_report (PadBridge *bridge)
{
	struct uhid_event ev;
	uint8_t *data;

	build_report (bridge);
	memset (&ev, 0, sizeof (ev));
	ev.type = UHID_INPUT2;
	ev.u.input2.size = 1 + sizeof (bridge->report);
	data = ev.u.input2.data;
	data[0] = 0x01;
	memcpy (data + 1, &bridge->report, sizeof (bridge->report));
	uhid_write (bridge->uhid_fd, &ev);
	bridge->sensor_tick++;
}

static gboolean
pad_ready (gint fd, GIOCondition condition, gpointer user_data)
{
	PadBridge *bridge = user_data;
	struct input_event ie;

	(void) condition;
	for (;;) {
		ssize_t n = read (fd, &ie, sizeof (ie));
		if (n < 0) {
			if (errno == EAGAIN || errno == EWOULDBLOCK)
				break;
			g_warning ("pad read failed: %s", g_strerror (errno));
			break;
		}
		if ((size_t) n < sizeof (ie))
			continue;
		if (ie.type == EV_KEY)
			set_key (bridge, ie.code, ie.value);
		else if (ie.type == EV_ABS && ie.code < ABS_CNT)
			bridge->abs[ie.code] = ie.value;
	}
	return G_SOURCE_CONTINUE;
}

static int
open_dsu_client (PadBridge *bridge, GError **error)
{
	struct sockaddr_in addr = {
		.sin_family = AF_INET,
		.sin_port = htons (DSU_PORT),
		.sin_addr.s_addr = htonl (INADDR_LOOPBACK),
	};
	int fd = socket (AF_INET, SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);

	if (fd < 0) {
		g_set_error (error, G_FILE_ERROR, g_file_error_from_errno (errno),
			     "DSU socket: %s", g_strerror (errno));
		return -1;
	}
	if (connect (fd, (struct sockaddr *) &addr, sizeof (addr)) < 0) {
		g_set_error (error, G_FILE_ERROR, g_file_error_from_errno (errno),
			     "DSU connect: %s", g_strerror (errno));
		close (fd);
		return -1;
	}
	bridge->dsu_fd = fd;
	bridge->dsu_client_id = g_random_int ();
	return fd;
}

static void
dsu_send_register (PadBridge *bridge)
{
	uint8_t packet[28];

	fill_dsu_header (packet, sizeof (packet), bridge->dsu_client_id, DSU_MSG_DATA);
	packet[20] = DSU_REG_SLOT;
	packet[21] = 0;
	finish_crc (packet, sizeof (packet));
	if (send (bridge->dsu_fd, packet, sizeof (packet), 0) < 0 && bridge->verbose)
		g_warning ("DSU register send failed: %s", g_strerror (errno));
}

static gboolean
dsu_ready (gint fd, GIOCondition condition, gpointer user_data)
{
	PadBridge *bridge = user_data;
	uint8_t packet[256];

	(void) condition;
	for (;;) {
		ssize_t n = recv (fd, packet, sizeof (packet), 0);
		if (n < 0) {
			if (errno == EAGAIN || errno == EWOULDBLOCK)
				break;
			break;
		}
		if (n < 100 || memcmp (packet, "DSUS", 4) != 0)
			continue;
		if (read_le32 (packet + 16) != DSU_MSG_DATA)
			continue;
		bridge->accel_g[0] = read_float_le (packet + 76);
		bridge->accel_g[1] = read_float_le (packet + 80);
		bridge->accel_g[2] = read_float_le (packet + 84);
		bridge->gyro_dps[0] = read_float_le (packet + 88);
		bridge->gyro_dps[1] = read_float_le (packet + 92);
		bridge->gyro_dps[2] = read_float_le (packet + 96);
		bridge->have_motion = TRUE;
		/* Renew registration like Cemu. */
		dsu_send_register (bridge);
	}
	return G_SOURCE_CONTINUE;
}

static gboolean
tick_cb (gpointer user_data)
{
	PadBridge *bridge = user_data;
	static guint renew = 0;

	if ((renew++ % 20) == 0)
		dsu_send_register (bridge);
	if (!bridge->have_motion) {
		/* Flat default until DSU streams. */
		bridge->accel_g[0] = 0;
		bridge->accel_g[1] = -1.0f;
		bridge->accel_g[2] = 0;
	}
	send_input_report (bridge);
	return G_SOURCE_CONTINUE;
}

static gboolean
shutdown_cb (gpointer user_data)
{
	PadBridge *bridge = user_data;
	g_main_loop_quit (bridge->loop);
	return G_SOURCE_REMOVE;
}

static void
destroy_uhid (PadBridge *bridge)
{
	struct uhid_event ev = { .type = UHID_DESTROY };
	if (bridge->uhid_fd >= 0) {
		uhid_write (bridge->uhid_fd, &ev);
		close (bridge->uhid_fd);
		bridge->uhid_fd = -1;
	}
}

int
main (int argc, char **argv)
{
	PadBridge bridge = {
		.uhid_fd = -1,
		.pad_fd = -1,
		.dsu_fd = -1,
		.grab_pad = TRUE,
		.ff_effect_id = -1,
	};
	gboolean no_grab = FALSE;
	GError *error = NULL;
	GOptionEntry entries[] = {
		{ "no-grab", 0, 0, G_OPTION_ARG_NONE, &no_grab,
		  "Do not EVIOCGRAB / chmod-hide the Odin gamepad (debug)", NULL },
		{ "verbose", 'v', 0, G_OPTION_ARG_NONE, &bridge.verbose, "Verbose", NULL },
		{ NULL }
	};
	GOptionContext *ctx = g_option_context_new (
		"- AYN Odin2 Gamepad UHID with SDL motion for Cemu");

	g_option_context_add_main_entries (ctx, entries, NULL);
	if (!g_option_context_parse (ctx, &argc, &argv, &error)) {
		g_printerr ("%s\n", error->message);
		return 2;
	}
	g_option_context_free (ctx);
	bridge.grab_pad = !no_grab;

	bridge.pad_fd = find_odin_gamepad (&bridge);
	if (bridge.pad_fd < 0) {
		g_printerr ("AYN Odin2/Thor gamepad not found\n");
		return 1;
	}
	if (bridge.grab_pad) {
		int grab = 1;
		if (ioctl (bridge.pad_fd, EVIOCGRAB, &grab) < 0)
			g_warning ("EVIOCGRAB failed: %s (continuing)", g_strerror (errno));
		else
			g_message ("Grabbed native Odin gamepad");
		hide_native_pad_from_sdl (&bridge);
	}

	if (open_uhid_dualsense (&bridge, &error) < 0) {
		g_printerr ("%s\n", error->message);
		restore_native_pad (&bridge);
		return 1;
	}
	if (open_dsu_client (&bridge, &error) < 0) {
		g_printerr ("%s\n", error->message);
		destroy_uhid (&bridge);
		restore_native_pad (&bridge);
		return 1;
	}

	bridge.abs[ABS_X] = bridge.abs[ABS_Y] = 0;
	bridge.abs[ABS_RX] = bridge.abs[ABS_RY] = 0;
	bridge.abs[ABS_Z] = bridge.abs[ABS_RZ] = 0;
	bridge.accel_g[1] = -1.0f;

	bridge.loop = g_main_loop_new (NULL, FALSE);
	g_unix_fd_add (bridge.uhid_fd, G_IO_IN | G_IO_ERR | G_IO_HUP, uhid_ready, &bridge);
	g_unix_fd_add (bridge.pad_fd, G_IO_IN | G_IO_ERR | G_IO_HUP, pad_ready, &bridge);
	g_unix_fd_add (bridge.dsu_fd, G_IO_IN | G_IO_ERR | G_IO_HUP, dsu_ready, &bridge);
	g_timeout_add (1000 / REPORT_HZ, tick_cb, &bridge);
	g_unix_signal_add (SIGINT, shutdown_cb, &bridge);
	g_unix_signal_add (SIGTERM, shutdown_cb, &bridge);

	dsu_send_register (&bridge);
	g_message ("qcom-sdl-pad ready — DualSense HIDAPI (PS5 layout) + Use motion");
	g_main_loop_run (bridge.loop);

	if (bridge.grab_pad) {
		int grab = 0;
		ioctl (bridge.pad_fd, EVIOCGRAB, &grab);
	}
	restore_native_pad (&bridge);
	restore_hidraw (&bridge);
	destroy_uhid (&bridge);
	close (bridge.pad_fd);
	close (bridge.dsu_fd);
	g_free (bridge.pad_dev_path);
	g_free (bridge.hidraw_path);
	g_main_loop_unref (bridge.loop);
	return 0;
}
