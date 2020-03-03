#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <clientprefs>

#define PLUGIN_VERSION "0.2"

enum {
    WEAPONTYPE_UNKNOWN = -1,
    WEAPONTYPE_KNIFE = 0,
    WEAPONTYPE_PISTOL = 1,
    WEAPONTYPE_SUBMACHINEGUN = 2,
    WEAPONTYPE_RIFLE = 3,
    WEAPONTYPE_SHOTGUN = 4,
    WEAPONTYPE_SNIPER_RIFLE = 5,
    WEAPONTYPE_MACHINEGUN = 6,
    WEAPONTYPE_C4 = 7,
    WEAPONTYPE_TASER = 8,
    WEAPONTYPE_GRENADE = 9,
    WEAPONTYPE_HEALTHSHOT = 11
};

public Plugin myinfo = {
    name = "CSGO Aim Nitpick",
    description = "CSGO aim inaccuracy check via server plugin -- Sound beeps to differentiate aim and strafe mistakes, etc.",
    author = "Rain",
    version = PLUGIN_VERSION,
    url = "https://github.com/Rainyan/sourcemod-nt-nitpick"
};

enum MistakeSound {
    CROSSHAIR_PLACEMENT_INCORRECT = 0,
    ALL_OK,
    COUNTERSTRAFE_INCORRECT,
    SHOT_DID_NOT_CONNECT,
    MULTIPLE_FAILED
}

new const String:g_sSounds[][] = {
    "buttons/button16.wav",
    "buttons/button17.wav",
    "buttons/button18.wav",
    "buttons/button6.wav",
    "buttons/button19.wav"
};

bool g_bWantsAimNote[MAXPLAYERS+1];
bool g_bDidConnectSShot[MAXPLAYERS+1];
bool g_bHoldsShootable[MAXPLAYERS+1];
bool g_bOnlyFails[MAXPLAYERS+1];
bool g_bUseSounds[MAXPLAYERS+1];

static int g_iNitLvl[MAXPLAYERS+1];

float g_flStrafeThreshold[MAXPLAYERS+1];

ConVar g_cAimThreshold = null, g_cOkVerbosity = null;

enum {
    NOTE_NONE = 0,
    NOTE_STRAFE,
    NOTE_ALL,
    NOTE_ENUM_COUNT
};

int g_iDefaultNotify = NOTE_STRAFE;
bool g_bDefaultOnlyFails = false;
bool g_bDefaultUseSounds = true;

new const String:g_sDisEn[][] = { "dis", "en" };

new const String:g_sNitStyle[NOTE_ENUM_COUNT][] = {
    "none",
    "only counterstrafe mistakes",
    "all mistakes"
};

enum {
    COOKIE_ENABLED,
    COOKIE_LEVEL,
    COOKIE_USE_SOUND,
    COOKIE_ONLY_FAILS,
    COOKIE_STRAFE_THRESHOLD,
    COOKIE_ENUM_COUNT
};

new const String:g_sCookies[COOKIE_ENUM_COUNT][] = {
    "nitpick_enabled",
    "nitpick_level",
    "nitpick_use_sound",
    "nitpick_only_fails",
    "nitpick_strafe_threshold"
};

new const String:g_sCookiesDesc[COOKIE_ENUM_COUNT][] = {
    "Toggle nitpick on/off for yourself.",
    "Set the nitpick level.",
    "Whether to play sound feedback.",
    "Whether to only notify on mistakes.",
    "Custom threshold for counterstrafe inaccuracy."
};

Handle cookies[COOKIE_ENUM_COUNT];

public void OnPluginStart()
{
    g_cAimThreshold = CreateConVar("sm_nitpick_vel_threshold", "32",
        "Max acceptable velocity considered as accurate aim.",
        _, true, 0.0);
    
    g_cOkVerbosity = CreateConVar("sm_nitpick_ok_verbosity", "1",
        "Whether to notify player of correct shots",
        _, true, 0.0, true, 1.0);

    RegConsoleCmd("sm_nitpick", Cmd_ToggleAimNote);
    RegConsoleCmd("sm_nitpick_toggle", Cmd_ToggleAimNote);
    RegConsoleCmd("sm_nitpick_level", Cmd_NitpickLevel);
    RegConsoleCmd("sm_nitpick_use_sound", Cmd_SetUseSound);
    RegConsoleCmd("sm_nitpick_only_fails", Cmd_SetOnlyFails);
    RegConsoleCmd("sm_nitpick_strafe_threshold", Cmd_StrafeThreshold);
    RegConsoleCmd("sm_nitpick_help", Cmd_Help);
    
    for (int i = 0; i < sizeof(g_sSounds); i++) {
        if (!PrecacheSound(g_sSounds[i])) {
            SetFailState("Failed to precache sound: %s", g_sSounds[i]);
        }
    }
        
    for (int i = 1; i <= MaxClients; i++) {
        g_iNitLvl[i] = g_iDefaultNotify;
        g_bUseSounds[i] = g_bDefaultUseSounds;
        g_bOnlyFails[i] = g_bDefaultOnlyFails;
        g_flStrafeThreshold[i] = g_cAimThreshold.FloatValue;
    }
    
    for (int i = 0; i < sizeof(cookies); i++)
    {
        RegClientCookie(g_sCookies[i], g_sCookiesDesc[i], CookieAccess_Public);
        
        cookies[i] = FindClientCookie(g_sCookies[i]);
        if (cookies[i] == INVALID_HANDLE)
        {
            SetFailState("Failed to get cookie handle for \"%s\"",
                g_sCookies[i]);
        }
    }
    
    SetCookiePrefabMenu(cookies[COOKIE_ENABLED], CookieMenu_YesNo,
        g_sCookiesDesc[COOKIE_ENABLED], SetCookie_IntVal, COOKIE_ENABLED);
    
    SetCookieMenuItem(SetCookie_NitLevel, COOKIE_LEVEL,
        g_sCookiesDesc[COOKIE_LEVEL]);
    
    SetCookiePrefabMenu(cookies[COOKIE_ONLY_FAILS], CookieMenu_OnOff_Int,
        g_sCookiesDesc[COOKIE_ONLY_FAILS], SetCookie_IntVal, COOKIE_ONLY_FAILS);
    
    SetCookiePrefabMenu(cookies[COOKIE_USE_SOUND], CookieMenu_OnOff_Int,
        g_sCookiesDesc[COOKIE_USE_SOUND], SetCookie_IntVal, COOKIE_USE_SOUND);
    
    SetCookieMenuItem(SetCookie_StrafeThreshold, COOKIE_STRAFE_THRESHOLD,
        g_sCookiesDesc[COOKIE_STRAFE_THRESHOLD]);
    
    HookEvent("player_hurt", AttackHappened, EventHookMode_Pre);
    HookEvent("item_equip", ItemEquip, EventHookMode_Post);
}

public void SetCookie_IntVal(int client, CookieMenuAction action, int info, char[] buffer, int maxlen)
{
    if (info == COOKIE_ENABLED)
    {
        bool enabled = view_as<bool>(StringToInt(buffer));
        SetAimNote(client, enabled, false);
    }
    else if (info == COOKIE_ONLY_FAILS)
    {
        g_bOnlyFails[client] = view_as<bool>(StringToInt(buffer));
    }
    else if (info == COOKIE_USE_SOUND)
    {
        g_bUseSounds[client] = view_as<bool>(StringToInt(buffer));
    }
    else
    {
        PrintToChat(client, "Unknown Nitpick cookie.");
        ThrowError("Unknown nitpick cookie: %i", info);
    }  
    
    PrintToChat(client, " \x01\x0B\x03%s: %sabled",
        g_sCookiesDesc[info],
        g_sDisEn[g_bWantsAimNote[client]]);
}

void SetCookie_NitLevel(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
    strcopy(buffer, maxlen, g_sCookiesDesc[COOKIE_LEVEL]);
    
    if (action == CookieMenuAction_SelectOption)
    {
        g_iNitLvl[client] = StringToInt(buffer);
        
        PrintToChat(client, " \x01\x0B\x03[SM] Now notifying on: %s", g_sNitStyle[g_iNitLvl[client]]);
    }
}

void SetCookie_StrafeThreshold(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
    if (action == CookieMenuAction_SelectOption)
    {
        g_flStrafeThreshold[client] = StringToFloat(buffer);
        
        PrintToChat(client, " \x01\x0B\x03[SM] Your counterstrafe threshold is now: %.2f",
            g_flStrafeThreshold[client]);
    
        PrintToChat(client, " \x01\x0B\x03If you want to revert it, the server default is: %.2f",
            g_cAimThreshold.FloatValue);
    }
}

public void OnClientPutInServer(int client)
{
    if (!IsFakeClient(client) && IsClientInGame(client))
    {
        if (AreClientCookiesCached(client))
        {
            LoadCookiesToMemory(client);
        }
    }
}

public void OnClientCookiesCached(int client)
{
    if (!IsFakeClient(client) && IsClientInGame(client))
    {
        LoadCookiesToMemory(client);
    }
}

void LoadCookiesToMemory(int client)
{
    char cookieBuffer[16];
    for (int i = 0; i < sizeof(cookies); i++)
    {
        GetClientCookie(client, cookies[i],
            cookieBuffer, sizeof(cookieBuffer));
        
        switch(i)
        {
            case COOKIE_ENABLED:
            {
                bool enabled = view_as<bool>(StringToInt(cookieBuffer));
                SetAimNote(client, enabled);
                break;
            }
            
            case COOKIE_LEVEL:
            {
                if (g_bWantsAimNote[client])
                {
                    g_iNitLvl[client] = StringToInt(cookieBuffer);
                }
                break;
            }
            
            case COOKIE_ONLY_FAILS:
            {
                g_bOnlyFails[client] = view_as<bool>(StringToInt(cookieBuffer));
                break;
            }
            
            case COOKIE_STRAFE_THRESHOLD:
            {
                g_flStrafeThreshold[client] = view_as<float>(StringToInt(cookieBuffer));
                break;
            }
            
            case COOKIE_USE_SOUND:
            {
                g_bUseSounds[client] = view_as<bool>(StringToInt(cookieBuffer));
                break;
            }
            
            default:
            {
                break;
            }
        }
    }
}

public void OnClientDisconnect(int client)
{
    g_bHoldsShootable[client] = false;
    g_iNitLvl[client] = g_iDefaultNotify;
    g_bUseSounds[client] = g_bDefaultUseSounds;
    g_bOnlyFails[client] = g_bDefaultOnlyFails;
    g_flStrafeThreshold[client] = g_cAimThreshold.FloatValue;
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse,
    const float vel[3], const float angles[3], int weapon, int subtype,
    int cmdnum, int tickcount, int seed, const int mouse[2])
{
    if (g_bWantsAimNote[client] && g_bHoldsShootable[client] && g_iNitLvl[client] > NOTE_NONE) {
        static int prevButtons[MAXPLAYERS+1] = 0;
        static float currentVel[MAXPLAYERS+1][3];
        if (buttons & IN_ATTACK) {
            if (prevButtons[client] & IN_ATTACK) {
                
            }
            else {
                GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", currentVel[client]);
                CheckForMistake(client, currentVel[client]);
            }
        }
        prevButtons[client] = buttons;
    }
}

public Action Cmd_MainMenu(int client, int argc)
{
    ShowCookieMenu(client);
    
    return Plugin_Handled;
}

public Action Cmd_StrafeThreshold(int client, int argc)
{
    if (argc < 1)
    {
        ReplyToCommand(client, "[SM] Max acceptable velocity considered as accurate aim.");
        ReplyToCommand(client, "Usage: sm_nitpick_strafe_threshold <value> (default value: %.2f)",
            g_cAimThreshold.FloatValue);
        return Plugin_Stop;
    }
    
    char arg[16];
    GetCmdArg(1, arg, sizeof(arg));
    float argFloat = StringToFloat(arg);
    
    g_flStrafeThreshold[client] = argFloat;
    SetClientCookie(client, cookies[COOKIE_STRAFE_THRESHOLD], arg);
    
    ReplyToCommand(client, " \x01\x0B\x03[SM] Your counterstrafe threshold is now: %.2f",
        g_flStrafeThreshold[client]);
    
    ReplyToCommand(client, " \x01\x0B\x03If you want to revert it, the server default is: %.2f",
        g_cAimThreshold.FloatValue);
    
    return Plugin_Handled;
}

public Action Cmd_Help(int client, int argc)
{
    ReplyToCommand(client, " \x01\x0B\x03[SM] AimNote commands:");
    ReplyToCommand(client, " \x01\x0B\x03[SM] sm_nitpick -- alias for sm_nitpick_toggle");
    ReplyToCommand(client, "[SM] sm_nitpick_toggle -- Enable/disable this feature for yourself.");
    ReplyToCommand(client, "[SM] sm_nitpick_level -- Set mistake level.");
    ReplyToCommand(client, "[SM] sm_nitpick_use_sound -- Whether or not to play sound effect.");
    ReplyToCommand(client, "[SM] sm_nitpick_only_fails -- Whether to only announce mistakes.");
    ReplyToCommand(client, "[SM] sm_nitpick_strafe_threshold -- Max acceptable velocity considered as accurate aim.");
    ReplyToCommand(client, "[SM] sm_nitpick_help -- Show this help list.");
    return Plugin_Handled;
}

public Action Cmd_ToggleAimNote(int client, int argc)
{
    if (client == 0) {
        ReplyToCommand(client, "This command cannot be run by server.");
        return Plugin_Stop;
    }
    
    SetAimNote(client, !g_bWantsAimNote[client]);
    SetClientCookie(client, cookies[COOKIE_ENABLED], g_bWantsAimNote[client] ? "1" : "0");
    
    return Plugin_Handled;
}

void PrintNitNoteHelp(int client)
{
    PrintToChat(client, "[SM] Nitpick style setter. Usage: sm_nitpick_level <number>");
    PrintToChat(client, "Your current setting is: %s", g_sNitStyle[g_iNitLvl[client]]);
    PrintToChat(client, "Accepted values are:");
    for (int i = 0; i < NOTE_ENUM_COUNT; i++)
    {
        PrintToChat(client, "%i -- %s", i, g_sNitStyle[i]);
    }
}

public Action Cmd_NitpickLevel(int client, int argc)
{
    if (argc < 1)
    {
        PrintNitNoteHelp(client);
        return Plugin_Stop;
    }
    
    char arg[16];
    GetCmdArg(1, arg, sizeof(arg));
    int argInt = StringToInt(arg);
    
    //PrintToChat(client, "argc: %i argInt: %i arg: %s", argc, argInt, arg);
    
    
    if (argInt < 0 || argInt >= NOTE_ENUM_COUNT)
    {
        ReplyToCommand(client, " \x01\x0B\x07[SM] Unknown value");
        PrintNitNoteHelp(client);
        return Plugin_Stop;
    }
    
    g_iNitLvl[client] = StringToInt(arg);
    SetClientCookie(client, cookies[COOKIE_LEVEL], arg);
    
    
    ReplyToCommand(client, " \x01\x0B\x03[SM] Now notifying on: %s", g_sNitStyle[g_iNitLvl[client]]);
    
    return Plugin_Handled;
}

public Action Cmd_SetUseSound(int client, int argc)
{
    if (argc < 1)
    {
        ReplyToCommand(client, "[SM] Whether to play sounds. Usage: sm_nitpick_use_sound 1/0");
        return Plugin_Stop;
    }
    
    char arg[16];
    GetCmdArg(1, arg, sizeof(arg));
    int argInt = StringToInt(arg);
    
    g_bUseSounds[client] = view_as<bool>(argInt);
    SetClientCookie(client, cookies[COOKIE_USE_SOUND], arg);
    
    PrintToChat(client, " \x01\x0B\x03Playing sound feedback is now: %sabled", g_sDisEn[g_bUseSounds[client]]);
    
    return Plugin_Handled;
}

public Action Cmd_SetOnlyFails(int client, int argc)
{
    if (argc < 1)
    {
        ReplyToCommand(client, "[SM] Whether to only announce mistakes. Usage: sm_nitpick_only_fails 1/0");
        return Plugin_Stop;
    }
    
    char arg[16];
    GetCmdArg(1, arg, sizeof(arg));
    int argInt = StringToInt(arg);
    
    g_bOnlyFails[client] = view_as<bool>(argInt);
    SetClientCookie(client, cookies[COOKIE_ONLY_FAILS], arg);
    
    PrintToChat(client, " \x01\x0B\x03Only mistake announcing is now: %sabled", g_sDisEn[g_bOnlyFails[client]]);
    
    return Plugin_Handled;
}

public Action AttackHappened(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    
    if (IsValidClient(attacker) && attacker != victim) {
        g_bDidConnectSShot[attacker] = true;
    }
}

public void ItemEquip(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client) && IsClientConnected(client)) {
        int weptype = event.GetInt("weptype");
        if (weptype == WEAPONTYPE_KNIFE || weptype == WEAPONTYPE_GRENADE
            || weptype == WEAPONTYPE_C4)
        {
            g_bHoldsShootable[client] = false;
            /*PrintToChat(client, "Weptype: %i, knife: %i, gren: %i, c4: %i",
                weptype, WEAPONTYPE_KNIFE, WEAPONTYPE_GRENADE,
                WEAPONTYPE_C4);*/
        }
        else {
            g_bHoldsShootable[client] = true;
            //PrintToChat(client, "Holds shootable");
        }
    }
}

bool IsShootable(const char[] wepName)
{
    const int len = 7;
    new const String:beginningLetters[len] = "weapon_";
    for (int i = 0; i < len; i++) {
        if (wepName[i] != beginningLetters[i]) {
            return false;
        }
    }
    bool notShootable = (wepName[len] == 'k' && wepName[len+1] == 'n') // knife
        || (wepName[len] == 'f' && wepName[len+1] == 'l') // flash
        || (wepName[len] == 'h' && wepName[len+1] == 'e') // HE
        || (wepName[len] == 's' && wepName[len+1] == 'm') // smoke
        || (wepName[len] == 'm' && wepName[len+1] == 'o') // molotov
        || (wepName[len] == 'i' && wepName[len+1] == 'n') // inc grenade
        || (wepName[len] == 'z' && wepName[len+1] == 'e') // zeus
        || (wepName[len] == 'c' && wepName[len+1] == '4') // C4
        || (wepName[len] == 'd' && wepName[len+1] == 'e' && wepName[len+2] == 'c'); // decoy
    return !notShootable;
}

void SetAimNote(int client, bool enabled, bool verbose = true)
{
    g_bWantsAimNote[client] = enabled;
    
    if (g_bWantsAimNote[client]) {
        
        decl String:wepName[64];
        GetClientWeapon(client, wepName, sizeof(wepName));
        g_bHoldsShootable[client] = IsShootable(wepName);
        /*PrintToChat(client, "Wepname: %s (shootable: %b)",
            wepName, g_bHoldsShootable[client]);*/
    }
    
    if (verbose) {
        PrintToChat(client, " \x01\x0B\x03Your AimNote is now %sabled", g_sDisEn[g_bWantsAimNote[client]]);
    }
}

void CheckForMistake(int client, const float velocity[3])
{
    bool strafeOk = true;
    if (g_iNitLvl[client] >= NOTE_STRAFE)
    {
        for (int i = 0; i < sizeof(velocity); i++) {
            if (FloatAbs(velocity[i]) > g_flStrafeThreshold[client]) {
                strafeOk = false;
                break;
            }
        }
    }
    
    float pos[3];
    GetClientEyePosition(client, pos);
    
    float angles[3];
    GetClientEyeAngles(client, angles);
    
    Handle ray = TR_TraceRayFilterEx(pos, angles, MASK_SHOT, RayType_Infinite,
        DidNotHitShooter, client);
    int hitEnt = TR_GetEntityIndex(ray);
    delete ray;
    
    bool aimOk = false;
    if (g_iNitLvl[client] < NOTE_ALL)
    {
        aimOk = true;
    }
    else
    {
        if (IsValidEntity(hitEnt) && IsValidClient(hitEnt)
            && IsClientConnected(hitEnt))
        {
            //PrintToChat(client, "Client %i hit client %i", client, hitEnt);
            aimOk = true;
        }
    }
    
    bool shotConnectOk = g_bDidConnectSShot[client];
    if (g_iNitLvl[client] < NOTE_ALL)
    {
        shotConnectOk = true;
    }
    g_bDidConnectSShot[client] = false;
    
    MistakeSound sound = GetMistakes(aimOk, strafeOk, shotConnectOk, true, client);
    
    if (g_bUseSounds[client] && (!g_bOnlyFails[client] || sound != ALL_OK))
    {
        EmitSoundToClient(client, g_sSounds[sound]);
    }
    
    /*PrintToChat(client, "Aim: %b, strafe: %b, shotC: %b",
        aimOk, strafeOk, shotConnectOk);*/
}

MistakeSound GetMistakes(bool aimOk, bool strafeOk, bool shotConnectOk,
    bool verbose = true, int client = 0)
{
    int numMistakes = 0;
    if (!aimOk) { numMistakes++; }
    if (!strafeOk) { numMistakes++; }
    if (!shotConnectOk) { numMistakes++; }
    
    MistakeSound result;
    if (numMistakes == 0) {
        result = ALL_OK;
    }
    else if (numMistakes == 1) {
        if (!aimOk) { result = ALL_OK; } // This means one tapped, crosshair is no longer on target
        else if (!strafeOk) { result = COUNTERSTRAFE_INCORRECT; }
        else { result = SHOT_DID_NOT_CONNECT; }
    }
    else {
        if (strafeOk && shotConnectOk) {
            result = ALL_OK;
        }
        else if (!strafeOk && aimOk) {
            result = COUNTERSTRAFE_INCORRECT;
        }
        else if (strafeOk && !aimOk && !shotConnectOk) {
            result = CROSSHAIR_PLACEMENT_INCORRECT;
        }
        else {
            result = MULTIPLE_FAILED;
        }
    }
    
    if (verbose) {
        if (!IsValidClient(client) || !IsClientConnected(client)) {
            ThrowError("Unexpected client %i", client);
        }
        if (result == ALL_OK && !g_cOkVerbosity.BoolValue) {
            return result;
        }
        new const String:message[][] = {
            " \x01\x0B\x07Crosshair placement incorrect",
            " \x01\x0B\x03OK",
            " \x01\x0B\x07Counterstrafe incorrect",
            " \x01\x0B\x07Shot did not connect",
            " \x01\x0B\x07Multiple mistakes"
        };
        
        if (!g_bOnlyFails[client] || result != ALL_OK)
        {
            PrintToChat(client, message[result]);
        }
    }
    return result;
}

bool DidNotHitShooter(int shooter, int contentsMask, int target)
{
    return shooter != target;
}

bool IsValidClient(int client)
{
    return client > 0 && client <= MaxClients;
}
