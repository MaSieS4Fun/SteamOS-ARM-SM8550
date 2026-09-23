/*
 * Native Qualcomm Sensor Core to DSU/Cemuhook bridge for Batocera.
 *
 * DSU server protocol handling is derived from the Apache-2.0 gCemuhook
 * implementation, Copyright 2022 v1993. The libssc bridge and Batocera
 * integration are GPL-3.0-or-later.
 *
 * SPDX-License-Identifier: Apache-2.0 AND GPL-3.0-or-later
 */

#define _GNU_SOURCE

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <glib-unix.h>
#include <glib.h>
#include <libssc.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <math.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <zlib.h>

#define DSU_PROTOCOL_VERSION 1001
#define DSU_HEADER_BASE 16
#define DSU_HEADER_FULL 20
#define DSU_MSG_VERSION 0x100000U
#define DSU_MSG_PORTS 0x100001U
#define DSU_MSG_DATA 0x100002U
#define DSU_SLOT_CONNECTED 2
#define DSU_DEVICE_GYRO_FULL 2
#define DSU_CONNECTION_OTHER 0
#define DSU_CONNECTION_USB 1
#define DSU_BATTERY_FULL 5
#define DSU_REG_ALL 0
#define DSU_REG_SLOT 1
#define DSU_REG_MAC 2
#define DSU_DEFAULT_PORT 26760
#define DSU_CLIENT_TIMEOUT_US (5 * G_USEC_PER_SEC)
#define DSU_MAX_CLIENTS 32
/*
 * Keep this well under the kernel QRTR nameserver lookup cap
 * (QRTR_NS_MAX_LOOKUPS, typically 64). Each failed SSC probe can leave a
 * NEW_LOOKUP observer; flooding past the cap makes the whole QRTR bus look
 * "unavailable" until the process exits and the socket is closed.
 */
#define SENSOR_RETRY_COUNT 48
#define SENSOR_RETRY_DELAY_US 250000
#define EARTH_GRAVITY 9.80665f
#define RAD_TO_DEG (180.0f / (float)G_PI)
#define GYRO_AUTO_CALIBRATION_SAMPLES 64
#define GYRO_CALIBRATION_MAX_RATE_DPS 8.0f
#define GYRO_CALIBRATION_MAX_STEP_DPS 2.0f
#define GYRO_CALIBRATION_MAX_STDDEV_DPS 0.35f
#define GYRO_CALIBRATION_TIMEOUT_SECONDS 30
#define GYRO_DEFAULT_DEADZONE_DPS 0.50
#define GYRO_REFINEMENT_MAX_RATE_DPS 2.5f
#define GYRO_REFINEMENT_MAX_STEP_DPS 1.0f
#define GYRO_REFINEMENT_MAX_STDDEV_DPS 0.45f
#define GYRO_REFINEMENT_ACCEL_TOLERANCE_G 0.015f
#define MOTION_DEFAULT_SAMPLE_RATE_HZ 100.0
/* Match hid-playstation DualShock/DualSense sensor nodes (RPCS3/evdev). */
#define EVDEV_ACCEL_RES_PER_G 8192
#define EVDEV_GYRO_RES_PER_DEG_S 1024
#define EVDEV_ABS_RANGE 32767
#define READY_FILE "/var/run/batocera-qcom-motion.ready"
#define THOR_CALIBRATION_FILE "/userdata/system/qcom-sensors/thor/motion-calibration.ini"
#define ODIN2_CALIBRATION_FILE "/userdata/system/qcom-sensors/odin2/motion-calibration.ini"
#define THOR_ACCEL_CALIBRATION_FRAME "thor-dsu-v3"
#define ODIN2_ACCEL_CALIBRATION_FRAME "odin2-dsu-v3"

/* Locally administered stable identifier: 02:41:59:4e:54:01 (AYN + Thor). */
#define DEVICE_MAC 0x0241594e5401ULL

typedef struct {
	gboolean active;
	uint32_t id;
	uint32_t packet_counter;
	gint64 last_request;
	struct sockaddr_storage address;
	socklen_t address_length;
} DsuClient;

typedef enum {
	MOTION_PROFILE_THOR,
	MOTION_PROFILE_ODIN2,
} MotionProfile;

typedef struct {
	int socket_fd;
	int uinput_fd;
	GMainLoop *main_loop;
	SSCSensorAccelerometer *accelerometer;
	SSCSensorGyroscope *gyroscope;
	DsuClient clients[DSU_MAX_CLIENTS];
	uint32_t server_id;
	uint64_t motion_timestamp;
	float accel[3];
	float accel_offset[3];
	float accel_matrix[3][3];
	float gyro[3];
	float gyro_bias[3];
	double calibration_mean[3];
	double calibration_m2[3];
	float calibration_previous[3];
	guint calibration_count;
	guint calibration_target;
	gboolean calibration_have_previous;
	double refinement_mean[3];
	double refinement_m2[3];
	float refinement_previous[3];
	float refinement_accel_anchor[3];
	guint refinement_count;
	gboolean refinement_have_previous;
	gboolean refinement_locked;
	gboolean gyro_calibrated;
	gboolean calibration_mode;
	gboolean calibration_success;
	gdouble gyro_deadzone;
	gdouble sample_rate;
	const gchar *calibration_file;
	const gchar *calibration_frame;
	const gchar *device_name;
	const gchar *profile_name;
	MotionProfile profile;
	gboolean have_accel;
	gboolean have_gyro;
	gboolean raw_axes;
	gboolean verbose;
	gboolean enable_evdev;
} MotionServer;

static gboolean
device_tree_has_compatible (const gchar *compatible)
{
	gchar *contents = NULL;
	gsize length = 0;
	gsize offset = 0;
	gboolean found = FALSE;

	if (!g_file_get_contents ("/proc/device-tree/compatible", &contents, &length, NULL))
		return FALSE;

	while (offset < length) {
		gsize entry_length = strnlen (contents + offset, length - offset);
		if (strlen (compatible) == entry_length &&
		    memcmp (contents + offset, compatible, entry_length) == 0) {
			found = TRUE;
			break;
		}
		offset += entry_length + 1;
	}

	g_free (contents);
	return found;
}

static gboolean
select_motion_profile (MotionServer *server, const gchar *requested, GError **error)
{
	const gchar *profile = requested;

	if (profile == NULL || g_str_equal (profile, "auto")) {
		if (device_tree_has_compatible ("ayn,thor"))
			profile = "thor";
		else if (device_tree_has_compatible ("ayn,odin2"))
			profile = "odin2";
		else {
			g_set_error_literal (error, G_OPTION_ERROR, G_OPTION_ERROR_BAD_VALUE,
					     "No supported AYN motion profile matches this device");
			return FALSE;
		}
	}

	if (g_str_equal (profile, "thor")) {
		server->profile = MOTION_PROFILE_THOR;
		server->profile_name = "thor";
		server->device_name = "AYN Thor";
		server->calibration_frame = THOR_ACCEL_CALIBRATION_FRAME;
		return TRUE;
	}
	if (g_str_equal (profile, "odin2")) {
		server->profile = MOTION_PROFILE_ODIN2;
		server->profile_name = "odin2";
		server->device_name = "AYN Odin 2";
		server->calibration_frame = ODIN2_ACCEL_CALIBRATION_FRAME;
		return TRUE;
	}

	g_set_error (error, G_OPTION_ERROR, G_OPTION_ERROR_BAD_VALUE,
		     "Unknown motion profile '%s' (expected auto, thor, or odin2)", profile);
	return FALSE;
}

static const gchar *
default_calibration_file (const MotionServer *server)
{
	return server->profile == MOTION_PROFILE_ODIN2 ?
		ODIN2_CALIBRATION_FILE : THOR_CALIBRATION_FILE;
}

/*
 * Keep this call out of line. With aggressive optimization GCC can otherwise
 * narrow "(float) sqrt((double) value)" back to sqrtf, whose symbol version is
 * newer on current glibc and prevents smoke-testing the bridge on older,
 * otherwise ABI-compatible Batocera images.
 */
__attribute__ ((noinline)) static double
sqrt_compat (double value)
{
	return sqrt (value);
}

static uint16_t
read_le16 (const uint8_t *data)
{
	uint16_t value;
	memcpy (&value, data, sizeof (value));
	return GUINT16_FROM_LE (value);
}

static uint32_t
read_le32 (const uint8_t *data)
{
	uint32_t value;
	memcpy (&value, data, sizeof (value));
	return GUINT32_FROM_LE (value);
}

static void
write_le16 (uint8_t *data, uint16_t value)
{
	value = GUINT16_TO_LE (value);
	memcpy (data, &value, sizeof (value));
}

static void
write_le32 (uint8_t *data, uint32_t value)
{
	value = GUINT32_TO_LE (value);
	memcpy (data, &value, sizeof (value));
}

static void
write_le64 (uint8_t *data, uint64_t value)
{
	value = GUINT64_TO_LE (value);
	memcpy (data, &value, sizeof (value));
}

static void
write_float_le (uint8_t *data, float value)
{
	uint32_t bits;
	G_STATIC_ASSERT (sizeof (bits) == sizeof (value));
	memcpy (&bits, &value, sizeof (bits));
	write_le32 (data, bits);
}

static float
read_float_le (const uint8_t *data)
{
	uint32_t bits = read_le32 (data);
	float value;
	memcpy (&value, &bits, sizeof (value));
	return value;
}

static void
finish_crc (uint8_t *packet, size_t length)
{
	uLong crc;
	write_le32 (packet + 8, 0);
	crc = crc32 (0L, packet, (uInt) length);
	write_le32 (packet + 8, (uint32_t) crc);
}

static void
fill_header (uint8_t *packet,
	     size_t length,
	     char peer,
	     uint32_t peer_id,
	     uint32_t message_type)
{
	memset (packet, 0, length);
	memcpy (packet, "DSU?", 4);
	packet[3] = (uint8_t) peer;
	write_le16 (packet + 4, DSU_PROTOCOL_VERSION);
	write_le16 (packet + 6, (uint16_t) (length - DSU_HEADER_BASE));
	write_le32 (packet + 12, peer_id);
	write_le32 (packet + 16, message_type);
}

static gboolean
validate_header (uint8_t *packet,
		 size_t length,
		 char peer,
		 uint32_t *peer_id,
		 uint32_t *message_type)
{
	uint32_t expected_crc;
	uint32_t actual_crc;

	if (length < DSU_HEADER_FULL || memcmp (packet, "DSU", 3) != 0 ||
	    packet[3] != (uint8_t) peer ||
	    read_le16 (packet + 4) != DSU_PROTOCOL_VERSION ||
	    read_le16 (packet + 6) != length - DSU_HEADER_BASE)
		return FALSE;

	expected_crc = read_le32 (packet + 8);
	write_le32 (packet + 8, 0);
	actual_crc = (uint32_t) crc32 (0L, packet, (uInt) length);
	write_le32 (packet + 8, expected_crc);
	if (expected_crc != actual_crc)
		return FALSE;

	if (peer_id != NULL)
		*peer_id = read_le32 (packet + 12);
	if (message_type != NULL)
		*message_type = read_le32 (packet + 16);
	return TRUE;
}

static void
write_mac (uint8_t *data)
{
	data[0] = (uint8_t) (DEVICE_MAC >> 40);
	data[1] = (uint8_t) (DEVICE_MAC >> 32);
	data[2] = (uint8_t) (DEVICE_MAC >> 24);
	data[3] = (uint8_t) (DEVICE_MAC >> 16);
	data[4] = (uint8_t) (DEVICE_MAC >> 8);
	data[5] = (uint8_t) DEVICE_MAC;
}

static uint64_t
read_mac (const uint8_t *data)
{
	uint64_t value = 0;
	for (unsigned int i = 0; i < 6; i++)
		value = (value << 8) | data[i];
	return value;
}

static void
fill_controller_header (uint8_t *data, uint8_t slot)
{
	data[0] = slot;
	if (slot != 0)
		return;

	data[1] = DSU_SLOT_CONNECTED;
	data[2] = DSU_DEVICE_GYRO_FULL;
	/* Match DualShock/Joy-Con via gcemuhook: USB looks like a built-in pad. */
	data[3] = DSU_CONNECTION_USB;
	write_mac (data + 4);
	data[10] = DSU_BATTERY_FULL;
}

static void
send_to_address (MotionServer *server,
		 const uint8_t *packet,
		 size_t length,
		 const struct sockaddr *address,
		 socklen_t address_length)
{
	ssize_t sent = sendto (server->socket_fd, packet, length, 0,
			       address, address_length);
	if (sent < 0 && server->verbose)
		g_warning ("DSU send failed: %s", g_strerror (errno));
}

static int32_t
clamp_abs_value (float value)
{
	if (value > (float) EVDEV_ABS_RANGE)
		return EVDEV_ABS_RANGE;
	if (value < (float) -EVDEV_ABS_RANGE)
		return -EVDEV_ABS_RANGE;
	return (int32_t) lroundf (value);
}

static void
emit_uinput_event (int fd, uint16_t type, uint16_t code, int32_t value)
{
	struct input_event event = {
		.type = type,
		.code = code,
		.value = value,
	};
	if (write (fd, &event, sizeof (event)) != (ssize_t) sizeof (event) &&
	    errno != EAGAIN)
		g_warning ("uinput write failed: %s", g_strerror (errno));
}

static void
emit_evdev_motion (MotionServer *server)
{
	int32_t accel[3];
	int32_t gyro[3];

	if (server->uinput_fd < 0 || !server->have_accel || !server->have_gyro)
		return;

	/*
	 * Same units as DualShock sensor nodes: ABS_X/Y/Z in G * 8192,
	 * ABS_RX/RY/RZ in deg/s * 1024. Axis frame matches DSU output.
	 */
	accel[0] = clamp_abs_value (server->accel[0] * (float) EVDEV_ACCEL_RES_PER_G);
	accel[1] = clamp_abs_value (server->accel[1] * (float) EVDEV_ACCEL_RES_PER_G);
	accel[2] = clamp_abs_value (server->accel[2] * (float) EVDEV_ACCEL_RES_PER_G);
	gyro[0] = clamp_abs_value (server->gyro[0] * (float) EVDEV_GYRO_RES_PER_DEG_S);
	gyro[1] = clamp_abs_value (server->gyro[1] * (float) EVDEV_GYRO_RES_PER_DEG_S);
	gyro[2] = clamp_abs_value (server->gyro[2] * (float) EVDEV_GYRO_RES_PER_DEG_S);

	emit_uinput_event (server->uinput_fd, EV_ABS, ABS_X, accel[0]);
	emit_uinput_event (server->uinput_fd, EV_ABS, ABS_Y, accel[1]);
	emit_uinput_event (server->uinput_fd, EV_ABS, ABS_Z, accel[2]);
	emit_uinput_event (server->uinput_fd, EV_ABS, ABS_RX, gyro[0]);
	emit_uinput_event (server->uinput_fd, EV_ABS, ABS_RY, gyro[1]);
	emit_uinput_event (server->uinput_fd, EV_ABS, ABS_RZ, gyro[2]);
	emit_uinput_event (server->uinput_fd, EV_SYN, SYN_REPORT, 0);
}

static gboolean
open_evdev_motion_device (MotionServer *server, GError **error)
{
	struct uinput_setup setup;
	struct uinput_abs_setup abs;
	int fd;
	const uint16_t abs_codes[] = {
		ABS_X, ABS_Y, ABS_Z, ABS_RX, ABS_RY, ABS_RZ
	};

	if (!server->enable_evdev) {
		server->uinput_fd = -1;
		return TRUE;
	}

	fd = open ("/dev/uinput", O_WRONLY | O_NONBLOCK);
	if (fd < 0) {
		g_set_error (error, G_FILE_ERROR, g_file_error_from_errno (errno),
			     "Unable to open /dev/uinput: %s", g_strerror (errno));
		return FALSE;
	}

	if (ioctl (fd, UI_SET_EVBIT, EV_ABS) < 0 ||
	    ioctl (fd, UI_SET_EVBIT, EV_SYN) < 0 ||
	    ioctl (fd, UI_SET_PROPBIT, INPUT_PROP_ACCELEROMETER) < 0)
		goto fail;

	for (unsigned int i = 0; i < G_N_ELEMENTS (abs_codes); i++) {
		if (ioctl (fd, UI_SET_ABSBIT, abs_codes[i]) < 0)
			goto fail;
	}

	memset (&setup, 0, sizeof (setup));
	snprintf (setup.name, sizeof (setup.name), "AYN Odin2 Motion");
	setup.id.bustype = BUS_VIRTUAL;
	setup.id.vendor = 0x0B05; /* AYN-ish locally administered */
	setup.id.product = 0x0D12;
	setup.id.version = 1;
	if (ioctl (fd, UI_DEV_SETUP, &setup) < 0)
		goto fail;

	for (unsigned int i = 0; i < G_N_ELEMENTS (abs_codes); i++) {
		memset (&abs, 0, sizeof (abs));
		abs.code = abs_codes[i];
		abs.absinfo.minimum = -EVDEV_ABS_RANGE;
		abs.absinfo.maximum = EVDEV_ABS_RANGE;
		abs.absinfo.fuzz = 16;
		abs.absinfo.resolution = (abs_codes[i] <= ABS_Z) ?
			EVDEV_ACCEL_RES_PER_G : EVDEV_GYRO_RES_PER_DEG_S;
		if (ioctl (fd, UI_ABS_SETUP, &abs) < 0)
			goto fail;
	}

	if (ioctl (fd, UI_DEV_CREATE) < 0)
		goto fail;

	server->uinput_fd = fd;
	g_message ("Exported evdev motion device \"AYN Odin2 Motion\" (RPCS3/Evdev)");
	return TRUE;

fail:
	g_set_error (error, G_FILE_ERROR, g_file_error_from_errno (errno),
		     "Unable to create uinput motion device: %s", g_strerror (errno));
	close (fd);
	server->uinput_fd = -1;
	return FALSE;
}

static void
close_evdev_motion_device (MotionServer *server)
{
	if (server->uinput_fd < 0)
		return;
	ioctl (server->uinput_fd, UI_DEV_DESTROY);
	close (server->uinput_fd);
	server->uinput_fd = -1;
}

static void
send_version (MotionServer *server,
	      const struct sockaddr *address,
	      socklen_t address_length)
{
	uint8_t packet[DSU_HEADER_FULL + 2];
	fill_header (packet, sizeof (packet), 'S', server->server_id, DSU_MSG_VERSION);
	write_le16 (packet + DSU_HEADER_FULL, DSU_PROTOCOL_VERSION);
	finish_crc (packet, sizeof (packet));
	send_to_address (server, packet, sizeof (packet), address, address_length);
}

static void
send_slot_info (MotionServer *server,
		uint8_t slot,
		const struct sockaddr *address,
		socklen_t address_length)
{
	uint8_t packet[DSU_HEADER_FULL + 12];
	fill_header (packet, sizeof (packet), 'S', server->server_id, DSU_MSG_PORTS);
	fill_controller_header (packet + DSU_HEADER_FULL, slot);
	/* Cemu PortInfoData includes is_active after battery. */
	if (slot == 0)
		packet[DSU_HEADER_FULL + 11] = 1;
	finish_crc (packet, sizeof (packet));
	send_to_address (server, packet, sizeof (packet), address, address_length);
}

static DsuClient *
register_client (MotionServer *server,
		 uint32_t client_id,
		 const struct sockaddr *address,
		 socklen_t address_length)
{
	DsuClient *free_slot = NULL;

	for (unsigned int i = 0; i < DSU_MAX_CLIENTS; i++) {
		DsuClient *client = &server->clients[i];
		if (client->active && client->id == client_id) {
			server->refinement_locked = TRUE;
			memcpy (&client->address, address, address_length);
			client->address_length = address_length;
			client->last_request = g_get_monotonic_time ();
			return client;
		}
		if (!client->active && free_slot == NULL)
			free_slot = client;
	}

	if (free_slot == NULL) {
		g_warning ("DSU client table is full");
		return NULL;
	}

	memset (free_slot, 0, sizeof (*free_slot));
	free_slot->active = TRUE;
	free_slot->id = client_id;
	free_slot->last_request = g_get_monotonic_time ();
	memcpy (&free_slot->address, address, address_length);
	free_slot->address_length = address_length;
	server->refinement_locked = TRUE;
	if (server->verbose)
		g_message ("Registered DSU client %u", client_id);
	return free_slot;
}

static void
send_motion_data (MotionServer *server)
{
	uint8_t packet[DSU_HEADER_FULL + 80];

	if (!server->have_accel || !server->have_gyro)
		return;

	fill_header (packet, sizeof (packet), 'S', server->server_id, DSU_MSG_DATA);
	fill_controller_header (packet + 20, 0);
	packet[31] = 1;
	packet[40] = 127;
	packet[41] = 127;
	packet[42] = 127;
	packet[43] = 127;
	write_le64 (packet + 68, server->motion_timestamp);
	write_float_le (packet + 76, server->accel[0]);
	write_float_le (packet + 80, server->accel[1]);
	write_float_le (packet + 84, server->accel[2]);
	write_float_le (packet + 88, server->gyro[0]);
	write_float_le (packet + 92, server->gyro[1]);
	write_float_le (packet + 96, server->gyro[2]);

	emit_evdev_motion (server);

	for (unsigned int i = 0; i < DSU_MAX_CLIENTS; i++) {
		DsuClient *client = &server->clients[i];
		if (!client->active)
			continue;
		write_le32 (packet + 32, client->packet_counter++);
		finish_crc (packet, sizeof (packet));
		send_to_address (server, packet, sizeof (packet),
				 (const struct sockaddr *) &client->address,
				 client->address_length);
	}
}

static void
set_identity_accel_calibration (MotionServer *server)
{
	memset (server->accel_offset, 0, sizeof (server->accel_offset));
	memset (server->accel_matrix, 0, sizeof (server->accel_matrix));
	for (unsigned int i = 0; i < 3; i++)
		server->accel_matrix[i][i] = 1.0f;
}

static void
accelerometer_measurement (SSCSensorAccelerometer *sensor,
			   float x,
			   float y,
			   float z,
			   gpointer user_data)
{
	MotionServer *server = user_data;
	float sample[3];
	(void) sensor;

	if (server->raw_axes) {
		server->accel[0] = x / EARTH_GRAVITY;
		server->accel[1] = y / EARTH_GRAVITY;
		server->accel[2] = z / EARTH_GRAVITY;
	} else {
		/*
		 * Map each stock SSC stream into one common DSU frame. Both devices
		 * lie at Y=+1 with their controls facing up. Odin 2's unrotated
		 * LSM6DSV reports left, top, and face-up gravity on +X, +Y, and -Z.
		 * Vertical (Y) is inverted vs. the stock SSC mapping on both profiles.
		 */
		if (server->profile == MOTION_PROFILE_ODIN2) {
			sample[0] = x / EARTH_GRAVITY;
			sample[1] = -z / EARTH_GRAVITY;
			sample[2] = y / EARTH_GRAVITY;
		} else {
			sample[0] = -y / EARTH_GRAVITY;
			sample[1] = z / EARTH_GRAVITY;
			sample[2] = -x / EARTH_GRAVITY;
		}
		for (unsigned int i = 0; i < 3; i++) {
			server->accel[i] = 0.0f;
			for (unsigned int j = 0; j < 3; j++)
				server->accel[i] += server->accel_matrix[i][j] *
					(sample[j] - server->accel_offset[j]);
		}
	}
	server->motion_timestamp = (uint64_t) g_get_monotonic_time ();
	server->have_accel = TRUE;
	/* Stream on accel too (gcemuhook sends on every sensor update). */
	if (server->have_gyro)
		send_motion_data (server);
}

static void
transform_gyro (MotionServer *server, const float raw[3], float output[3])
{
	float corrected[3];

	for (unsigned int i = 0; i < 3; i++)
		corrected[i] = raw[i] - server->gyro_bias[i];

	if (server->raw_axes) {
		output[0] = corrected[0] * RAD_TO_DEG;
		output[1] = corrected[1] * RAD_TO_DEG;
		output[2] = corrected[2] * RAD_TO_DEG;
	} else {
		if (server->profile == MOTION_PROFILE_ODIN2) {
			/* Axial-vector counterpart of the Odin 2 accel (X,-Z,Y) map. */
			output[0] = -corrected[0] * RAD_TO_DEG;
			output[1] = -corrected[2] * RAD_TO_DEG;
			output[2] = corrected[1] * RAD_TO_DEG;
		} else {
			output[0] = corrected[1] * RAD_TO_DEG;
			output[1] = corrected[2] * RAD_TO_DEG;
			output[2] = corrected[0] * RAD_TO_DEG;
		}
	}

	for (unsigned int i = 0; i < 3; i++) {
		if (fabs (output[i]) < server->gyro_deadzone)
			output[i] = 0.0f;
	}
}

static void
reset_gyro_calibration (MotionServer *server)
{
	server->calibration_count = 0;
	server->calibration_have_previous = FALSE;
	memset (server->calibration_mean, 0, sizeof (server->calibration_mean));
	memset (server->calibration_m2, 0, sizeof (server->calibration_m2));
}

static gboolean
save_gyro_calibration (MotionServer *server, GError **error)
{
	GKeyFile *key_file = g_key_file_new ();
	gchar *directory = g_path_get_dirname (server->calibration_file);
	gchar *contents;
	gsize length;
	gboolean success;

	if (g_file_test (server->calibration_file, G_FILE_TEST_IS_REGULAR))
		g_key_file_load_from_file (key_file, server->calibration_file,
					   G_KEY_FILE_KEEP_COMMENTS, NULL);
	g_key_file_set_comment (key_file, NULL, NULL,
				"AYN Qualcomm motion calibration", NULL);
	g_key_file_set_double (key_file, "gyroscope", "bias_x", server->gyro_bias[0]);
	g_key_file_set_double (key_file, "gyroscope", "bias_y", server->gyro_bias[1]);
	g_key_file_set_double (key_file, "gyroscope", "bias_z", server->gyro_bias[2]);
	contents = g_key_file_to_data (key_file, &length, error);
	if (contents == NULL) {
		g_free (directory);
		g_key_file_unref (key_file);
		return FALSE;
	}

	if (g_mkdir_with_parents (directory, 0755) < 0 && errno != EEXIST) {
		g_set_error (error, G_FILE_ERROR, g_file_error_from_errno (errno),
			     "Unable to create %s: %s", directory, g_strerror (errno));
		success = FALSE;
	} else {
		success = g_file_set_contents (server->calibration_file, contents,
					       (gssize) length, error);
	}

	g_free (contents);
	g_free (directory);
	g_key_file_unref (key_file);
	return success;
}

static gboolean
load_gyro_calibration (MotionServer *server)
{
	static const gchar *keys[] = { "bias_x", "bias_y", "bias_z" };
	static const gchar *offset_keys[] = { "offset_x", "offset_y", "offset_z" };
	GKeyFile *key_file;
	GError *error = NULL;
	float transformed[3];

	if (!g_file_test (server->calibration_file, G_FILE_TEST_IS_REGULAR))
		return FALSE;

	key_file = g_key_file_new ();
	if (!g_key_file_load_from_file (key_file, server->calibration_file,
					G_KEY_FILE_NONE, &error))
		goto fail;

	for (unsigned int i = 0; i < 3; i++) {
		double value = g_key_file_get_double (key_file, "gyroscope", keys[i], &error);
		if (error != NULL || !isfinite (value) || fabs (value) > 1.0)
			goto fail;
		server->gyro_bias[i] = (float) value;
	}
	server->gyro_calibrated = TRUE;
	if (g_key_file_has_group (key_file, "accelerometer")) {
		float offset[3];
		float matrix[3][3];
		gchar *frame = g_key_file_get_string (key_file, "accelerometer",
						       "frame", &error);
		gboolean valid = error == NULL &&
			g_strcmp0 (frame, server->calibration_frame) == 0;

		if (!valid)
			g_warning ("Ignoring accelerometer calibration with an unsupported frame in %s",
				   server->calibration_file);

		for (unsigned int i = 0; i < 3 && valid; i++) {
			double value = g_key_file_get_double (key_file, "accelerometer",
						      offset_keys[i], &error);
			if (error != NULL || !isfinite (value) || fabs (value) > 2.0)
				valid = FALSE;
			else
				offset[i] = (float) value;
		}
		for (unsigned int i = 0; i < 3 && valid; i++) {
			for (unsigned int j = 0; j < 3; j++) {
				gchar key[16];
				double value;
				g_snprintf (key, sizeof (key), "matrix_%u%u", i, j);
				value = g_key_file_get_double (key_file, "accelerometer", key, &error);
				if (error != NULL || !isfinite (value) || fabs (value) > 10.0) {
					valid = FALSE;
					break;
				}
				matrix[i][j] = (float) value;
			}
		}
		if (valid) {
			memcpy (server->accel_offset, offset, sizeof (offset));
			memcpy (server->accel_matrix, matrix, sizeof (matrix));
			g_message ("Loaded pose-based accelerometer calibration");
		} else {
			g_warning ("Ignoring invalid accelerometer calibration in %s",
				   server->calibration_file);
			g_clear_error (&error);
			set_identity_accel_calibration (server);
		}
		g_free (frame);
	}
	transform_gyro (server, (const float[3]) { 0.0f, 0.0f, 0.0f }, transformed);
	g_message ("Loaded gyro calibration %s; DSU bias=(%.3f, %.3f, %.3f) deg/s",
		   server->calibration_file, -transformed[0], -transformed[1], -transformed[2]);
	g_key_file_unref (key_file);
	return TRUE;

fail:
	g_warning ("Ignoring invalid gyro calibration %s: %s",
		   server->calibration_file,
		   error != NULL ? error->message : "invalid bias value");
	g_clear_error (&error);
	g_key_file_unref (key_file);
	memset (server->gyro_bias, 0, sizeof (server->gyro_bias));
	return FALSE;
}

static gboolean
add_gyro_calibration_sample (MotionServer *server, const float sample[3])
{
	float max_rate = 0.0f;
	float max_step = 0.0f;

	for (unsigned int i = 0; i < 3; i++) {
		max_rate = MAX (max_rate, fabsf (sample[i]) * RAD_TO_DEG);
		if (server->calibration_have_previous)
			max_step = MAX (max_step,
					fabsf (sample[i] - server->calibration_previous[i]) * RAD_TO_DEG);
	}
	if (max_rate > GYRO_CALIBRATION_MAX_RATE_DPS ||
	    (server->calibration_have_previous && max_step > GYRO_CALIBRATION_MAX_STEP_DPS)) {
		reset_gyro_calibration (server);
		return FALSE;
	}

	server->calibration_count++;
	for (unsigned int i = 0; i < 3; i++) {
		double delta = sample[i] - server->calibration_mean[i];
		server->calibration_mean[i] += delta / server->calibration_count;
		server->calibration_m2[i] += delta * (sample[i] - server->calibration_mean[i]);
		server->calibration_previous[i] = sample[i];
	}
	server->calibration_have_previous = TRUE;

	if (server->calibration_mode && server->calibration_count % 32 == 0) {
		g_print ("Gyro calibration: %u/%u stationary samples\n",
			 server->calibration_count, server->calibration_target);
		fflush (stdout);
	}
	if (server->calibration_count < server->calibration_target)
		return FALSE;

	for (unsigned int i = 0; i < 3; i++) {
		double variance = server->calibration_count > 1 ?
			server->calibration_m2[i] / (server->calibration_count - 1) : 0.0;
		if (sqrt (variance) * RAD_TO_DEG > GYRO_CALIBRATION_MAX_STDDEV_DPS) {
			reset_gyro_calibration (server);
			return FALSE;
		}
		server->gyro_bias[i] = (float) server->calibration_mean[i];
	}
	server->gyro_calibrated = TRUE;

	float transformed[3];
	transform_gyro (server, (const float[3]) { 0.0f, 0.0f, 0.0f }, transformed);
	g_message ("Gyro calibrated; DSU bias=(%.3f, %.3f, %.3f) deg/s",
		   -transformed[0], -transformed[1], -transformed[2]);

	if (server->calibration_mode) {
		GError *error = NULL;
		server->calibration_success = save_gyro_calibration (server, &error);
		if (server->calibration_success)
			g_print ("Saved gyro calibration to %s\n", server->calibration_file);
		else {
			g_printerr ("Unable to save gyro calibration: %s\n",
				    error != NULL ? error->message : "unknown error");
			g_clear_error (&error);
		}
		if (server->main_loop != NULL)
			g_main_loop_quit (server->main_loop);
	}
	return TRUE;
}

static void
reset_gyro_refinement (MotionServer *server)
{
	server->refinement_count = 0;
	server->refinement_have_previous = FALSE;
	memset (server->refinement_mean, 0, sizeof (server->refinement_mean));
	memset (server->refinement_m2, 0, sizeof (server->refinement_m2));
}

static void
refine_stationary_gyro_bias (MotionServer *server, const float sample[3])
{
	float accel_magnitude = 0.0f;
	float accel_delta = 0.0f;
	float max_rate = 0.0f;
	float max_step = 0.0f;
	guint target = MAX ((guint) server->sample_rate, 64U);

	/* Never change the neutral point underneath an active emulator session. */
	if (server->refinement_locked || !server->have_accel)
		return;
	for (unsigned int i = 0; i < 3; i++) {
		accel_magnitude += server->accel[i] * server->accel[i];
		if (server->refinement_count == 0)
			server->refinement_accel_anchor[i] = server->accel[i];
		accel_delta += (server->accel[i] - server->refinement_accel_anchor[i]) *
			(server->accel[i] - server->refinement_accel_anchor[i]);
		max_rate = MAX (max_rate,
				fabsf (sample[i] - server->gyro_bias[i]) * RAD_TO_DEG);
		if (server->refinement_have_previous)
			max_step = MAX (max_step,
					fabsf (sample[i] - server->refinement_previous[i]) *
					RAD_TO_DEG);
	}
	accel_magnitude = (float) sqrt_compat ((double) accel_magnitude);
	accel_delta = (float) sqrt_compat ((double) accel_delta);
	if (accel_magnitude < 0.85f || accel_magnitude > 1.15f ||
	    accel_delta > GYRO_REFINEMENT_ACCEL_TOLERANCE_G ||
	    max_rate > GYRO_REFINEMENT_MAX_RATE_DPS ||
	    (server->refinement_have_previous &&
	     max_step > GYRO_REFINEMENT_MAX_STEP_DPS)) {
		reset_gyro_refinement (server);
		return;
	}

	server->refinement_count++;
	for (unsigned int i = 0; i < 3; i++) {
		double delta = sample[i] - server->refinement_mean[i];
		server->refinement_mean[i] += delta / server->refinement_count;
		server->refinement_m2[i] +=
			delta * (sample[i] - server->refinement_mean[i]);
		server->refinement_previous[i] = sample[i];
	}
	server->refinement_have_previous = TRUE;
	if (server->refinement_count < target)
		return;

	for (unsigned int i = 0; i < 3; i++) {
		double variance = server->refinement_count > 1 ?
			server->refinement_m2[i] / (server->refinement_count - 1) : 0.0;
		if (sqrt (variance) * RAD_TO_DEG >
		    GYRO_REFINEMENT_MAX_STDDEV_DPS) {
			reset_gyro_refinement (server);
			return;
		}
	}

	float residual[3] = {
		(float) (server->refinement_mean[1] - server->gyro_bias[1]) * RAD_TO_DEG,
		(float) -(server->refinement_mean[2] - server->gyro_bias[2]) * RAD_TO_DEG,
		(float) -(server->refinement_mean[0] - server->gyro_bias[0]) * RAD_TO_DEG,
	};
	for (unsigned int i = 0; i < 3; i++)
		server->gyro_bias[i] = (float) server->refinement_mean[i];
	if (fabsf (residual[0]) > 0.1f || fabsf (residual[1]) > 0.1f ||
	    fabsf (residual[2]) > 0.1f)
		g_message ("Refined stationary gyro bias; removed DSU residual=(%.3f, %.3f, %.3f) deg/s",
			   residual[0], residual[1], residual[2]);
	reset_gyro_refinement (server);
}

static void
gyroscope_measurement (SSCSensorGyroscope *sensor,
		       float x,
		       float y,
		       float z,
		       gpointer user_data)
{
	MotionServer *server = user_data;
	float sample[3] = { x, y, z };
	(void) sensor;

	if (!server->gyro_calibrated) {
		if (!add_gyro_calibration_sample (server, sample))
			return;
		if (server->calibration_mode)
			return;
	}
	if (!server->calibration_mode)
		refine_stationary_gyro_bias (server, sample);
	transform_gyro (server, sample, server->gyro);
	server->motion_timestamp = (uint64_t) g_get_monotonic_time ();
	server->have_gyro = TRUE;
	send_motion_data (server);
}

static gboolean
cleanup_clients (gpointer user_data)
{
	MotionServer *server = user_data;
	gint64 now = g_get_monotonic_time ();
	gboolean have_active_client = FALSE;

	for (unsigned int i = 0; i < DSU_MAX_CLIENTS; i++) {
		DsuClient *client = &server->clients[i];
		if (client->active && now - client->last_request > DSU_CLIENT_TIMEOUT_US) {
			if (server->verbose)
				g_message ("Expired DSU client %u", client->id);
			memset (client, 0, sizeof (*client));
		}
		if (client->active)
			have_active_client = TRUE;
	}
	if (!have_active_client && server->refinement_locked) {
		server->refinement_locked = FALSE;
		reset_gyro_refinement (server);
		if (server->verbose)
			g_message ("No DSU clients remain; stationary bias refinement resumed");
	}
	return G_SOURCE_CONTINUE;
}

static gboolean
socket_ready (gint fd, GIOCondition condition, gpointer user_data)
{
	MotionServer *server = user_data;
	uint8_t packet[2048];

	if (condition & (G_IO_ERR | G_IO_HUP)) {
		g_warning ("DSU socket became unavailable");
		g_main_loop_quit (server->main_loop);
		return G_SOURCE_REMOVE;
	}

	for (;;) {
		struct sockaddr_storage sender;
		socklen_t sender_length = sizeof (sender);
		uint32_t client_id;
		uint32_t message_type;
		ssize_t length = recvfrom (fd, packet, sizeof (packet), 0,
					  (struct sockaddr *) &sender, &sender_length);

		if (length < 0) {
			if (errno == EAGAIN || errno == EWOULDBLOCK)
				break;
			g_warning ("DSU receive failed: %s", g_strerror (errno));
			break;
		}

		if (!validate_header (packet, (size_t) length, 'C',
				      &client_id, &message_type))
			continue;

		switch (message_type) {
		case DSU_MSG_VERSION:
			send_version (server, (struct sockaddr *) &sender, sender_length);
			break;
		case DSU_MSG_PORTS:
			if (length >= DSU_HEADER_FULL + 4) {
				uint32_t amount = MIN (read_le32 (packet + 20), 5U);
				amount = MIN (amount, (uint32_t) length - 24U);
				for (uint32_t i = 0; i < amount; i++) {
					uint8_t slot = packet[24 + i];
					if (slot < 4)
						send_slot_info (server, slot,
								(struct sockaddr *) &sender,
								sender_length);
				}
			}
			break;
		case DSU_MSG_DATA:
			if (length >= DSU_HEADER_FULL + 8) {
				uint8_t registration = packet[20];
				uint8_t slot = packet[21];
				uint64_t mac = read_mac (packet + 22);
				gboolean requested = registration == DSU_REG_ALL ||
					((registration & DSU_REG_SLOT) && slot == 0) ||
					((registration & DSU_REG_MAC) && mac == DEVICE_MAC);
				if (requested)
					register_client (server, client_id,
							 (struct sockaddr *) &sender,
							 sender_length);
			}
			break;
		default:
			break;
		}
	}
	return G_SOURCE_CONTINUE;
}

static gboolean
initialize_sensors_once (MotionServer *server, GError **error)
{
	server->accelerometer = ssc_sensor_accelerometer_new_sync (NULL, error);
	if (server->accelerometer == NULL)
		return FALSE;

	server->gyroscope = ssc_sensor_gyroscope_new_sync (NULL, error);
	if (server->gyroscope == NULL)
		goto fail;
	ssc_sensor_set_sample_rate (SSC_SENSOR (server->accelerometer),
				    (gfloat) server->sample_rate);
	ssc_sensor_set_sample_rate (SSC_SENSOR (server->gyroscope),
				    (gfloat) server->sample_rate);

	g_signal_connect (server->accelerometer, "measurement",
			  G_CALLBACK (accelerometer_measurement), server);
	g_signal_connect (server->gyroscope, "measurement",
			  G_CALLBACK (gyroscope_measurement), server);

	if (!ssc_sensor_accelerometer_open_sync (server->accelerometer, NULL, error))
		goto fail;
	if (!ssc_sensor_gyroscope_open_sync (server->gyroscope, NULL, error)) {
		ssc_sensor_accelerometer_close_sync (server->accelerometer, NULL, NULL);
		goto fail;
	}
	return TRUE;

fail:
	g_clear_object (&server->gyroscope);
	g_clear_object (&server->accelerometer);
	return FALSE;
}

static gboolean
initialize_sensors (MotionServer *server)
{
	for (unsigned int attempt = 0; attempt < SENSOR_RETRY_COUNT; attempt++) {
		GError *error = NULL;
		if (initialize_sensors_once (server, &error))
			return TRUE;
		if (attempt == 0 || (attempt + 1) % 20 == 0)
			g_printerr ("Waiting for Qualcomm sensors (%u/%u): %s\n",
				    attempt + 1, SENSOR_RETRY_COUNT,
				    error != NULL ? error->message : "unknown error");
		g_clear_error (&error);
		g_usleep (SENSOR_RETRY_DELAY_US);
	}
	return FALSE;
}

static gboolean
open_server_socket (MotionServer *server, uint16_t port, GError **error)
{
	/*
	 * Match gcemuhook/evdevhook2: dual-stack UDP on :: (IPv4+IPv6).
	 * Binding only 127.0.0.1 breaks clients that resolve localhost as ::1.
	 */
	struct sockaddr_in6 address = {
		.sin6_family = AF_INET6,
		.sin6_port = htons (port),
		.sin6_addr = in6addr_any,
	};
	int flags;
	int v6only = 0;

	server->socket_fd = socket (AF_INET6, SOCK_DGRAM, IPPROTO_UDP);
	if (server->socket_fd < 0)
		goto fail;
	if (setsockopt (server->socket_fd, IPPROTO_IPV6, IPV6_V6ONLY,
			&v6only, sizeof (v6only)) < 0)
		goto fail;
	flags = fcntl (server->socket_fd, F_GETFL, 0);
	if (flags < 0 || fcntl (server->socket_fd, F_SETFL, flags | O_NONBLOCK) < 0)
		goto fail;
	if (bind (server->socket_fd, (struct sockaddr *) &address, sizeof (address)) < 0)
		goto fail;
	return TRUE;

fail:
	g_set_error (error, G_FILE_ERROR, g_file_error_from_errno (errno),
		     "Unable to open *:%u (IPv6 dual-stack): %s", port, g_strerror (errno));
	if (server->socket_fd >= 0) {
		close (server->socket_fd);
		server->socket_fd = -1;
	}
	return FALSE;
}

static gboolean
shutdown_signal (gpointer user_data)
{
	MotionServer *server = user_data;
	g_main_loop_quit (server->main_loop);
	return G_SOURCE_REMOVE;
}

static gboolean
calibration_timeout (gpointer user_data)
{
	MotionServer *server = user_data;

	g_printerr ("Gyro calibration timed out; keep the device still and try again\n");
	g_main_loop_quit (server->main_loop);
	return G_SOURCE_REMOVE;
}

static ssize_t
receive_message (int socket_fd,
		 uint32_t expected_type,
		 uint8_t *packet,
		 size_t capacity,
		 int timeout_ms)
{
	gint64 deadline = g_get_monotonic_time () + timeout_ms * 1000LL;

	while (g_get_monotonic_time () < deadline) {
		struct pollfd descriptor = { .fd = socket_fd, .events = POLLIN };
		int remaining = (int) ((deadline - g_get_monotonic_time () + 999) / 1000);
		int status = poll (&descriptor, 1, MAX (remaining, 1));
		if (status < 0 && errno == EINTR)
			continue;
		if (status <= 0)
			break;
		ssize_t length = recv (socket_fd, packet, capacity, 0);
		uint32_t type;
		if (length >= 0 && validate_header (packet, (size_t) length, 'S', NULL, &type) &&
		    type == expected_type)
			return length;
	}
	return -1;
}

static int
check_server (uint16_t port)
{
	struct sockaddr_in address = {
		.sin_family = AF_INET,
		.sin_port = htons (port),
		.sin_addr.s_addr = htonl (INADDR_LOOPBACK),
	};
	uint32_t client_id = g_random_int ();
	uint8_t request[32];
	uint8_t response[256];
	int socket_fd = socket (AF_INET, SOCK_DGRAM, IPPROTO_UDP);
	ssize_t length;

	if (socket_fd < 0 || connect (socket_fd, (struct sockaddr *) &address, sizeof (address)) < 0) {
		g_printerr ("FAIL: cannot connect to DSU server: %s\n", g_strerror (errno));
		if (socket_fd >= 0)
			close (socket_fd);
		return 1;
	}

	fill_header (request, 20, 'C', client_id, DSU_MSG_VERSION);
	finish_crc (request, 20);
	if (send (socket_fd, request, 20, 0) != 20 ||
	    receive_message (socket_fd, DSU_MSG_VERSION, response, sizeof (response), 1000) < 22) {
		g_printerr ("FAIL: DSU version request timed out\n");
		close (socket_fd);
		return 1;
	}

	fill_header (request, 25, 'C', client_id, DSU_MSG_PORTS);
	write_le32 (request + 20, 1);
	request[24] = 0;
	finish_crc (request, 25);
	if (send (socket_fd, request, 25, 0) != 25 ||
	    (length = receive_message (socket_fd, DSU_MSG_PORTS, response,
				       sizeof (response), 1000)) < 32 ||
	    response[20] != 0 || response[21] != DSU_SLOT_CONNECTED ||
	    response[22] != DSU_DEVICE_GYRO_FULL) {
		g_printerr ("FAIL: DSU motion slot 0 is unavailable\n");
		close (socket_fd);
		return 1;
	}

	fill_header (request, 28, 'C', client_id, DSU_MSG_DATA);
	request[20] = DSU_REG_SLOT;
	request[21] = 0;
	finish_crc (request, 28);
	if (send (socket_fd, request, 28, 0) != 28 ||
	    (length = receive_message (socket_fd, DSU_MSG_DATA, response,
				       sizeof (response), 2500)) < 100) {
		g_printerr ("FAIL: DSU motion data request timed out\n");
		close (socket_fd);
		return 1;
	}

	g_print ("PASS: DSU slot 0 accel=(%.4f, %.4f, %.4f) G ",
		 read_float_le (response + 76), read_float_le (response + 80),
		 read_float_le (response + 84));
	g_print ("gyro=(%.3f, %.3f, %.3f) deg/s\n",
		 read_float_le (response + 88), read_float_le (response + 92),
		 read_float_le (response + 96));
	close (socket_fd);
	return 0;
}

static void
close_sensors (MotionServer *server)
{
	if (server->gyroscope != NULL)
		ssc_sensor_gyroscope_close_sync (server->gyroscope, NULL, NULL);
	if (server->accelerometer != NULL)
		ssc_sensor_accelerometer_close_sync (server->accelerometer, NULL, NULL);
	g_clear_object (&server->gyroscope);
	g_clear_object (&server->accelerometer);
}

int
main (int argc, char **argv)
{
	MotionServer server = { .socket_fd = -1, .uinput_fd = -1, .enable_evdev = TRUE };
	gint port = DSU_DEFAULT_PORT;
	gint calibration_samples = GYRO_AUTO_CALIBRATION_SAMPLES;
	gboolean check = FALSE;
	gboolean calibrate = FALSE;
	gboolean no_evdev = FALSE;
	gchar *calibration_file = NULL;
	gchar *profile = NULL;
	GError *error = NULL;
	gchar ready_contents[16];

	server.gyro_deadzone = GYRO_DEFAULT_DEADZONE_DPS;
	server.sample_rate = MOTION_DEFAULT_SAMPLE_RATE_HZ;
	set_identity_accel_calibration (&server);
	GOptionEntry options[] = {
		{ "port", 'p', 0, G_OPTION_ARG_INT, &port, "DSU UDP port", "PORT" },
		{ "check", 'c', 0, G_OPTION_ARG_NONE, &check, "Probe a running bridge", NULL },
		{ "calibrate", 0, 0, G_OPTION_ARG_NONE, &calibrate,
		  "Collect and save stationary gyro calibration", NULL },
		{ "calibration-file", 0, 0, G_OPTION_ARG_FILENAME, &calibration_file,
		  "Persistent gyro calibration file", "FILE" },
		{ "profile", 0, 0, G_OPTION_ARG_STRING, &profile,
		  "Device coordinate profile (auto, thor, or odin2)", "PROFILE" },
		{ "calibration-samples", 0, 0, G_OPTION_ARG_INT, &calibration_samples,
		  "Stationary samples required for calibration", "COUNT" },
		{ "gyro-deadzone", 0, 0, G_OPTION_ARG_DOUBLE, &server.gyro_deadzone,
		  "Post-calibration gyro deadzone in degrees per second", "DPS" },
		{ "sample-rate", 0, 0, G_OPTION_ARG_DOUBLE, &server.sample_rate,
		  "Accelerometer and gyroscope sample rate in Hz", "HZ" },
		{ "raw-axes", 0, 0, G_OPTION_ARG_NONE, &server.raw_axes,
		  "Do not rotate handset coordinates into gamepad coordinates", NULL },
		{ "no-evdev", 0, 0, G_OPTION_ARG_NONE, &no_evdev,
		  "Do not export a uinput accelerometer/gyro for RPCS3/Evdev", NULL },
		{ "verbose", 'v', 0, G_OPTION_ARG_NONE, &server.verbose, "Verbose logging", NULL },
		{ NULL }
	};
	GOptionContext *context = g_option_context_new ("- Qualcomm SSC DSU motion bridge");

	g_option_context_add_main_entries (context, options, NULL);
	if (!g_option_context_parse (context, &argc, &argv, &error)) {
		g_printerr ("%s\n", error->message);
		g_clear_error (&error);
		g_option_context_free (context);
		g_free (calibration_file);
		g_free (profile);
		return 2;
	}
	g_option_context_free (context);
	server.enable_evdev = !no_evdev;
	if (!select_motion_profile (&server, profile, &error)) {
		g_printerr ("%s\n", error->message);
		g_clear_error (&error);
		g_free (calibration_file);
		g_free (profile);
		return 2;
	}
	if (calibration_file == NULL)
		calibration_file = g_strdup (default_calibration_file (&server));
	if (port < 1 || port > 65535) {
		g_printerr ("Port must be between 1 and 65535\n");
		g_free (calibration_file);
		g_free (profile);
		return 2;
	}
	if (calibration_samples < 0 || calibration_samples > 4096 ||
	    (calibrate && calibration_samples < 16)) {
		g_printerr ("Calibration samples must be 16-4096, or 0 to disable automatic calibration\n");
		g_free (calibration_file);
		g_free (profile);
		return 2;
	}
	if (server.gyro_deadzone < 0.0 || server.gyro_deadzone > 10.0) {
		g_printerr ("Gyro deadzone must be between 0 and 10 degrees per second\n");
		g_free (calibration_file);
		g_free (profile);
		return 2;
	}
	if (server.sample_rate < 20.0 || server.sample_rate > 400.0) {
		g_printerr ("Motion sample rate must be between 20 and 400 Hz\n");
		g_free (calibration_file);
		g_free (profile);
		return 2;
	}
	if (check) {
		int result = check_server ((uint16_t) port);
		g_free (calibration_file);
		g_free (profile);
		return result;
	}

	server.calibration_file = calibration_file;
	server.calibration_target = (guint) calibration_samples;
	server.calibration_mode = calibrate;
	server.main_loop = g_main_loop_new (NULL, FALSE);
	if (!calibrate) {
		if (!load_gyro_calibration (&server)) {
			server.gyro_calibrated = calibration_samples == 0;
			if (!server.gyro_calibrated)
				g_message ("Waiting for %d stationary gyro samples", calibration_samples);
		}
	} else {
		g_print ("Keep the device flat and still; collecting %d gyro samples\n",
			 calibration_samples);
	}

	if (!initialize_sensors (&server)) {
		g_printerr ("Unable to open Qualcomm accelerometer and gyroscope\n");
		g_main_loop_unref (server.main_loop);
		g_free (calibration_file);
		g_free (profile);
		return 1;
	}
	g_unix_signal_add (SIGINT, shutdown_signal, &server);
	g_unix_signal_add (SIGTERM, shutdown_signal, &server);
	if (calibrate) {
		g_timeout_add_seconds (GYRO_CALIBRATION_TIMEOUT_SECONDS,
				       calibration_timeout, &server);
		g_main_loop_run (server.main_loop);
		close_sensors (&server);
		g_main_loop_unref (server.main_loop);
		g_free (calibration_file);
		g_free (profile);
		return server.calibration_success ? 0 : 1;
	}
	if (!open_server_socket (&server, (uint16_t) port, &error)) {
		g_printerr ("%s\n", error->message);
		g_clear_error (&error);
		close_sensors (&server);
		g_main_loop_unref (server.main_loop);
		g_free (calibration_file);
		g_free (profile);
		return 1;
	}
	if (!open_evdev_motion_device (&server, &error)) {
		g_warning ("%s (continuing with DSU only)", error->message);
		g_clear_error (&error);
	}
	unlink (READY_FILE);
	g_snprintf (ready_contents, sizeof (ready_contents), "%d\n", port);
	if (!g_file_set_contents (READY_FILE, ready_contents, -1, &error)) {
		g_printerr ("Unable to create %s: %s\n", READY_FILE, error->message);
		g_clear_error (&error);
		close_evdev_motion_device (&server);
		close (server.socket_fd);
		close_sensors (&server);
		g_main_loop_unref (server.main_loop);
		g_free (calibration_file);
		g_free (profile);
		return 1;
	}

	server.server_id = g_random_int ();
	g_unix_fd_add_full (G_PRIORITY_HIGH, server.socket_fd,
			    G_IO_IN | G_IO_ERR | G_IO_HUP, socket_ready, &server, NULL);
	g_timeout_add_seconds (1, cleanup_clients, &server);
	g_message ("Qualcomm motion bridge ready for %s (%s) on *:%d (IPv4/IPv6) at %.0f Hz",
		   server.device_name, server.profile_name, port, server.sample_rate);
	g_main_loop_run (server.main_loop);

	unlink (READY_FILE);
	close_evdev_motion_device (&server);
	close_sensors (&server);
	close (server.socket_fd);
	g_main_loop_unref (server.main_loop);
	g_free (calibration_file);
	g_free (profile);
	return 0;
}
