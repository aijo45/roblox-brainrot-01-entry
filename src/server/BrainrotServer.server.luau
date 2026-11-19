-- BrainrotServer: the whole Brainrot Bay game loop, server side.
-- Builds the 3D bay at runtime, walks brainrots down the conveyor,
-- pays $/s for every brainrot on a player's base, and runs stealing,
-- the Meme Wave, rebirths, DataStore saves and one brainrot-recovery
-- path. The client only draws the HUD; every number that matters
-- lives here. A catch is never silently lost: a stolen brainrot goes
-- home to its owner when the thief is tagged, swept or leaves, and a
-- bought one runs off back onto the conveyor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")

local BrainrotData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotData"))

-- Tuning -----------------------------------------------------------------
local SPAWN_EVERY = 4 -- seconds between conveyor spawns
local WALK_SPEED = 6 -- studs per second along the conveyor
local PROXIMITY_BUY_STUDS = 5 -- buy range: standing this close to a walker buys it
local CONVEYOR_HALF = 105 -- brainrots despawn past z = +/-105
local WALKER_MAX = 8
local WAVE_EVERY = 100 -- seconds between Meme Waves
local WAVE_WARN = 10 -- seconds of warning before the wall sweeps
local WAVE_SWEEP = 8 -- seconds the wall takes to cross the map
local LOCK_SECONDS = 20
local LOCK_COOLDOWN = 60
local START_CASH = 100
local PLOT_COUNT = 8
local SAVE_EVERY = 60 -- seconds between autosaves
local REMOTE_DEBOUNCE = 2 -- seconds between lock/rebirth requests

-- The Meme Wave clock. Declared up here so sendHud (below) can read it:
-- a local declared after a function is invisible inside that function.
local waveCountdown = WAVE_EVERY
local wavePhase = "calm" -- calm -> warn -> sweep
local waveTimer = 0
local waveZ = -130

-- Saves ------------------------------------------------------------------
-- GetDataStore throws in Studio when API access is off, so a dead
-- store must never take the game down with it: persistence is simply
-- off then, and no save ever runs.
local saveStore = nil
pcall(function()
	saveStore = DataStoreService:GetDataStore("BrainrotBaySaveV1")
end)

local function loadSave(player)
	if not saveStore then
		return nil, false
	end
	local ok, data = pcall(function()
		return saveStore:GetAsync("player_" .. player.UserId)
	end)
	if not ok then
		return nil, false
	end
	return data, true
end

-- Never save a player whose load failed: overwriting their real save
-- with fresh defaults would erase their progress for good.
local function saveData(player, state)
	if not saveStore or not state or not state.dataLoaded then
		return
	end
	local key = "player_" .. player.UserId
	local cash, earned, rebirths = state.cash, state.earned, state.rebirths
	pcall(function()
		saveStore:UpdateAsync(key, function()
			return { cash = cash, earned = earned, rebirths = rebirths }
		end)
	end)
end

-- Remotes ----------------------------------------------------------------
local hudUpdate = Instance.new("RemoteEvent")
hudUpdate.Name = "HudUpdate"
hudUpdate.Parent = ReplicatedStorage

local notify = Instance.new("RemoteEvent")
notify.Name = "Notify"
notify.Parent = ReplicatedStorage

local requestLock = Instance.new("RemoteEvent")
requestLock.Name = "RequestLock"
requestLock.Parent = ReplicatedStorage

local requestRebirth = Instance.new("RemoteEvent")
requestRebirth.Name = "RequestRebirth"
requestRebirth.Parent = ReplicatedStorage

-- World ------------------------------------------------------------------
local function newPart(name, size, position, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = true
	part.Parent = Workspace
	return part
end

-- The conveyor: a dark belt down the middle of the bay. Brainrots walk
-- it from the north gate to the south gate; buy one by touching it.
local conveyor = newPart("Conveyor", Vector3.new(10, 0.5, 220), Vector3.new(0, 0.25, 0),
	Color3.fromRGB(45, 45, 60), Enum.Material.Slate)
conveyor.CanCollide = false

for z = -100, 100, 20 do
	local stripe = Instance.new("Part")
	stripe.Name = "BeltStripe"
	stripe.Size = Vector3.new(10, 0.1, 2)
	stripe.Position = Vector3.new(0, 0.55, z)
	stripe.Color = Color3.fromRGB(255, 200, 40)
	stripe.Material = Enum.Material.Neon
	stripe.Anchored = true
	stripe.CanCollide = false
	stripe.Parent = Workspace
end

-- The north and south gates the brainrots walk through.
local function newGate(z, label)
	local gate = newPart("Gate", Vector3.new(14, 10, 1), Vector3.new(0, 5, z), Color3.fromRGB(255, 120, 180))
	local sign = Instance.new("BillboardGui")
	sign.Name = "GateSign"
	sign.Size = UDim2.fromOffset(220, 44)
	sign.StudsOffset = Vector3.new(0, 6, 0)
	sign.AlwaysOnTop = true
	sign.Parent = gate
	local text = Instance.new("TextLabel")
	text.Name = "Label"
	text.Text = label
	text.TextSize = 26
	text.Font = Enum.Font.GothamBlack
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Parent = sign
end
newGate(-112, "BRAINROT BAY")
newGate(112, "CATCH THEM ALL")

-- Base plots: four on the west side, four on the east, each with six
-- pedestals in two rows of three and a floating owner sign.
local PLOT_CENTERS = {}
for i = 1, 4 do
	table.insert(PLOT_CENTERS, Vector3.new(-62, 0, -78 + (i - 1) * 52))
	table.insert(PLOT_CENTERS, Vector3.new(62, 0, -78 + (i - 1) * 52))
end

local PLOT_COLORS = {
	Color3.fromRGB(255, 90, 90), Color3.fromRGB(90, 160, 255), Color3.fromRGB(90, 220, 120),
	Color3.fromRGB(255, 200, 60), Color3.fromRGB(200, 120, 255), Color3.fromRGB(255, 140, 200),
	Color3.fromRGB(120, 220, 230), Color3.fromRGB(255, 170, 90),
}

local plots = {} -- [plotIndex] = { center, color, owner, lockUntil, pedestals, signText }

local function buildPlot(index)
	local center = PLOT_CENTERS[index]
	local color = PLOT_COLORS[index]
	local platform = newPart("BasePlot" .. index, Vector3.new(26, 1, 26),
		Vector3.new(center.X, 0.5, center.Z), color, Enum.Material.Grass)
	platform.Name = "BasePlot"
	platform:SetAttribute("PlotIndex", index)

	local trim = newPart("PlotTrim" .. index, Vector3.new(27, 0.4, 27),
		Vector3.new(center.X, 0.2, center.Z), Color3.fromRGB(255, 255, 255))
	trim.CanCollide = false

	local signPart = newPart("PlotSign" .. index, Vector3.new(1, 1, 1),
		Vector3.new(center.X, 8, center.Z - 11), color)
	signPart.Transparency = 1
	signPart.CanCollide = false
	local sign = Instance.new("BillboardGui")
	sign.Name = "OwnerSign"
	sign.Size = UDim2.fromOffset(260, 50)
	sign.AlwaysOnTop = true
	sign.Parent = signPart
	local signText = Instance.new("TextLabel")
	signText.Name = "Label"
	signText.Text = "EMPTY BASE"
	signText.TextSize = 24
	signText.Font = Enum.Font.GothamBlack
	signText.TextColor3 = Color3.fromRGB(255, 255, 255)
	signText.BackgroundTransparency = 1
	signText.Size = UDim2.fromScale(1, 1)
	signText.Parent = sign

	local pedestals = {}
	for slot = 1, BrainrotData.MAX_BASE_SLOTS do
		local row = math.floor((slot - 1) / 3)
		local col = (slot - 1) % 3
		local px = center.X - 8 + col * 8
		local pz = center.Z - 5 + row * 10
		local ped = newPart("Pedestal" .. slot, Vector3.new(5, 1.5, 5),
			Vector3.new(px, 0.75, pz), Color3.fromRGB(240, 240, 250), Enum.Material.Marble)
		ped:SetAttribute("PlotIndex", index)
		ped:SetAttribute("Slot", slot)
		table.insert(pedestals, { part = ped, taken = false, brainrot = nil })
	end

	plots[index] = {
		center = center, color = color, owner = nil, lockUntil = 0,
		platform = platform, pedestals = pedestals, signText = signText,
	}
end
for i = 1, PLOT_COUNT do
	buildPlot(i)
end

-- A few trees and rocks so the bay is a place, not a flat board.
local function newTree(x, z)
	local trunk = newPart("TreeTrunk", Vector3.new(2, 6, 2), Vector3.new(x, 3, z),
		Color3.fromRGB(140, 95, 50), Enum.Material.Wood)
	local leaves = Instance.new("Part")
	leaves.Name = "TreeTop"
	leaves.Shape = Enum.PartType.Ball
	leaves.Size = Vector3.new(9, 9, 9)
	leaves.Position = Vector3.new(x, 9, z)
	leaves.Color = Color3.fromRGB(60, 180, 80)
	leaves.Material = Enum.Material.Grass
	leaves.Anchored = true
	leaves.Parent = Workspace
	return trunk
end
newTree(-30, -95)
newTree(30, -95)
newTree(-30, 95)
newTree(30, 95)
newTree(-95, 0)
newTree(95, 0)

-- The Meme Wave wall: a translucent red wall that sweeps the map from
-- north to south. It starts parked under the baseplate.
local waveWall = Instance.new("Part")
waveWall.Name = "MemeWave"
waveWall.Size = Vector3.new(260, 24, 2)
waveWall.Position = Vector3.new(0, 12, -200)
waveWall.Color = Color3.fromRGB(255, 60, 120)
waveWall.Material = Enum.Material.Neon
waveWall.Transparency = 0.4
waveWall.Anchored = true
waveWall.CanCollide = false
waveWall.Parent = Workspace

-- Player state -----------------------------------------------------------
-- [player] = { cash, earned, rebirths, plot, carrying, lockUntil,
--   lockReadyAt, lockRequestAt, rebirthRequestAt, dataLoaded }
local playerState = {}

local function playerRate(state)
	local total = 0
	if not state.plot then
		return 0
	end
	for _, ped in ipairs(plots[state.plot].pedestals) do
		if ped.brainrot then
			total = total + ped.brainrot.rate
		end
	end
	return total * (1 + BrainrotData.REBIRTH_BONUS_PER * state.rebirths)
end

-- Seconds left in the current wave phase: calm/warn count down to the
-- next phase, sweep counts down to the wall leaving the map.
local function waveSeconds()
	if wavePhase == "sweep" then
		return math.max(0, (130 - waveZ) / (260 / WAVE_SWEEP))
	elseif wavePhase == "warn" then
		return math.max(0, WAVE_WARN - waveTimer)
	else
		return math.max(0, waveCountdown)
	end
end

local function sendHud(player)
	local state = playerState[player]
	if not state then
		return
	end
	hudUpdate:FireClient(player, {
		cash = state.cash,
		rate = playerRate(state),
		rebirths = state.rebirths,
		earned = state.earned,
		plot = state.plot or 0,
		carrying = state.carrying ~= nil,
		lockActive = tick() < state.lockUntil,
		lockLeft = math.max(0, state.lockUntil - tick()),
		lockReadyIn = math.max(0, state.lockReadyAt - tick()),
		rebirthGoal = BrainrotData.REBIRTH_CASH_GOAL,
		waveIn = waveCountdown,
		wavePhase = wavePhase,
		waveSecs = waveSeconds(),
	})
end

local function sendAllHud()
	for player in pairs(playerState) do
		sendHud(player)
	end
end

-- Brainrot models --------------------------------------------------------
-- Placed brainrots grow a little with their rarity tier (Common 1.0x
-- up to Brainrot God 1.3x), so the ladder is visible at a glance, and
-- a Golden or better mutation gets a thin neon trim in its own color.
local function buildBrainrotModel(character, mutationIndex)
	local rarity = BrainrotData.RARITIES[character.rarity]
	local mutation = BrainrotData.MUTATIONS[mutationIndex]
	local s = 1 + (character.rarity - 1) * 0.06
	local model = Instance.new("Model")
	model.Name = character.name

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(3 * s, 3 * s, 2 * s)
	body.Color = character.body
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2.6 * s, 2.4 * s, 2.2 * s)
	head.Position = Vector3.new(0, 2.7 * s, 0)
	head.Color = character.head
	head.Material = Enum.Material.SmoothPlastic
	head.Anchored = true
	head.Parent = model

	for _, side in ipairs({ -0.7, 0.7 }) do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Size = Vector3.new(0.5 * s, 0.7 * s, 0.2 * s)
		eye.Position = Vector3.new(side * s, 2.9 * s, 1.15 * s)
		eye.Color = Color3.fromRGB(20, 20, 30)
		eye.Anchored = true
		eye.Parent = model
	end

	if mutationIndex > 1 then
		local trim = Instance.new("Part")
		trim.Name = "MutationTrim"
		trim.Size = Vector3.new(3.4 * s, 0.3, 2.4 * s)
		trim.Position = Vector3.new(0, -1.6 * s, 0)
		trim.Color = mutation.color
		trim.Material = Enum.Material.Neon
		trim.Anchored = true
		trim.Parent = model
	end

	local label = Instance.new("BillboardGui")
	label.Name = "BrainrotLabel"
	label.Size = UDim2.fromOffset(220, 72)
	label.StudsOffset = Vector3.new(0, 5.2 * s, 0)
	label.AlwaysOnTop = true
	label.Parent = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Text = character.name
	nameLabel.TextSize = 22
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextColor3 = rarity.color
	nameLabel.TextStrokeTransparency = 0.2
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 26)
	nameLabel.Parent = label

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "Rarity"
	rarityLabel.Text = rarity.name .. (mutationIndex > 1 and ("  •  " .. mutation.name) or "")
	rarityLabel.TextSize = 17
	rarityLabel.Font = Enum.Font.GothamBold
	rarityLabel.TextColor3 = mutation.color
	rarityLabel.TextStrokeTransparency = 0.2
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Size = UDim2.new(1, 0, 0, 22)
	rarityLabel.Position = UDim2.new(0, 0, 0, 26)
	rarityLabel.Parent = label

	local rateLabel = Instance.new("TextLabel")
	rateLabel.Name = "Rate"
	rateLabel.Text = BrainrotData.formatMoney(BrainrotData.rateOf(character, mutationIndex))
		.. "/s  •  " .. BrainrotData.formatMoney(BrainrotData.priceOf(character, mutationIndex))
	rateLabel.TextSize = 17
	rateLabel.Font = Enum.Font.GothamBold
	rateLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
	rateLabel.TextStrokeTransparency = 0.2
	rateLabel.BackgroundTransparency = 1
	rateLabel.Size = UDim2.new(1, 0, 0, 22)
	rateLabel.Position = UDim2.new(0, 0, 0, 48)
	rateLabel.Parent = label

	model.PrimaryPart = body
	return model
end

local function freePedestal(plotIndex)
	for _, ped in ipairs(plots[plotIndex].pedestals) do
		if not ped.taken then
			return ped
		end
	end
	return nil
end

-- Walking brainrots ------------------------------------------------------
-- walkers is keyed by Model, so #walkers is 0 forever; the cap runs on
-- an explicit counter that rises on every spawn and falls on every
-- buy and despawn.
local walkers = {} -- [model] = { character, mutation, rate, price, cooldown }
local walkerCount = 0

local function buyWalker(player, model, entry)
	local state = playerState[player]
	if not state or state.carrying or not walkers[model] then
		return
	end
	if state.cash < entry.price then
		notify:FireClient(player, "Need " .. BrainrotData.formatMoney(entry.price)
			.. " for " .. entry.character.name .. " — you have " .. BrainrotData.formatMoney(state.cash))
		return
	end
	state.cash = state.cash - entry.price
	walkers[model] = nil
	walkerCount = walkerCount - 1
	model:Destroy()
	state.carrying = {
		character = entry.character,
		mutation = entry.mutation,
		rate = entry.rate,
		price = entry.price,
		owner = player, -- the player it was bought by; stealing changes this
		stolen = false,
	}
	-- The carried brainrot rides above the player's head, built fresh so
	-- its label follows the player around the map.
	state.carrying.model = buildBrainrotModel(entry.character, entry.mutation)
	state.carrying.model.Parent = Workspace
	notify:FireClient(player, "Caught " .. entry.character.name .. "! Dash it home to your base!")
	sendHud(player)
	print(("Brainrot Bay: %s bought %s for %d"):format(player.Name, entry.character.name, entry.price))
end

local function spawnWalkerModel(character, mutation)
	local model = buildBrainrotModel(character, mutation)
	model:PivotTo(CFrame.new(0, 2.5, -CONVEYOR_HALF))
	model.Parent = Workspace
	local entry = {
		character = character,
		mutation = mutation,
		rate = BrainrotData.rateOf(character, mutation),
		price = BrainrotData.priceOf(character, mutation),
		cooldown = 0,
	}
	walkers[model] = entry
	walkerCount = walkerCount + 1

	model.PrimaryPart.Touched:Connect(function(hit)
		if tick() < entry.cooldown then
			return
		end
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player then
			return
		end
		entry.cooldown = tick() + 0.5
		buyWalker(player, model, entry)
	end)
	return model, entry
end

local function pickCharacter()
	-- Weight the roll toward cheap characters: rarity 1 is common, the
	-- Brainrot Gods are a rare sight on the conveyor.
	local weights = { 45, 25, 15, 8, 5, 2 }
	local total = 0
	for _, w in ipairs(weights) do
		total = total + w
	end
	local roll = math.random(total)
	local acc = 0
	local rarity = 1
	for i, w in ipairs(weights) do
		acc = acc + w
		if roll <= acc then
			rarity = i
			break
		end
	end
	local pool = {}
	for _, character in ipairs(BrainrotData.CHARACTERS) do
		if character.rarity == rarity then
			table.insert(pool, character)
		end
	end
	return pool[math.random(#pool)]
end

local function spawnWalker()
	if walkerCount >= WALKER_MAX then
		return
	end
	spawnWalkerModel(pickCharacter(), BrainrotData.rollMutation())
end

-- Stealing and recovery --------------------------------------------------
local function stealBrainrot(hit, plotIndex, ped)
	local thief = Players:GetPlayerFromCharacter(hit.Parent)
	if not thief or not ped.taken or not ped.brainrot then
		return
	end
	local owner = ped.brainrot.owner
	if thief == owner then
		return
	end
	local thiefState = playerState[thief]
	if not thiefState or thiefState.carrying then
		return
	end
	local plot = plots[plotIndex]
	if tick() < (plot.lockUntil or 0) then
		notify:FireClient(thief, "That base is LOCKED — try again when the lock drops!")
		return
	end
	local stolen = ped.brainrot
	ped.taken = false
	ped.brainrot = nil
	if stolen.model then
		stolen.model:Destroy()
	end
	thiefState.carrying = {
		character = stolen.character,
		mutation = stolen.mutation,
		rate = stolen.rate,
		price = 0,
		owner = owner, -- the player it was stolen from
		stolen = true,
	}
	thiefState.carrying.model = buildBrainrotModel(stolen.character, stolen.mutation)
	thiefState.carrying.model.Parent = Workspace
	notify:FireClient(thief, "You stole " .. stolen.character.name .. "! RUN it to your base before "
		.. owner.Name .. " tags you!")
	if owner and owner.Parent then
		notify:FireClient(owner, thief.Name .. " stole your " .. stolen.character.name .. "! Tag them to get it back!")
		sendHud(owner)
	end
	sendHud(thief)
end

-- The one recovery path. A carried brainrot goes home to its owner's
-- first free pedestal; with no room, or no owner left, it runs off
-- down the conveyor for anyone to catch. Idempotent: a second call
-- with the same carried table is a no-op, so tag, wave and leave can
-- all funnel through it without ever duplicating a brainrot.
local function recoverBrainrot(carried)
	if not carried or carried.recovered then
		return
	end
	carried.recovered = true
	if carried.model then
		carried.model:Destroy()
		carried.model = nil
	end
	local owner = carried.owner
	local ownerState = owner and playerState[owner]
	if ownerState and ownerState.plot then
		local ped = freePedestal(ownerState.plot)
		if ped then
			ped.taken = true
			ped.brainrot = { character = carried.character, mutation = carried.mutation, rate = carried.rate, owner = owner }
			local model = buildBrainrotModel(carried.character, carried.mutation)
			model:PivotTo(CFrame.new(ped.part.Position.X, ped.part.Position.Y + 3.2, ped.part.Position.Z))
			model.Parent = Workspace
			ped.brainrot.model = model
			model.PrimaryPart.Touched:Connect(function(hit)
				stealBrainrot(hit, ownerState.plot, ped)
			end)
			if owner and owner.Parent then
				notify:FireClient(owner, "Your " .. carried.character.name .. " is safe back on your base.")
				sendHud(owner)
			end
			return
		end
	end
	spawnWalkerModel(carried.character, carried.mutation)
	if owner and owner.Parent then
		notify:FireClient(owner, carried.character.name .. " ran off down the conveyor!")
	end
end

local function placeCarried(player)
	local state = playerState[player]
	if not state or not state.carrying or not state.plot then
		return
	end
	local ped = freePedestal(state.plot)
	if not ped then
		notify:FireClient(player, "Your base is full! Rebirth or make room first.")
		return
	end
	local carried = state.carrying
	ped.taken = true
	ped.brainrot = { character = carried.character, mutation = carried.mutation, rate = carried.rate, owner = player }
	local model = buildBrainrotModel(carried.character, carried.mutation)
	model:PivotTo(CFrame.new(ped.part.Position.X, ped.part.Position.Y + 3.2, ped.part.Position.Z))
	model.Parent = Workspace
	ped.brainrot.model = model
	-- Touching a placed brainrot is how another player steals it.
	model.PrimaryPart.Touched:Connect(function(hit)
		stealBrainrot(hit, state.plot, ped)
	end)
	if carried.model then
		carried.model:Destroy()
	end
	state.carrying = nil
	notify:FireClient(player, carried.character.name .. " is on your base, earning "
		.. BrainrotData.formatMoney(carried.rate) .. "/s!")
	sendHud(player)
end

-- A tagged thief drops the stolen brainrot: it goes home through the
-- single recovery path, never just vanishes.
local function dropStolen(thief)
	local state = playerState[thief]
	if not state or not state.carrying or not state.carrying.stolen then
		return
	end
	local carried = state.carrying
	state.carrying = nil
	notify:FireClient(thief, "Dropped " .. carried.character.name .. " — it ran home!")
	recoverBrainrot(carried)
end

-- The Meme Wave ----------------------------------------------------------
local function onOwnBase(player)
	local state = playerState[player]
	if not state or not state.plot then
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local c = plots[state.plot].center
	return math.abs(root.Position.X - c.X) <= 13 and math.abs(root.Position.Z - c.Z) <= 13
end

local function sweepWave(dt)
	waveZ = waveZ + (260 / WAVE_SWEEP) * dt
	waveWall.Position = Vector3.new(0, 12, waveZ)
	for player in pairs(playerState) do
		local character = player.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root.Position.Z < waveZ + 2 and not onOwnBase(player) then
				-- Swept away: back to spawn, and anything carried runs
				-- home through recovery instead of vanishing.
				local state = playerState[player]
				if state and state.carrying then
					local carried = state.carrying
					state.carrying = nil
					notify:FireClient(player, "The Meme Wave swept you away — your brainrot ran home!")
					recoverBrainrot(carried)
				end
				character:PivotTo(CFrame.new(0, 3, 115))
				sendHud(player)
			end
		end
	end
	if waveZ >= 130 then
		wavePhase = "calm"
		waveCountdown = WAVE_EVERY
		waveWall.Position = Vector3.new(0, 12, -200)
	end
end

-- Lock and rebirth -------------------------------------------------------
requestLock.OnServerEvent:Connect(function(player)
	local state = playerState[player]
	if not state or not state.plot then
		return
	end
	if tick() - state.lockRequestAt < REMOTE_DEBOUNCE then
		return
	end
	state.lockRequestAt = tick()
	if tick() < state.lockReadyAt then
		notify:FireClient(player, "Base lock recharging: " .. math.ceil(state.lockReadyAt - tick()) .. "s left.")
		return
	end
	plots[state.plot].lockUntil = tick() + LOCK_SECONDS
	state.lockUntil = tick() + LOCK_SECONDS
	state.lockReadyAt = tick() + LOCK_SECONDS + LOCK_COOLDOWN
	notify:FireClient(player, "Base LOCKED for " .. LOCK_SECONDS .. "s — nobody can steal from you!")
	sendHud(player)
end)

requestRebirth.OnServerEvent:Connect(function(player)
	local state = playerState[player]
	if not state then
		return
	end
	if tick() - state.rebirthRequestAt < REMOTE_DEBOUNCE then
		return
	end
	state.rebirthRequestAt = tick()
	if state.earned < BrainrotData.REBIRTH_CASH_GOAL then
		notify:FireClient(player, "Rebirth needs " .. BrainrotData.formatMoney(BrainrotData.REBIRTH_CASH_GOAL)
			.. " total earned — you are at " .. BrainrotData.formatMoney(state.earned))
		return
	end
	-- Clear the base, keep the multiplier.
	if state.plot then
		for _, ped in ipairs(plots[state.plot].pedestals) do
			if ped.brainrot and ped.brainrot.model then
				ped.brainrot.model:Destroy()
			end
			ped.taken = false
			ped.brainrot = nil
		end
	end
	if state.carrying and state.carrying.model then
		state.carrying.model:Destroy()
	end
	state.carrying = nil
	state.cash = START_CASH
	state.earned = 0
	state.rebirths = state.rebirths + 1
	notify:FireClient(player, "REBIRTH #" .. state.rebirths .. "! All earnings x"
		.. string.format("%.1f", 1 + BrainrotData.REBIRTH_BONUS_PER * state.rebirths) .. " from now on!")
	sendHud(player)
	print(("Brainrot Bay: %s rebirthed (x%d)"):format(player.Name, state.rebirths))
end)

-- Players ----------------------------------------------------------------
local function claimPlot(player)
	for i, plot in ipairs(plots) do
		if not plot.owner then
			plot.owner = player
			plot.signText.Text = string.upper(player.Name) .. "'S BASE"
			return i
		end
	end
	return nil
end

Players.PlayerAdded:Connect(function(player)
	local saved, loaded = loadSave(player)
	local cash, earned, rebirths = START_CASH, 0, 0
	if loaded and type(saved) == "table" then
		cash = tonumber(saved.cash) or START_CASH
		earned = tonumber(saved.earned) or 0
		rebirths = tonumber(saved.rebirths) or 0
	end
	local plotIndex = claimPlot(player)
	playerState[player] = {
		cash = cash,
		earned = earned,
		rebirths = rebirths,
		plot = plotIndex,
		carrying = nil,
		lockUntil = 0,
		lockReadyAt = 0,
		lockRequestAt = 0,
		rebirthRequestAt = 0,
		dataLoaded = loaded,
	}
	if plotIndex then
		notify:FireClient(player, "Welcome to Brainrot Bay! Your base is plot #" .. plotIndex
			.. ". Touch a brainrot on the conveyor to buy it, then carry it home!")
	else
		notify:FireClient(player, "Welcome to Brainrot Bay! All bases are taken — spectate and steal!")
	end
	sendHud(player)
	print("Brainrot Bay: " .. player.Name .. " joined (plot " .. tostring(plotIndex) .. ").")
end)

Players.PlayerRemoving:Connect(function(player)
	local state = playerState[player]
	if not state then
		return
	end
	saveData(player, state)
	if state.carrying then
		local carried = state.carrying
		state.carrying = nil
		if carried.stolen then
			-- The victim gets their brainrot back through recovery.
			recoverBrainrot(carried)
		else
			-- A bought catch runs off back onto the conveyor.
			if carried.model then
				carried.model:Destroy()
			end
			spawnWalkerModel(carried.character, carried.mutation)
		end
	end
	if state.plot then
		local plot = plots[state.plot]
		for _, ped in ipairs(plot.pedestals) do
			if ped.brainrot and ped.brainrot.model then
				ped.brainrot.model:Destroy()
			end
			ped.taken = false
			ped.brainrot = nil
		end
		plot.owner = nil
		plot.lockUntil = 0
		plot.signText.Text = "EMPTY BASE"
	end
	playerState[player] = nil
end)

-- Save everyone if the server shuts down; autosave covers the rest.
game:BindToClose(function()
	for player, state in pairs(playerState) do
		saveData(player, state)
	end
end)

-- Tagging: touching a thief who carries YOUR brainrot makes them drop it.
RunService.Heartbeat:Connect(function(dt)
	for player, state in pairs(playerState) do
		local character = player.Character
		if character and state.carrying and state.carrying.stolen then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				local owner = state.carrying.owner
				local ownerChar = owner and owner.Character
				local ownerRoot = ownerChar and ownerChar:FindFirstChild("HumanoidRootPart")
				if ownerRoot and (ownerRoot.Position - root.Position).Magnitude < 5 then
					notify:FireClient(owner, "TAGGED! " .. player.Name .. " dropped your brainrot!")
					notify:FireClient(player, owner.Name .. " tagged you — brainrot dropped!")
					dropStolen(player)
				end
			end
		end
		-- Carrying a brainrot onto your own base places it.
		if character and state.carrying and state.plot and onOwnBase(player) then
			placeCarried(player)
		end
	end
end)

-- Main loop: spawn walkers, pay income, run the wave clock, autosave.
local spawnTimer = 0
local incomeTimer = 0
local saveTimer = 0
local lastHud = 0

RunService.Heartbeat:Connect(function(dt)
	spawnTimer = spawnTimer + dt
	if spawnTimer >= SPAWN_EVERY then
		spawnTimer = 0
		spawnWalker()
	end

	-- Walkers march down the conveyor; the carried one rides its player.
	for model, entry in pairs(walkers) do
		local cf = model:GetPivot()
		local nextZ = cf.Position.Z + WALK_SPEED * dt
		if nextZ > CONVEYOR_HALF then
			walkers[model] = nil
			walkerCount = walkerCount - 1
			model:Destroy()
		else
			model:PivotTo(CFrame.new(cf.Position.X, cf.Position.Y, nextZ))
			-- Close-range purchase: standing next to a walker buys it,
			-- no physics touch needed. Touch events are flaky for an
			-- anchored part re-positioned by CFrame every Heartbeat,
			-- so distance is the reliable trigger. buyWalker clears
			-- walkers[model] on a successful buy, which ends the scan.
			local buyRangeSq = PROXIMITY_BUY_STUDS * PROXIMITY_BUY_STUDS
			local ready = tick() >= entry.cooldown
			if ready then
				for player in pairs(playerState) do
					local state = playerState[player]
					if state and state.carrying == nil and walkers[model] then
						local hero = player.Character
						local rootPart = hero and hero:FindFirstChild("HumanoidRootPart")
						if rootPart then
							local wx = cf.Position.X - rootPart.Position.X
							local wz = nextZ - rootPart.Position.Z
							if wx * wx + wz * wz < buyRangeSq then
								entry.cooldown = tick() + 0.5 -- same gap as the touch path
								buyWalker(player, model, entry) -- hands the walker to the buyer
							end
						end
					end
				end
			end
		end
	end
	for player, state in pairs(playerState) do
		if state.carrying and state.carrying.model and player.Character then
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				state.carrying.model:PivotTo(root.CFrame * CFrame.new(0, 4.5, 0))
			end
		end
	end

	-- Income ticks once a second.
	incomeTimer = incomeTimer + dt
	if incomeTimer >= 1 then
		incomeTimer = 0
		for player, state in pairs(playerState) do
			local rate = playerRate(state)
			if rate > 0 then
				state.cash = state.cash + rate
				state.earned = state.earned + rate
			end
		end
	end

	-- Autosave every minute; a failed load never writes defaults.
	saveTimer = saveTimer + dt
	if saveTimer >= SAVE_EVERY then
		saveTimer = 0
		for player, state in pairs(playerState) do
			saveData(player, state)
		end
	end

	-- The Meme Wave clock.
	if wavePhase == "calm" then
		waveCountdown = waveCountdown - dt
		if waveCountdown <= WAVE_WARN then
			wavePhase = "warn"
			waveTimer = 0
			notify:FireAllClients("MEME WAVE INCOMING! Get on your base in " .. WAVE_WARN .. "s or get swept away!")
		end
	elseif wavePhase == "warn" then
		waveTimer = waveTimer + dt
		waveCountdown = WAVE_WARN - waveTimer
		if waveTimer >= WAVE_WARN then
			wavePhase = "sweep"
			waveZ = -130
			notify:FireAllClients("THE MEME WAVE IS HERE! Stay on your base!")
		end
	elseif wavePhase == "sweep" then
		sweepWave(dt)
	end

	lastHud = lastHud + dt
	if lastHud >= 1 then
		lastHud = 0
		sendAllHud()
	end
end)

print("Brainrot Bay server ready: 13 brainrots, 6 rarities, 8 bases, Meme Wave every " .. WAVE_EVERY .. "s.")
