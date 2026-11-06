local _, NS = ...
local SC = NS.SC

-- What kind of place a loot zone is (dungeon, raid or open world) and which expansion it belongs to, for the
-- Attunable Items filters. Both are bit flags so an item's sources can be OR'd together.
local ZoneInfo = {}
SC.ZoneInfo = ZoneInfo

ZoneInfo.DUNGEON, ZoneInfo.RAID, ZoneInfo.WORLD = 1, 2, 4
ZoneInfo.CLASSIC, ZoneInfo.TBC, ZoneInfo.WOTLK = 1, 2, 4

local D, R, W = ZoneInfo.DUNGEON, ZoneInfo.RAID, ZoneInfo.WORLD
local CLASSIC, TBC, WOTLK = ZoneInfo.CLASSIC, ZoneInfo.TBC, ZoneInfo.WOTLK

local instances = {}
local function addInstances(exp, kind, maps)
	for _, map in ipairs(maps) do instances[map] = { exp = exp, kind = kind } end
end
addInstances(CLASSIC, D, { 33, 34, 36, 43, 47, 48, 70, 90, 109, 129, 189, 209, 229, 230, 289, 329, 349, 389, 429 })
addInstances(CLASSIC, R, { 309, 409, 469, 509, 531 })
addInstances(CLASSIC, W, { 369 })
addInstances(TBC, D, { 269, 540, 542, 543, 545, 546, 547, 552, 553, 554, 555, 556, 557, 558, 560, 585 })
addInstances(TBC, R, { 532, 534, 544, 548, 550, 564, 565, 568, 580 })
addInstances(WOTLK, D, { 574, 575, 576, 578, 595, 599, 600, 601, 602, 604, 608, 619, 632, 650, 658, 668 })
addInstances(WOTLK, R, { 249, 533, 603, 615, 616, 624, 631, 649, 724 })
addInstances(WOTLK, W, { 609 })

local world = {}
local function addWorld(exp, zones)
	for _, zone in ipairs(zones) do world[zone] = exp end
end
addWorld(CLASSIC, { 1, 3, 4, 8, 10, 11, 12, 14, 15, 16, 17, 25, 28, 33, 36, 38, 40, 41, 44, 45, 46, 47, 51, 85, 130,
	139, 141, 148, 214, 215, 267, 331, 357, 361, 400, 405, 406, 440, 490, 493, 618, 718, 721, 796, 1337, 1377, 1477,
	1497, 1519, 1537, 1581, 1637, 1638, 1657, 2100, 2159, 2557, 2597 })
addWorld(TBC, { 3430, 3433, 3455, 3483, 3487, 3518, 3519, 3520, 3521, 3522, 3523, 3524, 3525, 3557, 3703, 4080 })
addWorld(WOTLK, { 65, 66, 67, 210, 394, 495, 2817, 3537, 3711, 3979, 4197, 4395, 4742 })

-- kind, expansion for a zone code from the loot data; nil for one this table doesn't know.
function ZoneInfo.Classify(zone)
	local kind, exp
	if zone and zone >= 0x8000 and zone ~= 0xFFFF then
		local info = instances[bit.band(zone, 0x3FF)]
		if info then kind, exp = info.kind, info.exp end
	elseif zone and world[zone] then
		kind, exp = W, world[zone]
	end
	return kind, exp
end

-- The expansion an item most likely belongs to when none of its sources has a known zone.
function ZoneInfo.ExpansionForLevel(req)
	local exp = CLASSIC
	if (req or 0) > 70 then exp = WOTLK elseif (req or 0) > 60 then exp = TBC end
	return exp
end
