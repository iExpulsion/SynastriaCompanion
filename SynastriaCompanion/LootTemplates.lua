local _, NS = ...
local SC = NS.SC

-- Loot filter templates, saved for every character in SC.db.lootTemplates[kind][name]: whole filters (rules and
-- options) to swap in, and single rules to add to any filter. They load into the Auto Loot screen's draft, so Apply
-- saves them and Discard takes them back.
local LT = {}
SC.LootTemplates = LT

local LF = SC.LootFilter

LT.KINDS = {
	{ key = "filters", label = "Filters", one = "Filter" },
	{ key = "rules", label = "Rules", one = "Rule" },
}

function LT.Kind(key)
	for _, kind in ipairs(LT.KINDS) do
		if kind.key == key then return kind end
	end
end

local function store(kind)
	local all = SC.db.lootTemplates
	all[kind] = all[kind] or {}
	return all[kind]
end

-- A rule as a template keeps it: without its place in the saved filter, which a loaded copy doesn't have.
local function copyRule(r)
	local rule = { type = r.type, enabled = r.enabled, outcome = r.outcome, notify = r.notify, name = r.name, cond = {} }
	for j, c in ipairs(r.cond) do rule.cond[j] = { type = c.type, op = c.op, value = c.value } end
	return rule
end

local function copyRules(rules)
	local out = {}
	for i, r in ipairs(rules) do out[i] = copyRule(r) end
	return out
end

function LT.List(kind)
	local list = {}
	for _, t in pairs(store(kind)) do list[#list + 1] = t end
	table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
	return list
end

function LT.Get(kind, name)
	return store(kind)[name]
end

-- Saves the filter (rules and options) under `name`, replacing a template of that name.
function LT.SaveFilter(name, filter)
	local t = { name = name, options = filter.options or 0, rules = copyRules(filter.rules) }
	store("filters")[name] = t
	return t
end

function LT.SaveRule(name, rule)
	local t = { name = name, rule = copyRule(rule) }
	store("rules")[name] = t
	return t
end

-- Puts a filter template's rules and options in the draft in place of its own.
function LT.LoadFilter(t, draft)
	draft.rules = copyRules(t.rules)
	draft.options = t.options
end

-- Adds a rule template at the bottom of the draft. Returns false when the filter already holds the most rules.
function LT.AddRule(t, draft)
	local room = #draft.rules < LF.MAX_RULES
	if room then draft.rules[#draft.rules + 1] = copyRule(t.rule) end
	return room
end

-- A short summary for lists: a filter's rule count and whether it loots, a rule's action and conditions.
function LT.Describe(kind, t)
	local text
	if kind == "filters" then
		local on = bit.band(t.options or 0, LF.AUTO_LOOT.bit) ~= 0
		text = ("%d %s, Auto Loot %s"):format(#t.rules, #t.rules == 1 and "Rule" or "Rules", on and "On" or "Off")
	else
		local action = "?"
		for _, a in ipairs(LF.ACTIONS) do
			if a.value == t.rule.outcome then action = a.text end
		end
		local n = #t.rule.cond
		text = ("%s, %d %s%s"):format(action, n, n == 1 and "Condition" or "Conditions", t.rule.enabled and "" or ", Off")
	end
	return text
end

-- Returns false when the new name is empty or taken.
function LT.Rename(kind, old, new)
	local all = store(kind)
	local ok = new ~= "" and all[old] ~= nil and (new == old or all[new] == nil)
	if ok then
		local t = all[old]
		all[old] = nil
		t.name = new
		all[new] = t
	end
	return ok
end

function LT.Delete(kind, name)
	store(kind)[name] = nil
end

function LT.UniqueName(kind, base)
	local all, name, n = store(kind), base, 1
	while all[name] do
		n = n + 1
		name = ("%s %d"):format(base, n)
	end
	return name
end
