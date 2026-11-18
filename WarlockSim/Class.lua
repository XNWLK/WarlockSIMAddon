-- Loaded first. The addon is a Warlock's: on any other class nothing else of it loads (every other file stops at its
-- first line), and what is left is a line in chat at login and the same line from /wsim and the key bindings.
-- When the class cannot be read, the addon loads as usual (reading the character still refuses a non-Warlock).
local ADDON, WL = ...
local ok, _, class = pcall(UnitClass, 'player')
if not ok or type(class) ~= 'string' or (issecretvalue and issecretvalue(class)) or class == 'WARLOCK' then return end

WL.notWarlock = true
local MSG = "|cff9482c9Xn's Warlock Sim|r cannot be used on other classes. It only loads on a Warlock."
local function say() if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(MSG) end end
SLASH_WARLOCKSIM1, SLASH_WARLOCKSIM2 = '/wsim', '/warlocksim'
SlashCmdList['WARLOCKSIM'] = say
function WarlockSim_Toggle() say() end
function WarlockSim_SimCharacter() say() end
BINDING_HEADER_WARLOCKSIM = "Xn's Warlock Sim"
BINDING_NAME_WARLOCKSIM_TOGGLE = 'Open or close the window'
BINDING_NAME_WARLOCKSIM_SIM = 'Sim my character'
local login = CreateFrame('Frame')
login:RegisterEvent('PLAYER_LOGIN')
login:SetScript('OnEvent', function(self) self:UnregisterAllEvents(); say() end)
