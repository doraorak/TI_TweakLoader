// The processes that must never receive TI_TweakLoader.dylib.
//
// One list for every place that decides to inject: the launchd and xpcproxy
// spawn hooks, and the loader's own spawn hook for the processes an injected
// process starts. Each entry is something that broke.
#pragma once

#include <string.h>

static const char *process_blacklist[] = {
    // Core system log & diagnostics
    "logd",
    "syslogd",
    "diagnosticd",
    "notifyd",
    "distnoted",
    // Preference and launch-services plumbing: nearly every launch goes through
    // these, and the loader hooks CFPreferences, so injecting them is circular.
    "cfprefsd",
    "launchservicesd",
    "configd",
    // Core launch & session supervision
    "launchd",
    "sessionproxy",
    // Security, Authentication & Login Framework (DO NOT INJECT — causes loginwindow deadlocks on ldrestart)
    "opendirectoryd",
    "sandboxd",
    "securityd",
    "securityd_system",
    "secd",
    "secinitd",
    "trustd",
    "GSSCred",
    "loginwindow",
    "LoginUserService",
    "SecurityAgent",
    "authorizationhost",
    "authd",
    "coreauthd",
    "online-auth-agent",
    "applekeystored",
    "keybagd",
    "biometrickitd",
    "taskgated",
    // Code signing: injecting the validator that authorises injection is a
    // loop, and a wedged amfid stalls every exec on the machine.
    "amfid",
    "UserSelector",
    "ScreenTimeAgent",
    "UserEventAgent",
    "runningboardd",
    "containermanagerd",
    "containermanagerd_system",
    "systemstats",
    "AccessibilityUIServer",
    // GPU shader compilation. Every app's Metal work funnels through this XPC
    // service, so a hooked function in it stalls the GPU pipeline machine-wide,
    // not just for the app that triggered the compile. Measured: three
    // instances each burning 2.6s of their 3.6s total CPU inside ElleKit's
    // exception handler, with Chrome blocked behind them on a turnstile --
    // which is what froze a Cloudflare checkbox, and what left processes alive
    // through shutdown until the watchdog reset the machine.
    "MTLCompilerService",
    // Apple system services that break when injected, and that no tweak
    // targets. Metal's other background tools:
    "MTLReplayer",
    "MTLAssetUpgraderD",
    // Wi-Fi:
    "airportd",
    "WiFiAgent",
    "WiFiCloudAssetsXPCService",
    "wifianalyticsd",
    "wifip2pd",
    // Network extensions and VPN sessions:
    "neagent",
    "nesessionmanager",
    // Early-boot filesystem tools. launchd runs these to bring the volumes up
    // BEFORE it starts amfid, so a code signature the kernel has not cached
    // yet cannot be validated and dyld aborts the process. These are
    // boot-critical, and a boot-critical task dying panics the kernel exactly
    // the way PID 1 does -- measured, as mount[1668] taking the machine down
    // over TI_TweakLoader.dylib. ldrestart pre-warms the signatures to stop
    // that happening at all; this list is the belt to that pair of braces, and
    // costs nothing, since none of these is anybody's tweak target.
    "mount",
    "mount_apfs",
    "umount",
    "fsck",
    "fsck_apfs",
    "apfsd",
    // Storage & Power
    "diskarbitrationd",
    "powerd",
    "kernelmanagerd",
    // The managing front-end and privileged helper
    "TweakInject",
    "com.doraorak.tweakinject.helper",
};

static int is_path_blacklisted_from_injection(const char *path) {
    if (path == NULL) {
        return 0;
    }

    if (strstr(path, ".dext/") != NULL) {
        return 1;
    }

    const char *name = strrchr(path, '/');
    name = name ? name + 1 : path;

    for (size_t i = 0; i < sizeof(process_blacklist) / sizeof(*process_blacklist); i++) {
        if (strcmp(name, process_blacklist[i]) == 0) {
            return 1;
        }
    }

    return 0;
}
