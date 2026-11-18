-- BrainrotClient: the Brainrot Bay HUD, drawn as a ScreenGui over the
-- 3D world. The server owns every number; this script only shows them
-- and sends the player's lock and rebirth requests. HUD text stays on
-- the right and bottom, clear of Roblox's own buttons in the top-left.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local BrainrotData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotData"))

local hudUpdate = ReplicatedStorage:WaitForChild("HudUpdate")
local notify = ReplicatedStorage:WaitForChild("Notify")
local requestLock = ReplicatedStorage:WaitForChild("RequestLock")
local requestRebirth = ReplicatedStorage:WaitForChild("RequestRebirth")

-- GUI root -----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "BrainrotBay"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

local function makeLabel(parent, name, text, size, color, pos, anchor, align)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = text
	label.TextSize = size
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = color
	label.BackgroundTransparency = 1
	label.TextStrokeTransparency = 0.6
	label.AnchorPoint = anchor or Vector2.new(0, 0)
	label.Position = pos
	label.Size = UDim2.fromOffset(320, 34)
	label.TextXAlignment = align or Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

-- Top-right HUD: cash, income, rebirths, wave clock. Right-aligned so
-- it never sits under Roblox's top-left menu buttons.
local hud = Instance.new("Frame")
hud.Name = "HUD"
hud.AnchorPoint = Vector2.new(1, 0)
hud.Position = UDim2.new(1, -16, 0, 12)
hud.Size = UDim2.fromOffset(330, 150)
hud.BackgroundTransparency = 1
hud.Parent = gui

local cashLabel = makeLabel(hud, "Cash", "CASH  $100", 28, Color3.fromRGB(120, 255, 140),
	UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), Enum.TextXAlignment.Right)
local rateLabel = makeLabel(hud, "Rate", "+$0/s", 22, Color3.fromRGB(255, 220, 90),
	UDim2.new(0, 0, 0, 36), Vector2.new(0, 0), Enum.TextXAlignment.Right)
local rebirthLabel = makeLabel(hud, "Rebirths", "REBIRTHS  0  (x1.0)", 20, Color3.fromRGB(200, 150, 255),
	UDim2.new(0, 0, 0, 68), Vector2.new(0, 0), Enum.TextXAlignment.Right)
local waveLabel = makeLabel(hud, "Wave", "MEME WAVE  100s", 20, Color3.fromRGB(255, 120, 160),
	UDim2.new(0, 0, 0, 98), Vector2.new(0, 0), Enum.TextXAlignment.Right)
local carryLabel = makeLabel(hud, "Carrying", "", 20, Color3.fromRGB(255, 255, 255),
	UDim2.new(0, 0, 0, 126), Vector2.new(0, 0), Enum.TextXAlignment.Right)

-- Left panel: the whole rarity ladder, so the player always sees the
-- next tier to save for. Built from the same shared data as the server.
local shop = Instance.new("Frame")
shop.Name = "ShopLadder"
shop.AnchorPoint = Vector2.new(0, 0)
shop.Position = UDim2.new(0, 12, 0, 60)
shop.Size = UDim2.fromOffset(300, 460)
shop.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
shop.BackgroundTransparency = 0.25
shop.BorderSizePixel = 0
shop.Parent = gui
local shopCorner = Instance.new("UICorner")
shopCorner.CornerRadius = UDim.new(0, 12)
shopCorner.Parent = shop

local shopTitle = makeLabel(shop, "Title", "BRAINROT LADDER", 20, Color3.fromRGB(255, 220, 90),
	UDim2.new(0, 12, 0, 8), Vector2.new(0, 0))
shopTitle.Size = UDim2.fromOffset(276, 28)

local y = 40
for _, character in ipairs(BrainrotData.CHARACTERS) do
	local rarity = BrainrotData.RARITIES[character.rarity]
	local row = Instance.new("TextLabel")
	row.Name = "Row" .. character.name
	row.Text = character.name .. "  •  " .. BrainrotData.formatMoney(character.cost)
		.. "  •  " .. BrainrotData.formatMoney(BrainrotData.rateOf(character, 1)) .. "/s"
	row.TextSize = 15
	row.Font = Enum.Font.GothamBold
	row.TextColor3 = rarity.color
	row.TextStrokeTransparency = 0.6
	row.BackgroundTransparency = 1
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.Position = UDim2.new(0, 12, 0, y)
	row.Size = UDim2.fromOffset(276, 22)
	row.Parent = shop
	local sub = Instance.new("TextLabel")
	sub.Name = "Quirk" .. character.name
	sub.Text = "  " .. rarity.name .. " — " .. character.quirk
	sub.TextSize = 12
	sub.Font = Enum.Font.Gotham
	sub.TextColor3 = Color3.fromRGB(200, 200, 220)
	sub.BackgroundTransparency = 1
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Position = UDim2.new(0, 12, 0, y + 20)
	sub.Size = UDim2.fromOffset(276, 16)
	sub.Parent = shop
	y = y + 38
end

-- Bottom bar: base lock, rebirth, and the hint line.
local bar = Instance.new("Frame")
bar.Name = "BottomBar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -14)
bar.Size = UDim2.fromOffset(560, 56)
bar.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
bar.BackgroundTransparency = 0.25
bar.BorderSizePixel = 0
bar.Parent = gui
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 12)
barCorner.Parent = bar

local function makeButton(parent, name, text, pos, size, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.TextSize = 18
	button.Font = Enum.Font.GothamBlack
	button.TextColor3 = Color3.fromRGB(15, 15, 30)
	button.BackgroundColor3 = color
	button.Position = pos
	button.Size = size
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	return button
end

local lockButton = makeButton(bar, "LockButton", "🔒 LOCK BASE (L)",
	UDim2.new(0, 10, 0, 8), UDim2.fromOffset(180, 40), Color3.fromRGB(120, 200, 255))
local rebirthButton = makeButton(bar, "RebirthButton", "✦ REBIRTH (R)",
	UDim2.new(0, 200, 0, 8), UDim2.fromOffset(180, 40), Color3.fromRGB(200, 150, 255))
local hintLabel = makeLabel(bar, "Hint", "Touch a brainrot on the belt to buy it!",
	14, Color3.fromRGB(230, 230, 245), UDim2.new(0, 390, 0, 12), Vector2.new(0, 0))
hintLabel.Size = UDim2.fromOffset(160, 32)
hintLabel.TextWrapped = true

-- Banner: server notices (wave warnings, steals, rebirths) across the
-- top center, under the timer bar area.
local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.Text = ""
banner.TextSize = 22
banner.Font = Enum.Font.GothamBlack
banner.TextColor3 = Color3.fromRGB(255, 255, 255)
banner.TextStrokeTransparency = 0.2
banner.BackgroundColor3 = Color3.fromRGB(15, 15, 30)
banner.BackgroundTransparency = 0.2
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 60)
banner.Size = UDim2.fromOffset(640, 40)
banner.Visible = false
banner.Parent = gui
local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 10)
bannerCorner.Parent = banner

local bannerHideAt = 0
local function showBanner(text)
	banner.Text = text
	banner.Visible = true
	bannerHideAt = tick() + 5
end

-- Start overlay ------------------------------------------------------------
local startOverlay = Instance.new("Frame")
startOverlay.Name = "StartOverlay"
startOverlay.Size = UDim2.fromScale(1, 1)
startOverlay.BackgroundColor3 = Color3.fromRGB(10, 10, 22)
startOverlay.BackgroundTransparency = 0.15
startOverlay.BorderSizePixel = 0
startOverlay.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Text = "BRAINROT BAY"
title.TextSize = 56
title.Font = Enum.Font.GothamBlack
title.TextColor3 = Color3.fromRGB(255, 120, 180)
title.BackgroundTransparency = 1
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.new(0.5, 0, 0.3, 0)
title.Size = UDim2.fromOffset(640, 70)
title.Parent = startOverlay

local howto = Instance.new("TextLabel")
howto.Name = "HowTo"
howto.Text = "Catch absurd brainrots off the conveyor, carry them to your base,\n"
	.. "and watch the cash tick up every second.\n\n"
	.. "• Touch a walking brainrot to buy it — then DASH it home!\n"
	.. "• Other players can steal from your base. Lock it (L) or tag thieves.\n"
	.. "• When the MEME WAVE comes, only your base is safe.\n"
	.. "• Earn $50K total, then REBIRTH (R) for +50% earnings forever."
howto.TextSize = 20
howto.Font = Enum.Font.Gotham
howto.TextColor3 = Color3.fromRGB(235, 235, 245)
howto.BackgroundTransparency = 1
howto.AnchorPoint = Vector2.new(0.5, 0.5)
howto.Position = UDim2.new(0.5, 0, 0.52, 0)
howto.Size = UDim2.fromOffset(640, 190)
howto.Parent = startOverlay

local startButton = makeButton(startOverlay, "StartButton", "▶  PLAY",
	UDim2.new(0.5, -110, 0, 0), UDim2.fromOffset(220, 56), Color3.fromRGB(255, 120, 180))
startButton.Position = UDim2.new(0.5, 0, 0.72, 0)
startButton.AnchorPoint = Vector2.new(0.5, 0.5)

-- Wiring -------------------------------------------------------------------
local started = false
local function startGame()
	started = true
	startOverlay.Visible = false
end
startButton.MouseButton1Click:Connect(startGame)

local function doLock()
	if started then
		requestLock:FireServer()
	end
end
local function doRebirth()
	if started then
		requestRebirth:FireServer()
	end
end
lockButton.MouseButton1Click:Connect(doLock)
rebirthButton.MouseButton1Click:Connect(doRebirth)
ContextActionService:BindAction("BrainrotLock", function(_, state)
	if state == Enum.UserInputState.Begin then
		doLock()
	end
end, false, Enum.KeyCode.L)
ContextActionService:BindAction("BrainrotRebirth", function(_, state)
	if state == Enum.UserInputState.Begin then
		doRebirth()
	end
end, false, Enum.KeyCode.R)
ContextActionService:BindAction("BrainrotStart", function(_, state)
	if state == Enum.UserInputState.Begin and not started then
		startGame()
	end
end, false, Enum.KeyCode.Return)

hudUpdate.OnClientEvent:Connect(function(data)
	cashLabel.Text = "CASH  " .. BrainrotData.formatMoney(data.cash)
	rateLabel.Text = "+" .. BrainrotData.formatMoney(data.rate) .. "/s"
	rebirthLabel.Text = "REBIRTHS  " .. tostring(data.rebirths)
		.. "  (x" .. string.format("%.1f", 1 + BrainrotData.REBIRTH_BONUS_PER * data.rebirths) .. ")"
	if data.waveIn <= 10 then
		waveLabel.Text = "⚠ MEME WAVE  " .. tostring(math.max(0, math.ceil(data.waveIn))) .. "s!"
		waveLabel.TextColor3 = Color3.fromRGB(255, 60, 80)
	else
		waveLabel.Text = "MEME WAVE  " .. tostring(math.ceil(data.waveIn)) .. "s"
		waveLabel.TextColor3 = Color3.fromRGB(255, 120, 160)
	end
	if data.carrying then
		carryLabel.Text = "CARRYING — DASH HOME!"
		carryLabel.TextColor3 = Color3.fromRGB(255, 220, 90)
	else
		carryLabel.Text = ""
	end
	if data.lockActive then
		lockButton.Text = "🔒 LOCKED"
	else
		lockButton.Text = "🔒 LOCK BASE (L)"
	end
	if data.earned >= data.rebirthGoal then
		rebirthButton.Text = "✦ REBIRTH READY! (R)"
	else
		rebirthButton.Text = "✦ REBIRTH (R)"
	end
end)

notify.OnClientEvent:Connect(function(message)
	showBanner(message)
end)

-- Hide the banner a few seconds after it shows.
game:GetService("RunService").RenderStepped:Connect(function()
	if banner.Visible and tick() >= bannerHideAt then
		banner.Visible = false
	end
end)

gui.Parent = player:WaitForChild("PlayerGui")
print("Brainrot Bay client ready.")
