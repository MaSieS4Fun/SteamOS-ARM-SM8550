#include "backlight.hpp"

#include "convar.h"
#include "log.hpp"

#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <grp.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <mutex>
#include <optional>
#include <string>
#include <unistd.h>

namespace gamescope
{
	static LogScope s_BacklightLog( "backlight" );

	static ConVar<std::string> cv_backlight_path(
		"backlight_path",
		"",
		"Sysfs backlight directory or brightness file. Empty = auto-detect the first /sys/class/backlight device." );

	static ConVar<float> cv_backlight_max_nits(
		"backlight_max_nits",
		500.0f,
		"Nits that map to 100% backlight when Steam sends a nits value." );

	static ConVar<float> cv_backlight_min_nits(
		"backlight_min_nits",
		5.0f,
		"Nits that map to the lowest usable backlight when Steam sends a nits value." );

	static std::mutex s_Mutex;
	static std::string s_BrightnessPath;
	static int s_nMax = 0;
	static int s_nFd = -1;
	static float s_flLastNorm = 1.0f;
	static bool s_bHardwareOk = false;

	static bool ReadIntFile( const std::string &path, int &out )
	{
		std::ifstream in( path );
		if ( !in )
			return false;
		in >> out;
		return bool( in );
	}

	static bool TryRelaxPermissions( const std::string &path )
	{
		if ( geteuid() != 0 )
			return false;

		group *pVideo = getgrnam( "video" );
		if ( pVideo )
			(void) chown( path.c_str(), static_cast<uid_t>( -1 ), pVideo->gr_gid );

		return chmod( path.c_str(), 0664 ) == 0;
	}

	static std::string BrightnessFileFromDir( const std::string &dir )
	{
		std::filesystem::path p( dir );
		if ( p.filename() == "brightness" )
			return p.string();
		return ( p / "brightness" ).string();
	}

	static bool OpenBrightnessFile( const std::string &path )
	{
		if ( s_nFd >= 0 )
		{
			close( s_nFd );
			s_nFd = -1;
		}

		TryRelaxPermissions( path );

		s_nFd = open( path.c_str(), O_RDWR | O_CLOEXEC );
		if ( s_nFd < 0 )
			s_nFd = open( path.c_str(), O_WRONLY | O_CLOEXEC );
		if ( s_nFd < 0 )
		{
			s_BacklightLog.warnf( "Cannot open %s: %s", path.c_str(), strerror( errno ) );
			return false;
		}

		s_BrightnessPath = path;
		return true;
	}

	static std::optional<std::string> PickBacklightDevice()
	{
		const char *pszEnv = getenv( "GAMESCOPE_BACKLIGHT_PATH" );
		if ( pszEnv && *pszEnv )
			return std::string( pszEnv );

		std::string sOverride = cv_backlight_path;
		if ( !sOverride.empty() )
			return sOverride;

		namespace fs = std::filesystem;
		const fs::path root{ "/sys/class/backlight" };
		if ( !fs::exists( root ) )
			return std::nullopt;

		std::string sBest;
		int nBestScore = -1;
		for ( const auto &entry : fs::directory_iterator( root ) )
		{
			if ( !entry.is_directory() && !entry.is_symlink() )
				continue;

			const fs::path dir = entry.path();
			int nMax = 0;
			if ( !ReadIntFile( ( dir / "max_brightness" ).string(), nMax ) || nMax <= 0 )
				continue;

			std::string sType;
			{
				std::ifstream in( dir / "type" );
				in >> sType;
			}

			// Prefer a real panel backlight over firmware/ACPI leftovers.
			int nScore = 1;
			if ( sType == "raw" || sType == "platform" )
				nScore = 10;
			else if ( sType == "firmware" )
				nScore = 5;
			if ( dir.filename() == "backlight" )
				nScore += 2;
			if ( nScore > nBestScore )
			{
				nBestScore = nScore;
				sBest = dir.string();
			}
		}

		if ( sBest.empty() )
			return std::nullopt;
		return sBest;
	}

	static bool WriteRawLocked( int nValue )
	{
		if ( s_nFd < 0 || s_nMax <= 0 )
			return false;

		nValue = std::clamp( nValue, 0, s_nMax );
		char buf[ 32 ];
		int nLen = snprintf( buf, sizeof( buf ), "%d\n", nValue );
		if ( nLen <= 0 )
			return false;

		if ( lseek( s_nFd, 0, SEEK_SET ) < 0 )
		{
			// Some sysfs nodes are not seekable; retry with a fresh open.
			if ( !OpenBrightnessFile( s_BrightnessPath ) )
				return false;
		}

		ssize_t nWrote = write( s_nFd, buf, static_cast<size_t>( nLen ) );
		if ( nWrote != nLen )
		{
			s_BacklightLog.warnf( "write(%s) failed: %s", s_BrightnessPath.c_str(), strerror( errno ) );
			return false;
		}

		return true;
	}

	void InitBacklight()
	{
		std::lock_guard<std::mutex> lock( s_Mutex );

		auto oDev = PickBacklightDevice();
		if ( !oDev )
		{
			s_BacklightLog.warnf( "No /sys/class/backlight device. Brightness will use a software fallback." );
			s_bHardwareOk = false;
			return;
		}

		const std::string sDir = *oDev;
		const std::string sFile = BrightnessFileFromDir( sDir );
		const std::filesystem::path dir = std::filesystem::path( sFile ).parent_path();

		if ( !ReadIntFile( ( dir / "max_brightness" ).string(), s_nMax ) || s_nMax <= 0 )
		{
			s_BacklightLog.errorf( "Invalid max_brightness for %s", sDir.c_str() );
			s_bHardwareOk = false;
			return;
		}

		int nCurrent = s_nMax;
		ReadIntFile( ( dir / "actual_brightness" ).string(), nCurrent );
		if ( nCurrent <= 0 )
			ReadIntFile( sFile, nCurrent );

		s_flLastNorm = std::clamp( float( nCurrent ) / float( s_nMax ), 0.0f, 1.0f );
		s_bHardwareOk = OpenBrightnessFile( sFile );
		s_BacklightLog.infof( "%s backlight %s (max=%d current=%d)",
			s_bHardwareOk ? "Using" : "Found but cannot write",
			sFile.c_str(), s_nMax, nCurrent );
	}

	static float SteamValueToNormalized( float flVal )
	{
		if ( !std::isfinite( flVal ) )
			return s_flLastNorm;

		if ( flVal <= 1.0f )
			return std::clamp( flVal, 0.0f, 1.0f );

		if ( flVal <= 100.0f )
			return std::clamp( flVal / 100.0f, 0.0f, 1.0f );

		const float flMin = std::max( 0.0f, float( cv_backlight_min_nits ) );
		const float flMax = std::max( flMin + 1.0f, float( cv_backlight_max_nits ) );
		return std::clamp( ( flVal - flMin ) / ( flMax - flMin ), 0.0f, 1.0f );
	}

	bool SetBacklightNormalized( float flNorm )
	{
		flNorm = std::clamp( flNorm, 0.0f, 1.0f );

		std::lock_guard<std::mutex> lock( s_Mutex );
		s_flLastNorm = flNorm;

		if ( s_nFd < 0 || s_nMax <= 0 )
		{
			s_bHardwareOk = false;
			return true;
		}

		// Keep a small floor so the panel never looks powered off by accident.
		const int nMin = std::max( 1, s_nMax / 64 );
		const int nValue = std::max( nMin, int( std::lround( flNorm * float( s_nMax ) ) ) );
		s_bHardwareOk = WriteRawLocked( nValue );
		return true;
	}

	float GetBacklightNormalized()
	{
		std::lock_guard<std::mutex> lock( s_Mutex );
		return s_flLastNorm;
	}

	bool HasHardwareBacklight()
	{
		std::lock_guard<std::mutex> lock( s_Mutex );
		return s_bHardwareOk && s_nFd >= 0;
	}

	float GetSoftwareBacklightGain()
	{
		std::lock_guard<std::mutex> lock( s_Mutex );
		if ( s_bHardwareOk )
			return 1.0f;

		// Perceptual-ish curve so 50% on the slider is not a black image.
		const float flFloor = 0.08f;
		return flFloor + ( 1.0f - flFloor ) * std::pow( std::clamp( s_flLastNorm, 0.0f, 1.0f ), 2.2f );
	}

	bool ApplySteamBrightnessValue( float flVal )
	{
		const float flNorm = SteamValueToNormalized( flVal );
		return SetBacklightNormalized( flNorm );
	}

	bool StepBacklight( int nDirection )
	{
		if ( nDirection == 0 )
			return false;

		const float flStep = 0.05f;
		const float flNext = std::clamp( GetBacklightNormalized() + flStep * float( nDirection ), 0.0f, 1.0f );
		return SetBacklightNormalized( flNext );
	}
}
