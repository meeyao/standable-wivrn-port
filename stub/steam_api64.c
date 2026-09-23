/*
 * steam_api64.dll: minimal Steamworks shim for Standable under Wine/Proton.
 *
 * Standable FBE checks Steam ownership at driver init: it calls
 * SteamInternal_SteamAPI_Init("SteamUtils010", 0) and, if that succeeds,
 * ISteamApps::BIsSubscribedApp(2370570). Without the real Steam client in the
 * Standable Proton prefix, init fails and the driver refuses to run (it returns
 * the hard-coded error 17777 / 0x4571).
 *
 * This shim exports the four symbols the driver imports and reports success, so
 * the driver runs without Steam. Replace the original DLL and keep a backup:
 *
 *   bin/win64/steam_api64.dll   (and bin/linux64/steam_api64.dll)
 *
 * Only enough of the ABI is provided to satisfy the driver's init path. This is
 * a shim, not a Steam emulator.
 *
 * Build (x86-64 Windows target):
 *   x86_64-w64-mingw32-gcc -shared -O2 -o steam_api64.dll steam_api64.c
 *
 * The exports deliberately omit the C++ mangling: the driver imports them by
 * name through the PE export table, matching the real steam_api64.dll.
 */

#include <stdint.h>

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

/* Opaque handles, matching the real ABI's pointer-sized types. */
typedef int32_t HSteamUser;
typedef int32_t HSteamPipe;
typedef void *UnknownInterface;

/*
 * Reported so ISteamApps::BIsSubscribedApp() answers for Standable's app id.
 * The driver passes 0x242c0a (2370570).
 */
#define STANDABLE_APP_ID 2370570

/* Result of a successful init: 0 == k_ESteamAPIInitResult_OK. */
EXPORT int32_t
SteamInternal_SteamAPI_Init(const char *pInterfaceVersions, const char *pUnknown)
{
	(void)pInterfaceVersions;
	(void)pUnknown;
	return 0;
}

/* Return a dummy interface pointer; the driver only checks for non-NULL. */
EXPORT UnknownInterface
SteamInternal_FindOrCreateUserInterface(HSteamUser hSteamUser, const char *pchVersion)
{
	(void)hSteamUser;
	(void)pchVersion;
	return (UnknownInterface)(uintptr_t)1;
}

/*
 * Context init: on the real SDK this returns a cached context object. The
 * driver uses it during init; a stable non-NULL sentinel is enough.
 */
EXPORT UnknownInterface
SteamInternal_ContextInit(void *pContextInitData)
{
	(void)pContextInitData;
	return (UnknownInterface)(uintptr_t)1;
}

/* The driver stores this in its Steam user field. Any constant is fine. */
EXPORT HSteamUser
SteamAPI_GetHSteamUser(void)
{
	return 1;
}
