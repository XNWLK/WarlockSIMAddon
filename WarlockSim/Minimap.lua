-- The minimap button (click: open or close the window; drag: move it around the minimap) and the two key bindings
-- (the game's Key Bindings menu, under "AddOns": open or close the window, sim my character; Bindings.xml names them).
-- The button is the addon's own frame, a child of the minimap; nothing of the game's is changed.
local ADDON, WL = ...

BINDING_HEADER_WARLOCKSIM = "Xn's Warlock Sim"
BINDING_NAME_WARLOCKSIM_TOGGLE = 'Open or close the window'
BINDING_NAME_WARLOCKSIM_SIM = 'Sim my character'
function WarlockSim_Toggle() if WL.toggleWindow then WL.toggleWindow() end end
function WarlockSim_SimCharacter() if WL.simFromKey then WL.simFromKey() end end

local ICON = 'Interface\\Icons\\Spell_Shadow_ShadowBolt'
local button

local function minimap() return Minimap or (MinimapCluster and MinimapCluster.Minimap) end

local function place()
  local mm = minimap()
  if not (button and mm) then return end
  local a = math.rad(tonumber(WL.db.options.minimapAngle) or 200)
  local r = (mm.GetWidth and mm:GetWidth() or 140) / 2 + 10
  button:ClearAllPoints()
  button:SetPoint('CENTER', mm, 'CENTER', math.cos(a) * r, math.sin(a) * r)
end

-- while dragged: the angle from the minimap's centre to the mouse
local function follow()
  local mm = minimap()
  local mx, my = mm:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = mm:GetEffectiveScale()
  if not (mx and cx and scale and scale > 0) then return end
  local atan2 = math.atan2 or math.atan                  -- the game's Lua 5.1 has atan2; the test runner's 5.3 takes two arguments in atan
  WL.db.options.minimapAngle = math.floor(math.deg(atan2(cy / scale - my, cx / scale - mx)) + 0.5) % 360
  place()
end

local function create()
  local mm = minimap()
  if button or not mm then return end
  button = CreateFrame('Button', 'WarlockSimMinimapButton', mm)
  button:SetSize(31, 31)
  button:SetFrameStrata('MEDIUM')
  button:SetFrameLevel((mm.GetFrameLevel and mm:GetFrameLevel() or 0) + 8)
  button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  button:RegisterForDrag('LeftButton')
  local bg = button:CreateTexture(nil, 'BACKGROUND')
  bg:SetTexture('Interface\\Minimap\\UI-Minimap-Background'); bg:SetSize(20, 20); bg:SetPoint('TOPLEFT', 7, -5)
  local icon = button:CreateTexture(nil, 'ARTWORK')
  icon:SetTexture(ICON); icon:SetSize(17, 17); icon:SetPoint('TOPLEFT', 7, -6); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local border = button:CreateTexture(nil, 'OVERLAY')
  border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder'); border:SetSize(53, 53); border:SetPoint('TOPLEFT', 0, 0)
  button:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
  button:SetScript('OnClick', function(_, mouse)
    if mouse == 'RightButton' then WarlockSim_SimCharacter() else WarlockSim_Toggle() end
  end)
  button:SetScript('OnDragStart', function(self) self:SetScript('OnUpdate', follow) end)
  button:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
  button:SetScript('OnEnter', function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
    GameTooltip:SetText("Xn's Warlock Sim", 0.58, 0.51, 0.79)
    GameTooltip:AddLine('Click: open or close the window', 1, 1, 1)
    GameTooltip:AddLine('Right-click: sim my character', 1, 1, 1)
    GameTooltip:AddLine('Drag: move this button', 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  button:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
  place()
end

function WL.updateMinimapButton()
  if not WL.db then return end
  if WL.db.options.minimapButton ~= false then
    create()
    if button then place(); button:Show() end
  elseif button then button:Hide() end
end
WL.loginHooks[#WL.loginHooks + 1] = WL.updateMinimapButton
