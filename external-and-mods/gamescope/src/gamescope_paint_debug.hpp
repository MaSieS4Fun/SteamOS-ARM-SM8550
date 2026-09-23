#pragma once

#include <cstdint>
#include <cstdlib>
#include <cstring>

#include "log.hpp"

inline bool gamescope_debug_paint_enabled()
{
	static int s_nCached = -1;
	if ( s_nCached < 0 )
	{
		const char *pchEnv = getenv( "GAMESCOPE_DEBUG_PAINT" );
		s_nCached = ( pchEnv && pchEnv[0] && strcmp( pchEnv, "0" ) != 0 ) ? 1 : 0;
	}
	return s_nCached;
}

struct gamescope_paint_debug_snapshot_t
{
	uint32_t uTexW = 0;
	uint32_t uTexH = 0;
	uint32_t uSourceW = 0;
	uint32_t uSourceH = 0;
	uint32_t uCompOutW = 0;
	uint32_t uCompOutH = 0;
	uint32_t uPanelW = 0;
	uint32_t uPanelH = 0;
	uint32_t uFbW = 0;
	uint32_t uFbH = 0;
	float flScaleX = 0.0f;
	float flScaleY = 0.0f;
	float flOffsetX = 0.0f;
	float flOffsetY = 0.0f;
	uint32_t uRotation = 0;
	bool bComposite = false;
	bool bFullComposite = false;
	uint32_t uLayerCount = 0;
};

inline bool gamescope_paint_debug_changed( const gamescope_paint_debug_snapshot_t &cur, const gamescope_paint_debug_snapshot_t &prev )
{
	return memcmp( &cur, &prev, sizeof( cur ) ) != 0;
}

inline void gamescope_paint_debug_log( LogScope &log, const char *pchTag, const gamescope_paint_debug_snapshot_t &snap )
{
	log.infof(
		"[%s] layers=%u composite=%s full=%s rot=%u tex=%ux%u source=%ux%u comp_out=%ux%u panel=%ux%u fb=%ux%u scale=%.4f,%.4f offset=%.0f,%.0f",
		pchTag,
		snap.uLayerCount,
		snap.bComposite ? "yes" : "no",
		snap.bFullComposite ? "yes" : "no",
		snap.uRotation,
		snap.uTexW, snap.uTexH,
		snap.uSourceW, snap.uSourceH,
		snap.uCompOutW, snap.uCompOutH,
		snap.uPanelW, snap.uPanelH,
		snap.uFbW, snap.uFbH,
		snap.flScaleX, snap.flScaleY,
		snap.flOffsetX, snap.flOffsetY );
}

inline bool gamescope_paint_debug_should_emit( gamescope_paint_debug_snapshot_t &cur, gamescope_paint_debug_snapshot_t &prev, uint64_t ulNowNs, uint64_t ulMinIntervalNs = 2'000'000'000ull )
{
	static uint64_t s_ulLastEmitNs = 0;

	if ( !gamescope_debug_paint_enabled() )
		return false;

	const bool bChanged = gamescope_paint_debug_changed( cur, prev );
	const bool bInterval = ulNowNs - s_ulLastEmitNs >= ulMinIntervalNs;

	if ( !bChanged && !bInterval )
		return false;

	prev = cur;
	s_ulLastEmitNs = ulNowNs;
	return true;
}
