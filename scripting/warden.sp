#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include "colors_csgo.inc"

#define PLUGIN_VERSION   "1.0.5"
#define CHAT_TAG_PREFIX "[{pink}WARDEN{default}] "
#define CHAT_TAG_PREFIX_PLAIN "[WARDEN] "

#define PREVIOUS_WARDEN_WAIT_TIME 3.0
#define MENU_POPUP_TIME 0.065 

int Warden = -1;
int PrevWarden = -1;

bool isEnabled = true;
bool firstWardenClaimed = false;
bool canPrevWardenClaim = false;

Menu WardenSelectionMenu = null;

Handle g_cVar_enabled;
Handle g_cVar_mnotes;
Handle g_fward_onBecome;
Handle g_fward_onRemove;

public Plugin myinfo = {
  name = "Invex Warden Plugin",
  author = "Ecca & Zipcore, Updates by Invex | Byte",
  description = "",
  version = PLUGIN_VERSION,
  url = "www.invexgaming.com.au"
};

public void OnPluginStart() 
{
  LoadTranslations("warden.phrases");
  
  RegConsoleCmd("sm_w", BecomeWarden);
  RegConsoleCmd("sm_warden", BecomeWarden);
  RegConsoleCmd("sm_uw", ExitWarden);
  RegConsoleCmd("sm_unwarden", ExitWarden);
  RegConsoleCmd("sm_c", BecomeWarden);
  RegConsoleCmd("sm_commander", BecomeWarden);
  RegConsoleCmd("sm_uc", ExitWarden);
  RegConsoleCmd("sm_uncommander", ExitWarden);
  
  RegAdminCmd("sm_removew", RemoveWarden, ADMFLAG_GENERIC);
  RegAdminCmd("sm_rc", RemoveWarden, ADMFLAG_GENERIC);
  
  HookEvent("round_start", round_poststart);
  
  HookEvent("player_death", playerDeath);
  HookEvent("player_team", playerTeam);
  
  AddCommandListener(HookPlayerChat, "say");
  
  CreateConVar("sm_warden_version", PLUGIN_VERSION,  "The version of the SourceMod plugin JailBreak Warden, by ecca", FCVAR_REPLICATED|FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD);
  g_cVar_enabled = CreateConVar("sm_warden_enabled", "1", "Enable Warden Plugin (0 off, 1 on, def. 1)");
  g_cVar_mnotes = CreateConVar("sm_warden_better_notifications", "0", "0 - disabled, 1 - Will use hint and center text", _, true, 0.0, true, 1.0);
  
  g_fward_onBecome = CreateGlobalForward("warden_OnWardenCreated", ET_Ignore, Param_Cell);
  g_fward_onRemove = CreateGlobalForward("warden_OnWardenRemoved", ET_Ignore, Param_Cell);

  //Enable status hook
  HookConVarChange(g_cVar_enabled, ConVarChange_enabled);
  
  isEnabled = true;
  
  AutoExecConfig(true, "warden");
}

public void ConVarChange_enabled(Handle convar, const char[] oldValue, const char[] newValue)
{
  isEnabled = !!StringToInt(newValue);
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, interr_max)
{
  CreateNative("warden_exist", Native_ExistWarden);
  CreateNative("warden_iswarden", Native_IsWarden);
  CreateNative("warden_set", Native_SetWarden);
  CreateNative("warden_remove", Native_RemoveWarden);

  RegPluginLibrary("warden");
  
  return APLRes_Success;
}

public Action BecomeWarden(int client, int args) 
{
  if (!isEnabled) 
    return Plugin_Handled;

  if (Warden == -1)
  {
    if (GetClientTeam(client) == CS_TEAM_CT)
    {
      if (IsPlayerAlive(client))
        if (client != PrevWarden || canPrevWardenClaim)
          SetTheWarden(client);
        else
          CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "warden_prevtoosoon");
      else CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "warden_playerdead");
    }
    else CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "warden_ctsonly");
  }
  else CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "warden_exist", Warden);
  
  return Plugin_Handled;
}

public Action ExitWarden(int client, int args) 
{
  if (!isEnabled) 
    return Plugin_Handled;
    
  if (client == Warden)
  {
    CPrintToChatAll("%s%t", CHAT_TAG_PREFIX, "warden_retire", client);
    
    if(GetConVarBool(g_cVar_mnotes))
    {
      PrintCenterTextAll("%s%t", CHAT_TAG_PREFIX, "warden_retire", client);
      PrintHintTextToAll("%s%t", CHAT_TAG_PREFIX_PLAIN, "warden_retire", client);
    }
    
    Warden = -1;

    Forward_OnWardenRemoved(client);
    SetEntityRenderColor(client, 255, 255, 255, 255);
  }
  else
    CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "warden_notwarden");
    
  return Plugin_Handled;
}

public Action round_poststart(Handle event, const char[] name, bool dontBroadcast) 
{
  if (!isEnabled) 
    return Plugin_Handled;
    
  firstWardenClaimed = false;
  canPrevWardenClaim = false;
  
  CreateTimer(PREVIOUS_WARDEN_WAIT_TIME, prevWardenEnabler);
  
  Warden = -1;
  
  CreateTimer(MENU_POPUP_TIME, wardenMenuShowTimer);
  
  return Plugin_Handled;
}

public Action prevWardenEnabler(Handle timer)
{
  canPrevWardenClaim = true;
}

public Action DelayShowWardenMenu(Handle timer, int client)
{
  //Only show menu if warden is still available to be taken
  if (Warden == -1)
    DisplayMenu(WardenSelectionMenu, client, MENU_TIME_FOREVER);
}

//Show Warden Menu to all alive CT's
public Action wardenMenuShowTimer(Handle timer)
{
  //Create menu for warden selection
  WardenSelectionMenu = CreateMenu(WardenSelectionMenuHandler);
  SetMenuTitle(WardenSelectionMenu, "Warden Claim Menu");

  //Add menu items
  AddMenuItem(WardenSelectionMenu, "Option1", "Claim Warden!");
  SetMenuExitButton(WardenSelectionMenu, true);
  
  //Show menu to all CT's
  int iMaxClients = GetMaxClients();
  for (int i = 1; i <= iMaxClients; ++i) {
    if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_CT) {
      //Show menu to this player
      if (!canPrevWardenClaim && i == PrevWarden)
        CreateTimer(PREVIOUS_WARDEN_WAIT_TIME, DelayShowWardenMenu, i);
      else
        DisplayMenu(WardenSelectionMenu, i, MENU_TIME_FOREVER);
    }
  }
}

//Handle duration menu
public int WardenSelectionMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
  if (action == MenuAction_Select)
  {
    char info[32];
    GetMenuItem(menu, param2, info, sizeof(info));
    
    if (StrEqual(info, "Option1")) {
      //User has claimed warden
      if (Warden == -1) {
        //This user is now warden if alive
        if (GetClientTeam(client) == CS_TEAM_CT)
        {
          if (IsPlayerAlive(client)) {
            SetTheWarden(client);
        
            //Cancel Menu for all other CT's
            CancelMenu(WardenSelectionMenu);
          }
        }
      }
      else {
        //User was too slow
        CPrintToChat(client, "%s%t", CHAT_TAG_PREFIX, "warden_tooslow");
      }
    }
  }
}

public Action playerDeath(Handle event, const char[] name, bool dontBroadcast) 
{
  if (!isEnabled) 
    return Plugin_Handled;
    
  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  
  if(client == Warden)
  {
    CPrintToChatAll("%s%t", CHAT_TAG_PREFIX, "warden_dead", client);
    
    if(GetConVarBool(g_cVar_mnotes))
    {
      PrintCenterTextAll("%s%t", CHAT_TAG_PREFIX, "warden_dead", client);
      PrintHintTextToAll("%s%t", CHAT_TAG_PREFIX_PLAIN, "warden_dead", client);
    }
    
    RemoveTheWarden(client);
    
    //Make menu appear so alive CT's can choose new warden
    CreateTimer(MENU_POPUP_TIME, wardenMenuShowTimer);
  }
  
  return Plugin_Handled;
}

public Action playerTeam(Handle event, const char[] name, bool dontBroadcast) 
{
  if (!isEnabled) 
    return Plugin_Handled;
    
  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  
  if(client == Warden)
    RemoveTheWarden(client);
    
  return Plugin_Handled;
}

public void OnClientDisconnect(int client)
{
  if (!isEnabled) 
    return;
    
  if(client == Warden)
  {
    CPrintToChatAll("%s%t", CHAT_TAG_PREFIX, "warden_disconnected");
    
    if(GetConVarBool(g_cVar_mnotes))
    {
      PrintCenterTextAll("%s%t", CHAT_TAG_PREFIX, "warden_disconnected", client);
      PrintHintTextToAll("%s%t", CHAT_TAG_PREFIX_PLAIN, "warden_disconnected", client);
    }
    
    Warden = -1;
    Forward_OnWardenRemoved(client);
  }
}

public Action RemoveWarden(int client, int args)
{
  if (!isEnabled) 
    return Plugin_Handled;
    
  if (Warden != -1) {
    CPrintToChatAll("%s%t", CHAT_TAG_PREFIX, "warden_removed", client, Warden);
  
    if(GetConVarBool(g_cVar_mnotes))
    {
      PrintCenterTextAll("%s%t", CHAT_TAG_PREFIX, "warden_removed", client);
      PrintHintTextToAll("%s%t", CHAT_TAG_PREFIX_PLAIN, "warden_removed", client);
    }
  
    RemoveTheWarden(client);
  }
  else
    CPrintToChatAll("%s%t", CHAT_TAG_PREFIX, "warden_noexist");

  return Plugin_Handled;
}

public Action HookPlayerChat(int client, const char[] command, int args)
{
  if (!isEnabled) 
    return Plugin_Continue;
    
  if(Warden == client && client)
  {
    char szText[256];
    GetCmdArg(1, szText, sizeof(szText));
    
    if(szText[0] == '/' || szText[0] == '@' || IsChatTrigger())
      return Plugin_Handled;
    
    //Dont print empty string
    if (strlen(szText) == 0) {
      return Plugin_Handled;
    }
    
    if(IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == CS_TEAM_CT)
    {
      CPrintToChatAll("%s%N : %s", CHAT_TAG_PREFIX, client, szText);
      return Plugin_Handled;
    }
  }
  
  return Plugin_Continue;
}

void SetTheWarden(int client)
{
  if (!isEnabled) 
    return;
    
  CPrintToChatAll("%s%t", CHAT_TAG_PREFIX, "warden_new", client);
  
  if(GetConVarBool(g_cVar_mnotes))
  {
    PrintCenterTextAll("%s%t", CHAT_TAG_PREFIX, "warden_new", client);
    PrintHintTextToAll("%s%t", CHAT_TAG_PREFIX_PLAIN, "warden_new", client);
  }
  
  if (!firstWardenClaimed) {
    firstWardenClaimed = true;
    PrevWarden = client;
  }
  
  Warden = client;
  SetEntityRenderColor(client, 0, 0, 255, 255);
  SetClientListeningFlags(client, VOICE_NORMAL);
  
  Forward_OnWardenCreation(client);
}

void RemoveTheWarden(int client)
{
  if (!isEnabled) 
    return;
    
  if(IsClientInGame(client) && IsPlayerAlive(client))
    SetEntityRenderColor(Warden, 255, 255, 255, 255);
  
  Warden = -1;
  
  Forward_OnWardenRemoved(client);
}

public int Native_ExistWarden(Handle plugin, int numParams)
{
  if(Warden != -1)
    return true;
  
  return false;
}

public int Native_IsWarden(Handle plugin, int numParams)
{
  int client = GetNativeCell(1);
  
  if(!IsClientInGame(client) && !IsClientConnected(client))
    ThrowNativeError(SP_ERROR_INDEX, "Client index %i is invalid", client);
  
  if(client == Warden)
    return true;
  
  return false;
}

public int Native_SetWarden(Handle plugin, int numParams)
{
  int client = GetNativeCell(1);
  
  if (!IsClientInGame(client) && !IsClientConnected(client))
    ThrowNativeError(SP_ERROR_INDEX, "Client index %i is invalid", client);
  
  if(Warden == -1)
    SetTheWarden(client);
}

public int Native_RemoveWarden(Handle plugin, int numParams)
{
  int client = GetNativeCell(1);
  
  if (!IsClientInGame(client) && !IsClientConnected(client))
    ThrowNativeError(SP_ERROR_INDEX, "Client index %i is invalid", client);
  
  if(client == Warden)
    RemoveTheWarden(client);
}

void Forward_OnWardenCreation(int client)
{
  Call_StartForward(g_fward_onBecome);
  Call_PushCell(client);
  Call_Finish();
}

void Forward_OnWardenRemoved(int client)
{
  Call_StartForward(g_fward_onRemove);
  Call_PushCell(client);
  Call_Finish();
}