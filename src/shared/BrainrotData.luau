-- BrainrotData: the shared cast, rarity ladder and mutation table for
-- Brainrot Bay. Both the server (spawning, income, stealing) and the
-- client (shop list, HUD labels) read this one module, so the numbers the
-- player sees are the numbers the server pays.

local BrainrotData = {}

-- Rarities climb from Common to Brainrot God. color drives the name
-- label and the pedestal trim; multiplier is the $/s multiplier of the
-- whole tier, so a Legendary earns roughly 100x a Common.
BrainrotData.RARITIES = {
	{ name = "Common", color = Color3.fromRGB(190, 190, 190), multiplier = 1 },
	{ name = "Rare", color = Color3.fromRGB(80, 180, 255), multiplier = 3 },
	{ name = "Epic", color = Color3.fromRGB(170, 90, 255), multiplier = 8 },
	{ name = "Legendary", color = Color3.fromRGB(255, 180, 40), multiplier = 25 },
	{ name = "Mythic", color = Color3.fromRGB(255, 80, 160), multiplier = 80 },
	{ name = "Brainrot God", color = Color3.fromRGB(255, 60, 60), multiplier = 250 },
}

-- Mutations roll when a brainrot spawns on the conveyor. They multiply
-- its $/s and its price, and tint its label.
BrainrotData.MUTATIONS = {
	{ name = "Normal", chance = 0.88, multiplier = 1, color = Color3.fromRGB(255, 255, 255) },
	{ name = "Golden", chance = 0.08, multiplier = 2, color = Color3.fromRGB(255, 215, 0) },
	{ name = "Diamond", chance = 0.03, multiplier = 5, color = Color3.fromRGB(120, 220, 255) },
	{ name = "Rainbow", chance = 0.01, multiplier = 10, color = Color3.fromRGB(255, 120, 255) },
}

-- The cast: twelve absurd, meme-born characters of our own. cost is the
-- buy price in cash; baseRate is the $/s before rarity and mutation.
-- Two per rarity tier, so the shop ladder always shows the next tier.
BrainrotData.CHARACTERS = {
	{ name = "Sir Quacksalot", rarity = 1, cost = 25, baseRate = 1, body = Color3.fromRGB(255, 220, 60), head = Color3.fromRGB(255, 240, 150), quirk = "A duck in a top hat who quacks in Latin." },
	{ name = "Noodle Wizard", rarity = 1, cost = 50, baseRate = 2, body = Color3.fromRGB(240, 200, 120), head = Color3.fromRGB(255, 230, 180), quirk = "Casts spells with wet spaghetti." },
	{ name = "Captain Pickle", rarity = 2, cost = 150, baseRate = 6, body = Color3.fromRGB(90, 200, 90), head = Color3.fromRGB(140, 230, 120), quirk = "Sailed the seven seas in a jar." },
	{ name = "DJ Toaster", rarity = 2, cost = 300, baseRate = 10, body = Color3.fromRGB(180, 180, 200), head = Color3.fromRGB(220, 220, 240), quirk = "Drops beats and bread at the same time." },
	{ name = "Professor Banana", rarity = 3, cost = 800, baseRate = 25, body = Color3.fromRGB(255, 230, 80), head = Color3.fromRGB(255, 245, 160), quirk = "Has a PhD in potassium." },
	{ name = "Couch Potato King", rarity = 3, cost = 1500, baseRate = 40, body = Color3.fromRGB(200, 160, 110), head = Color3.fromRGB(230, 200, 150), quirk = "Rules from the sofa. Never stands." },
	{ name = "Grandma Rocket", rarity = 4, cost = 4000, baseRate = 100, body = Color3.fromRGB(200, 60, 60), head = Color3.fromRGB(255, 200, 200), quirk = "Launches herself to bingo night." },
	{ name = "Toilet Tornado", rarity = 4, cost = 7000, baseRate = 160, body = Color3.fromRGB(230, 240, 255), head = Color3.fromRGB(255, 255, 255), quirk = "Spins. Flushes. Repeats." },
	{ name = "CEO of Naps", rarity = 5, cost = 20000, baseRate = 400, body = Color3.fromRGB(120, 90, 200), head = Color3.fromRGB(180, 150, 240), quirk = "Runs a Fortune 500 company asleep." },
	{ name = "Infinite Sandwich", rarity = 5, cost = 35000, baseRate = 650, body = Color3.fromRGB(220, 180, 120), head = Color3.fromRGB(255, 220, 160), quirk = "Every bite grows a new layer." },
	{ name = "The Algorithm", rarity = 6, cost = 100000, baseRate = 2000, body = Color3.fromRGB(40, 40, 60), head = Color3.fromRGB(90, 220, 255), quirk = "It knows what you will buy next." },
	{ name = "Skibidi Supreme", rarity = 6, cost = 250000, baseRate = 5000, body = Color3.fromRGB(255, 255, 255), head = Color3.fromRGB(255, 255, 255), quirk = "The final boss of brainrot." },
}

BrainrotData.MAX_BASE_SLOTS = 6
BrainrotData.REBIRTH_CASH_GOAL = 50000
BrainrotData.REBIRTH_BONUS_PER = 0.5

function BrainrotData.rollMutation()
	local roll = math.random()
	local acc = 0
	for i, mutation in ipairs(BrainrotData.MUTATIONS) do
		acc = acc + mutation.chance
		if roll <= acc then
			return i
		end
	end
	return 1
end

-- Full $/s of one brainrot: base rate x rarity multiplier x mutation.
function BrainrotData.rateOf(character, mutationIndex)
	local rarity = BrainrotData.RARITIES[character.rarity]
	local mutation = BrainrotData.MUTATIONS[mutationIndex or 1]
	return character.baseRate * rarity.multiplier * mutation.multiplier
end

-- Buy price scales with the mutation, so a Rainbow costs ten times more.
function BrainrotData.priceOf(character, mutationIndex)
	local mutation = BrainrotData.MUTATIONS[mutationIndex or 1]
	return character.cost * mutation.multiplier
end

function BrainrotData.rarityName(index)
	return BrainrotData.RARITIES[index].name
end

function BrainrotData.formatMoney(amount)
	amount = math.floor(amount + 0.5)
	if amount >= 1000000 then
		return string.format("$%.2fM", amount / 1000000)
	elseif amount >= 10000 then
		return string.format("$%.1fK", amount / 1000)
	else
		return "$" .. tostring(amount)
	end
end

return BrainrotData
