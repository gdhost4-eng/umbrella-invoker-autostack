--[[
     ~ qLocalization
     ~ automatic localization wrapper for Lua menu interfaces

     ~ author: qfun (qfun_g9s)
]]

local qLocalization = (function()
	local lib = {}

	local a = function(...)
		return ...
	end

	local state = {
		lang = Menu.Find("SettingsHidden", "", "", "", "Main", "Language"),
		instances = {},
	}

	local setters = {
		ToolTip = "tooltip",
	}

	local helpers
	do
		helpers = {
			resolve = a(function(root, path)
				for key in path:gmatch("[^.]+") do
					if type(root) ~= "table" then
						return
					end

					root = root[key]
				end

				return root
			end),

			is_object = a(function(value)
				return type(value) == "table" or type(value) == "userdata"
			end),

			has_method = a(function(object, name)
				return helpers.is_object(object) and type(object[name]) == "function"
			end),

			is_menu_object = a(function(value)
				return helpers.has_method(value, "Name") and helpers.has_method(value, "Type")
			end),

			is_list = a(function(value)
				if type(value) ~= "table" or #value == 0 then
					return false
				end

				for i = 1, #value do
					if type(value[i]) ~= "string" then
						return false
					end
				end

				return true
			end),

			is_indexed_list = a(function(object)
				return helpers.has_method(object, "List") and not helpers.has_method(object, "ListEnabled")
			end),
		}
	end

	function lib.new(translations)
		local languages = {}

		for i, name in ipairs(state.lang and state.lang:List() or {}) do
			local code = name:match("%a+")

			if code and translations[code] then
				languages[i - 1] = code
			end
		end

		local localization = {
			translations = translations,
			languages = languages,
			objects = {},
		}

		local methods
		do
			methods = {
				get_language = a(function(language_index)
					if language_index == nil and state.lang then
						language_index = state.lang:Get()
					end

					return localization.languages[language_index] or "en"
				end),

				localize = a(function(path, language_index)
					if type(path) ~= "string" then
						return path
					end

					local language = methods.get_language(language_index)

					return helpers.resolve(localization.translations[language], path)
						or helpers.resolve(localization.translations.en, path)
						or path
				end),

				has = a(function(path)
					if type(path) ~= "string" then
						return false
					end

					return helpers.resolve(localization.translations.en, path) ~= nil
						or helpers.resolve(localization.translations[methods.get_language()], path) ~= nil
				end),

				localize_items = a(function(items, language_index)
					local result, localized = {}, false

					for i = 1, #items do
						local value = items[i]

						if methods.has(value) then
							result[i] = methods.localize(value, language_index)
							localized = true
						else
							result[i] = value
						end
					end

					return result, localized
				end),

				apply = a(function(object, kind, path, language_index)
					if kind == "label" then
						object:ForceLocalization(methods.localize(path, language_index))
					elseif kind == "tooltip" then
						object:ToolTip(methods.localize(path, language_index))
					elseif kind == "items" then
						local value = object:Get()

						object:Update((methods.localize_items(path, language_index)))
						object:Set(value)
					end
				end),

				track = a(function(object, kind, path, apply_now)
					local record = localization.objects[object]

					if record == nil then
						record = {}
						localization.objects[object] = record
					end

					record[kind] = path

					if apply_now then
						methods.apply(object, kind, path)
					end
				end),

				register = a(function(object, path)
					if not methods.has(path) or not helpers.has_method(object, "ForceLocalization") then
						return
					end

					methods.track(object, "label", path, true)
				end),

				update = a(function(language_index)
					for object, record in pairs(localization.objects) do
						for kind, path in pairs(record) do
							methods.apply(object, kind, path, language_index)
						end
					end
				end),

				wrap = a(function(target, bind_self)
					if not helpers.is_object(target) then
						return target
					end

					local proxy

					proxy = setmetatable({}, {
						__index = function(_, key)
							local member = target[key]

							if type(member) ~= "function" then
								return member
							end

							return function(...)
								local args = table.pack(...)

								if bind_self and args[1] == proxy then
									table.remove(args, 1)
									args.n = args.n - 1
								end

								if key == "Switch" and args.n < 2 then
									args[2] = false
									args.n = 2
								end

								local name_path, item_paths

								if setters[key] then
									if methods.has(args[1]) then
										methods.track(target, setters[key], args[1], false)

										args[1] = methods.localize(args[1])
									end
								else
									local name_index = bind_self and 1 or args.n

									if methods.has(args[name_index]) then
										name_path = args[name_index]
									end

									local items_index

									if key == "Combo" then
										items_index = 2
									elseif key == "Update" and helpers.is_indexed_list(target) then
										items_index = 1
									end

									if items_index ~= nil and helpers.is_list(args[items_index]) then
										local items, localized = methods.localize_items(args[items_index])

										if localized then
											item_paths = args[items_index]
											args[items_index] = items
										end
									end
								end

								local results

								if bind_self then
									results = table.pack(member(target, table.unpack(args, 1, args.n)))
								else
									results = table.pack(member(table.unpack(args, 1, args.n)))
								end

								for i = 1, results.n do
									local result = results[i]

									if helpers.is_menu_object(result) then
										if name_path then
											methods.register(result, name_path)
										end

										if item_paths then
											methods.track(result, "items", item_paths, false)
											item_paths = nil
										end

										results[i] = methods.wrap(result, true)
									end
								end

								if item_paths then
									methods.track(target, "items", item_paths, false)
								end

								return table.unpack(results, 1, results.n)
							end
						end,

						__newindex = function(_, key, value)
							target[key] = value
						end,
					})

					return proxy
				end),
			}
		end

		state.instances[methods] = true

		return {
			GetLanguage = methods.get_language,

			Get = methods.localize,
			Localize = methods.localize,

			Update = methods.update,
			Register = methods.register,

			Wrap = methods.wrap,

			WrapLibrary = function(library)
				return methods.wrap(library, false)
			end,
		}
	end

	if state.lang then
		state.lang:SetCallback(function(this)
			local language_index = this:Get()

			for methods in pairs(state.instances) do
				methods.update(language_index)
			end
		end, true)
	else
		Log.Write("[qLocalization] Language widget not found, using English fallback")
	end

	return lib
end)()

local localization = qLocalization.new({
	en = {
		ias_group_main = "Autostack",
		ias_group_extra = "Behavior",
		ias_enable = "Enable",
		ias_enable_tip = "While the key is held, throws Tornado\nso creeps get lifted right before :00",
		ias_gear_extra = "Extra",
		ias_debug = "Debug log",
		ias_debug_tip = "Writes stack results and timings\nto the log",
		ias_hold_key = "Stack while held",
		ias_hold_key_tip = "While held, stacks the camp\nchosen below",
		ias_hold_mode = "What to stack while held",
		ias_hold_modes_near = "Nearest camp",
		ias_hold_modes_cursor = "Camp under cursor",
		ias_land = "Landing after :00, ms",
		ias_land_tip = "How long after :00 the first creep\nshould land back from Tornado",
		ias_reset = "Reset circles",
		ias_reset_tip = "Moves all camp circles\nback to their default spots",
		ias_invoke = "Auto invoke Tornado",
		ias_invoke_tip = "Invokes Tornado by itself\nright before the throw",
		ias_bind_name = "Invoker autostack",
		ias_st_cast_in = "throw in %.1f s",
		ias_st_wont = "won't throw: %s",
		ias_r_empty = "camp is empty",
		ias_r_far = "too far",
		ias_r_dead = "hero is dead",
		ias_r_skills = "need Quas and Wex",
		ias_r_invoke_cd = "Invoke on cooldown (%.1f s)",
		ias_r_tornado_cd = "Tornado on cooldown (%.1f s)",
		ias_r_mana = "not enough mana",
		ias_r_disabled = "hero is disabled",
		ias_r_invoke = "Tornado is not invoked",
		ias_ward = "a ward",
		ias_courier = "a courier",
		ias_ground_creep = "a creep on the ground",
		ias_drag = "Drag circles",
		ias_drag_tip = "How to drag a camp circle.\nWith a modifier a plain click goes to the game",
		ias_drags_lmb = "LMB",
		ias_drags_shift = "Shift + LMB",
		ias_drags_ctrl = "Ctrl + LMB",
		ias_drags_alt = "Alt + LMB",
		ias_drags_off = "Off",
		ias_res_no_order = "didn't throw, hero was busy",
		ias_res_no_hit = "not stacked: Tornado hit no creeps",
		ias_res_partial = "not stacked: Tornado hit %d of %d creeps",
		ias_res_blocker = "not stacked: %s in the camp",
		ias_res_late = "not stacked: a creep lifted %.2f s after :00",
		ias_res_early = "not stacked: a creep landed %.2f s before :00",
		ias_res_miss = "didn't throw: %s",
	},
	ru = {
		ias_group_main = "Автостак",
		ias_group_extra = "Поведение",
		ias_enable = "Включить",
		ias_enable_tip = "Пока зажата клавиша, кидает торнадо,\nчтобы крипы взлетели перед :00",
		ias_gear_extra = "Дополнительно",
		ias_debug = "Отладка в лог",
		ias_debug_tip = "Пишет в лог итоги стаков и тайминги",
		ias_hold_key = "Стак пока зажато",
		ias_hold_key_tip = "Пока клавиша зажата, стакает кемп,\nвыбранный ниже",
		ias_hold_mode = "Что стакать по зажатию",
		ias_hold_modes_near = "Ближайший кемп",
		ias_hold_modes_cursor = "Кемп под курсором",
		ias_land = "Приземление после :00, мс",
		ias_land_tip = "Через сколько мс после :00 первый крип\nдолжен упасть из торнадо",
		ias_reset = "Сбросить кружки",
		ias_reset_tip = "Возвращает кружки кемпов\nна места по умолчанию",
		ias_invoke = "Автоинвок торнадо",
		ias_invoke_tip = "Сам инвокает торнадо\nпрямо перед броском",
		ias_bind_name = "Invoker автостак",
		ias_st_cast_in = "бросок через %.1f с",
		ias_st_wont = "не кину: %s",
		ias_r_empty = "кемп пустой",
		ias_r_far = "далеко",
		ias_r_dead = "герой мертв",
		ias_r_skills = "нужны Quas и Wex",
		ias_r_invoke_cd = "Invoke в КД (%.1f с)",
		ias_r_tornado_cd = "торнадо в КД (%.1f с)",
		ias_r_mana = "мало маны",
		ias_r_disabled = "герой в контроле",
		ias_r_invoke = "торнадо не инвокнут",
		ias_ward = "вард",
		ias_courier = "курьер",
		ias_ground_creep = "крип на земле",
		ias_drag = "Перетаскивать кружки",
		ias_drag_tip = "Чем тащить кружок кемпа.",
		ias_drags_lmb = "ЛКМ",
		ias_drags_shift = "Shift + ЛКМ",
		ias_drags_ctrl = "Ctrl + ЛКМ",
		ias_drags_alt = "Alt + ЛКМ",
		ias_drags_off = "Выключено",
		ias_res_no_order = "не кинул, герой был занят",
		ias_res_no_hit = "не стакнулось: торнадо не задел крипов",
		ias_res_partial = "не стакнулось: торнадо задел %d из %d крипов",
		ias_res_blocker = "не стакнулось: в кемпе %s",
		ias_res_late = "не стакнулось: крип взлетел через %.2f с после :00",
		ias_res_early = "не стакнулось: крип приземлился за %.2f с до :00",
		ias_res_miss = "не кинул: %s",
	},
})

local UI = localization.WrapLibrary(Menu)
local L = localization.Get

local K = {
	VERSION = "1.4.2",
	TAG = "[Invoker AutoStack] ",
	CFG = "invoker_autostack",
	FS = 15,
	RING_R = 110,
	GRAB_PAD = 30,
	SMOOTH = 18,
	RESULT_TIME = 8,
	EDGE = 0.03,
	LIFT = { 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.6, 2.8, 3.0, 3.2 },
	DRAG_MODS = {
		[1] = { Enum.ButtonCode.KEY_LSHIFT, Enum.ButtonCode.KEY_RSHIFT },
		[2] = { Enum.ButtonCode.KEY_LCONTROL, Enum.ButtonCode.KEY_RCONTROL },
		[3] = { Enum.ButtonCode.KEY_LALT, Enum.ButtonCode.KEY_RALT },
	},
	DRAG_OFF = 4,
	TORNADO_MOD = "modifier_invoker_tornado",
	HERO = "npc_dota_hero_invoker",
}

local ui = {}

do
	local page
	local found, hero_tab = pcall(UI.Find, "Heroes", "Hero List", "Invoker")
	if found and hero_tab then
		page = hero_tab:Create("Автостак")
		ui.hero_enable = Menu.Find("Heroes", "Hero List", "Invoker", "Main Settings", "Hero Settings", "Enable")
	else
		local tab = UI.Create("Scripts", "Scripts", "Invoker AutoStack")
		tab:Icon("\u{f72e}")
		page = tab:Create("Settings")
	end

	local g_main = page:Create("ias_group_main", Enum.GroupSide.Left)
	local g_extra = page:Create("ias_group_extra", Enum.GroupSide.Right)

	ui.enable = g_main:Switch("ias_enable", false, "\u{f011}")
	ui.enable:ToolTip("ias_enable_tip")
	local g_gear = ui.enable:Gear("ias_gear_extra")
	ui.debug = g_gear:Switch("ias_debug", true, "\u{f188}")
	ui.debug:ToolTip("ias_debug_tip")

	ui.hold_key = g_main:Bind("ias_hold_key", Enum.ButtonCode.KEY_NONE, "\u{f11c}")
	ui.hold_key:ToolTip("ias_hold_key_tip")
	ui.hold_key:Properties(L("ias_bind_name"))

	ui.hold_mode = g_main:Combo("ias_hold_mode", { "ias_hold_modes_near", "ias_hold_modes_cursor" }, 1)
	ui.hold_mode:Icon("\u{f05b}")

	ui.invoke = g_extra:Switch("ias_invoke", false, "\u{f0e7}")
	ui.invoke:ToolTip("ias_invoke_tip")
	ui.invoke:Unsafe(true)

	ui.land = g_extra:Slider("ias_land", 0, 500, 340, "%d")
	ui.land:Icon("\u{f017}")
	ui.land:ToolTip("ias_land_tip")

	ui.drag = g_extra:Combo("ias_drag", { "ias_drags_lmb", "ias_drags_shift", "ias_drags_ctrl", "ias_drags_alt", "ias_drags_off" }, 0)
	ui.drag:Icon("\u{f0b2}")
	ui.drag:ToolTip("ias_drag_tip")

	ui.reset = g_extra:Button("ias_reset", function() if ui.on_reset then ui.on_reset() end end)
	ui.reset:Icon("\u{f3c5}")
	ui.reset:ToolTip("ias_reset_tip")
end

local function refresh_disabled()
	local on = ui.enable:Get()
	ui.debug:Disabled(not on)
	ui.drag:Disabled(not on)
	ui.hold_key:Disabled(not on)
	ui.hold_mode:Disabled(not on)
	ui.invoke:Disabled(not on)
	ui.land:Disabled(not on)
	ui.reset:Disabled(not on)
end

ui.enable:SetCallback(refresh_disabled, true)

local function log(text)
	if ui.debug:Get() then Log.Write(K.TAG .. text) end
end

Log.Write(K.TAG .. "v" .. K.VERSION .. " loaded")

local floor, min, max, abs, sqrt, huge = math.floor, math.min, math.max, math.abs, math.sqrt, math.huge
local font = Render.LoadFont("Arial", Enum.FontCreate.FONTFLAG_ANTIALIAS, 600)

local C = {
	RING = Color(80, 220, 120, 180),
	TARGET = Color(255, 200, 60, 255),
	GOOD = Color(90, 230, 110, 255),
	BAD = Color(255, 90, 90, 255),
	WARN = Color(255, 205, 80, 255),
	SHADOW = Color(0, 0, 0, 200),
}

local ISSUER = Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY
local ORDER = Enum.UnitOrder

local function safe(fn, ...)
	local ok, r = pcall(fn, ...)
	if ok then return r end
	return nil
end

local function game_clock()
	local start = GameRules.GetGameStartTime()
	if start and start > 0 then return GameRules.GetGameTime() - start end
	return nil
end

local function ping_sec()
	local o = safe(NetChannel.GetLatency, Enum.Flow.FLOW_OUTGOING) or 0
	local i = safe(NetChannel.GetLatency, Enum.Flow.FLOW_INCOMING) or 0
	return o + i
end

local function spec_val(ab, name, fallback)
	local v = safe(Ability.GetLevelSpecialValueFor, ab, name)
	if type(v) ~= "number" or v <= 0 then return fallback end
	return v
end

local function cfg_read_f(key, def) return safe(Config.ReadFloat, K.CFG, key, def) or def end
local function cfg_write_f(key, v) safe(Config.WriteFloat, K.CFG, key, v) end
local function cfg_read_s(key) return safe(Config.ReadString, K.CFG, key, "") or "" end
local function cfg_write_s(key, v) safe(Config.WriteString, K.CFG, key, v) end

local function dist2(ax, ay, bx, by)
	local dx, dy = ax - bx, ay - by
	return sqrt(dx * dx + dy * dy)
end

local S = {
	list = {}, byKey = {}, lastRefresh = -100,
	hero = nil, own = false, ab = nil, active = false,
	target = nil, plan = nil, reason = nil, lock = nil,
	castT = -1, invokeAt = -100,
	neutrals = {},
	firstSeen = {},
	liftDur = {},
	drag = nil,
}

local function find_invoker()
	local me = Heroes.GetLocal()
	if me and NPC.GetUnitName(me) == K.HERO then return me, true end
	local lp = Players.GetLocal()
	local pid = lp and safe(Player.GetPlayerID, lp)
	if not pid then return nil end
	for _, h in pairs(Heroes.GetAll() or {}) do
		if NPC.GetUnitName(h) == K.HERO and not NPC.IsIllusion(h)
			and safe(NPC.IsControllableByPlayer, h, pid) then
			return h, false
		end
	end
	return nil
end

local function script_on()
	return ui.enable:Get() and (not ui.hero_enable or ui.hero_enable:Get())
end

local function refresh_camps(now)
	if now - S.lastRefresh < 5 and #S.list > 0 then return end
	S.lastRefresh = now
	for i, c in pairs(Camps.GetAll() or {}) do
		local key = safe(Entity.GetIndex, c) or i
		if not S.byKey[key] then
			local box = safe(Camp.GetCampBox, c)
			if box and box.min and box.max then
				local bx, by = (box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2
				local camp = {
					min = box.min, max = box.max, hx = bx, hy = by,
					hz = (safe(Entity.GetAbsOrigin, c) or box.min).z,
					bx = bx, by = by, hl = 0,
					key = string.format("pos_%d_%d", floor(bx), floor(by)),
				}
				local saved = cfg_read_s(camp.key)
				local sx, sy = saved:match("^(-?[%d%.]+),(-?[%d%.]+)$")
				if sx then camp.hx, camp.hy = tonumber(sx), tonumber(sy) end
				camp.rx, camp.ry = camp.hx, camp.hy
				camp.corr = cfg_read_f(camp.key .. "_corr", 0)
				S.byKey[key] = camp
				S.list[#S.list + 1] = camp
			end
		end
	end
end

local function in_box(camp, x, y, pad)
	pad = pad or 0
	return x >= camp.min.x - pad and x <= camp.max.x + pad
		and y >= camp.min.y - pad and y <= camp.max.y + pad
end

local function home_vec(camp)
	return Vector(camp.hx, camp.hy, camp.hz)
end

local function camp_of(x, y)
	local best, bd = nil, huge
	for _, c in ipairs(S.list) do
		local d = dist2(x, y, c.hx, c.hy)
		if (in_box(c, x, y, 100) or d < 400) and d < bd then best, bd = c, d end
	end
	return best
end

local function collect_neutrals()
	local res = {}
	for _, u in pairs(NPCs.GetAll(Enum.UnitTypeFlags.TYPE_CREEP) or {}) do
		local idx = Entity.GetIndex(u)
		if S.now and not S.firstSeen[idx] then S.firstSeen[idx] = S.now end
		if NPC.IsNeutral(u) and Entity.IsAlive(u) and not Entity.IsDormant(u) and not NPC.IsWaitingToSpawn(u) then
			local p = Entity.GetAbsOrigin(u)
			res[#res + 1] = { u = u, idx = idx, x = p.x, y = p.y, camp = camp_of(p.x, p.y) }
		end
	end
	S.neutrals = res
end

local function creeps_of(camp)
	local res = {}
	for _, n in ipairs(S.neutrals) do
		if n.camp == camp then res[#res + 1] = n end
	end
	return res
end

ui.on_reset = function()
	S.drag = nil
	for _, camp in ipairs(S.list) do
		camp.hx, camp.hy = camp.bx, camp.by
		cfg_write_s(camp.key, "")
	end
end

local function unit_label(u)
	local name = NPC.GetUnitName(u) or "?"
	if NPC.IsHero(u) then return (name:gsub("npc_dota_hero_", "")) end
	if NPC.IsWard(u) then return L("ias_ward") end
	if NPC.IsCourier(u) then return L("ias_courier") end
	if NPC.IsNeutral(u) then return L("ias_ground_creep") end
	return (name:gsub("npc_dota_", ""))
end

local function blockers_in(camp)
	local res = {}
	for _, u in pairs(NPCs.GetAll() or {}) do
		if Entity.IsAlive(u) and not Entity.IsDormant(u) and not NPC.IsStructure(u)
			and not NPC.IsWaitingToSpawn(u) and not NPC.HasModifier(u, K.TORNADO_MOD) then
			local p = Entity.GetAbsOrigin(u)
			if in_box(camp, p.x, p.y, 0) then res[#res + 1] = unit_label(u) end
		end
	end
	return res
end

local function nearest_camp(pos, max_dist)
	local best, bd = nil, max_dist or huge
	for _, c in ipairs(S.list) do
		local d = dist2(pos.x, pos.y, c.hx, c.hy)
		if d < bd then best, bd = c, d end
	end
	return best
end

local function tornado_stats()
	local ab = S.ab.tornado
	return {
		dist = spec_val(ab, "travel_distance", 2000),
		speed = spec_val(ab, "travel_speed", 1000),
		aoe = spec_val(ab, "area_of_effect", 200),
		cp = safe(Ability.GetCastPoint, ab) or 0.05,
	}
end

local function quas_level()
	return S.ab and S.ab.quas and Ability.GetLevel(S.ab.quas) or 0
end

local function lift_duration()
	local lvl = quas_level()
	if S.liftDur[lvl] then return S.liftDur[lvl] end
	return K.LIFT[max(1, min(#K.LIFT, lvl))]
end

local function best_aim(hx, hy, pts, st)
	local cx, cy = 0, 0
	for _, p in ipairs(pts) do cx, cy = cx + p.x, cy + p.y end
	cx, cy = cx / #pts, cy / #pts

	local base, best = math.atan(cy - hy, cx - hx), nil
	for step = -160, 160 do
		local a = base + math.rad(step * 0.25)
		local ux, uy = math.cos(a), math.sin(a)
		local hits, first, last, worst_perp = 0, huge, 0, 0
		for _, p in ipairs(pts) do
			local rx, ry = p.x - hx, p.y - hy
			local along = rx * ux + ry * uy
			local perp = abs(rx * uy - ry * ux)
			local R = st.aoe + p.hull
			if along > 0 and perp < R - 25 then
				local touch = max(0, along - sqrt(R * R - perp * perp))
				if touch <= st.dist then
					hits = hits + 1
					first, last = min(first, touch), max(last, touch)
					worst_perp = max(worst_perp, perp)
				end
			end
		end
		if hits > 0 then
			local score = (last - first) + worst_perp * 0.6
			if not best or hits > best.hits or (hits == best.hits and score < best.score) then
				best = { hits = hits, first = first, last = last, score = score, ux = ux, uy = uy }
			end
		end
	end
	return best
end

local function make_plan(camp, T)
	local st = tornado_stats()
	local hp = Entity.GetAbsOrigin(S.hero)
	local pts, blind = {}, false
	for _, c in ipairs(creeps_of(camp)) do
		pts[#pts + 1] = { x = c.x, y = c.y, hull = safe(NPC.GetHullRadius, c.u) or 24 }
	end
	if #pts == 0 then
		if safe(FogOfWar.IsPointVisible, home_vec(camp)) then
			return { ok = false, T = T, reason = L("ias_r_empty") }
		end
		blind = true
		pts[1] = { x = camp.hx, y = camp.hy, hull = 24 }
	end

	local aim = best_aim(hp.x, hp.y, pts, st)
	if not aim then return { ok = false, T = T, reason = L("ias_r_far") } end

	local pos = Vector(hp.x + aim.ux * 600, hp.y + aim.uy * 600, hp.z)
	local turn = safe(NPC.GetTimeToFacePosition, S.hero, pos) or 0
	local first = aim.first
	if blind then first = max(0, first - 90) end
	local dur = lift_duration()
	local lift_at = T + ui.land:Get() / 1000 - dur
	local cast_at = lift_at - first / st.speed - st.cp - turn - ping_sec() - camp.corr
	return { ok = true, T = T, castAt = cast_at, pos = pos, blind = blind, dur = dur }
end

local function readiness(plan, now)
	local hero, ab = S.hero, S.ab
	if not Entity.IsAlive(hero) then return L("ias_r_dead") end
	if Ability.GetLevel(ab.quas) == 0 or Ability.GetLevel(ab.wex) == 0 then return L("ias_r_skills") end
	local left = plan.castAt - now
	if Ability.IsHidden(ab.tornado) then
		if not ui.invoke:Get() then return L("ias_r_invoke") end
		local icd = Ability.GetCooldown(ab.invoke) or 0
		if icd > 0.05 and icd > left - 0.3 then return string.format(L("ias_r_invoke_cd"), icd) end
	end
	local tcd = Ability.GetCooldown(ab.tornado) or 0
	if tcd > 0.05 and tcd > left then return string.format(L("ias_r_tornado_cd"), tcd) end
	if NPC.GetMana(hero) < (Ability.GetManaCost(ab.tornado) or 0) then return L("ias_r_mana") end
	return nil
end

local function order_no_target(ab)
	Player.PrepareUnitOrders(Players.GetLocal(), ORDER.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil, Vector(0, 0, 0),
		ab, ISSUER, S.hero, false, false, false, true, "inv_autostack")
end

local function order_cast_pos(ab, pos)
	Player.PrepareUnitOrders(Players.GetLocal(), ORDER.DOTA_UNIT_ORDER_CAST_POSITION, nil, pos,
		ab, ISSUER, S.hero, false, false, false, true, "inv_autostack")
end

local function hold_down()
	if Input.IsInputCaptured() then return false end
	if ui.hold_key:IsDown() then return true end
	local key = ui.hold_key:Get()
	return key ~= nil and key ~= Enum.ButtonCode.KEY_NONE and Input.IsKeyDown(key) == true
end

local function cursor_camp()
	local cur = Input.GetWorldCursorPos()
	if not cur then return nil end
	return nearest_camp(cur, K.RING_R + K.GRAB_PAD) or nearest_camp(cur, 900)
end

local function pick_target(held)
	local hp = Entity.GetAbsOrigin(S.hero)
	if held then
		local camp
		if ui.hold_mode:Get() == 1 then camp = cursor_camp() else camp = nearest_camp(hp) end
		S.heldCamp = camp or S.heldCamp
		return S.heldCamp
	end
	S.heldCamp = nil
	return nil
end

local function camp_name(camp)
	return camp and string.format("%.0f,%.0f", camp.bx, camp.by) or "none"
end

local function set_result(camp, text, color, now)
	camp.result = { text = text, color = color, time = now }
end

local function snapshot_all_neutrals()
	local ids = {}
	for _, u in pairs(NPCs.GetAll(Enum.UnitTypeFlags.TYPE_CREEP) or {}) do
		if NPC.IsNeutral(u) and Entity.IsAlive(u) and not NPC.IsWaitingToSpawn(u) then
			ids[Entity.GetIndex(u)] = true
		end
	end
	return ids
end

local function watch_spawns(camp, p)
	for _, n in ipairs(S.neutrals) do
		if n.camp == camp and not p.before[n.idx] then
			p.spawned = true
			p.newIdx = n.idx
			return
		end
	end
end

local function first_land(p)
	local t
	for _, land in pairs(p.land) do
		if not t or land < t then t = land end
	end
	return t
end

local function learn(camp, p, land_after)
	local land = first_land(p)
	if not land then return end
	local err = land - (p.T + land_after)
	if abs(err) >= 1.5 then return end
	if err < 0 then
		camp.corr = camp.corr + err - 0.02
	else
		camp.corr = camp.corr + err * 0.7
	end
	camp.corr = max(-1.5, min(1.5, camp.corr))
	cfg_write_f(camp.key .. "_corr", camp.corr)
end

local function failure(p)
	if p.spawned then return nil end
	local seen = p.vis and not p.blind
	if seen and p.hits == 0 then return L("ias_res_no_hit") end
	if p.blocker then return string.format(L("ias_res_blocker"), p.blocker) end
	if p.lastLift and p.lastLift > p.T + K.EDGE then
		return string.format(L("ias_res_late"), p.lastLift - p.T)
	end
	local land = first_land(p)
	if land and land < p.T - K.EDGE then
		return string.format(L("ias_res_early"), p.T - land)
	end
	if seen and p.expect and p.hits > 0 and p.hits < p.expect then
		return string.format(L("ias_res_partial"), p.hits, p.expect)
	end
	return nil
end

local function finish(camp, p, now, land_after)
	local text = failure(p)
	learn(camp, p, land_after)
	local land = first_land(p)
	log(string.format("camp %s | %s | lift %s..%s | land %s | hits %d/%s | spawned %s | vis %s/%s | blind %s | in box at %s: [%s] | lift dur %.2f | camp corr %.3f",
		camp_name(camp), text or "no certain failure",
		p.firstLift and string.format("%+.3f", p.firstLift - p.T) or "none",
		p.lastLift and string.format("%+.3f", p.lastLift - p.T) or "none",
		land and string.format("%+.3f", land - p.T) or "none",
		p.hits, tostring(p.expect), tostring(p.spawned), tostring(p.vis), tostring(p.visAfter),
		tostring(p.blind), p.boxAt and string.format("%+.3f", p.boxAt) or "none", p.boxList or "", p.dur or 0, camp.corr))
	if text then set_result(camp, text, C.BAD, now) end
end

local function evaluate_camp(camp, now, land_after)
	local p = camp.pending
	if not p then
		if camp.miss and now >= camp.miss.T then
			set_result(camp, string.format(L("ias_res_miss"), camp.miss.text), C.BAD, now)
			camp.miss = nil
		end
		return
	end
	if (Ability.GetCooldown(S.ab.tornado) or 0) > 0.05 then p.castSeen = true end
	if not p.castSeen and now > p.T + 1.6 then
		set_result(camp, L("ias_res_no_order"), C.BAD, now)
		camp.pending = nil
		return
	end
	if not p.before and now >= p.T - 0.25 then
		p.before = snapshot_all_neutrals()
		p.vis = safe(FogOfWar.IsPointVisible, home_vec(camp))
		p.expect = 0
		for _, n in ipairs(creeps_of(camp)) do
			if p.mine[n.idx] then p.expect = p.expect + 1 end
		end
	end
	if p.before and not p.boxChecked and now >= p.T then
		p.boxChecked = true
		local list = blockers_in(camp)
		p.blocker = list[1]
		p.boxAt = now - p.T
		p.boxList = table.concat(list, ", ")
	end
	if p.before and now >= p.T - 0.05 and now <= p.T + 1.6 then
		watch_spawns(camp, p)
		if safe(FogOfWar.IsPointVisible, home_vec(camp)) then p.visAfter = true end
	end
	if p.before and now > p.T + 1.6 then
		finish(camp, p, now, land_after)
		camp.pending = nil
	end
end

local function any_pending()
	for _, c in ipairs(S.list) do if c.pending then return true end end
	return false
end

local function start_pending(target, T, now, plan)
	local mine = {}
	for _, c in ipairs(creeps_of(target)) do mine[c.idx] = true end
	target.miss, target.result = nil, nil
	target.pending = { T = T, sentAt = now, hits = 0, mine = mine, lifted = {}, land = {}, blind = plan.blind, dur = plan.dur }
	S.castT = T
	log(string.format("cast for camp %s, %.2f s before :00 | quas %d | lift dur %.2f | camp corr %.3f",
		camp_name(target), T - now, quas_level(), plan.dur, target.corr))
end

local function update()
	S.active = false
	if not script_on() then return end

	local hero, own = find_invoker()
	S.hero, S.own = hero, own
	if not hero then return end
	local held = hold_down()
	if held ~= S.held then
		S.held = held
		log("hold key " .. (held and "down" or "up"))
	end
	if not own and not held and not S.lock and not any_pending() then return end

	S.ab = {
		quas = NPC.GetAbility(hero, "invoker_quas"),
		wex = NPC.GetAbility(hero, "invoker_wex"),
		invoke = NPC.GetAbility(hero, "invoker_invoke"),
		tornado = NPC.GetAbility(hero, "invoker_tornado"),
	}
	if not (S.ab.quas and S.ab.wex and S.ab.invoke and S.ab.tornado) then return end

	local now = game_clock()
	if not now then return end
	S.active = true
	S.now = now
	refresh_camps(now)
	collect_neutrals()
	local land_after = ui.land:Get() / 1000
	for _, camp in ipairs(S.list) do evaluate_camp(camp, now, land_after) end

	local target = pick_target(held)
	if S.lock and (S.lock.until_ <= now or (held and target and S.lock.camp ~= target)) then S.lock = nil end
	if S.lock then target = S.lock.camp end
	if target ~= S.target then log("target camp " .. camp_name(target)) end
	S.target, S.plan, S.reason = target, nil, nil
	if not target then return end

	local T = (floor(now / 60) + 1) * 60
	local plan = make_plan(target, T)
	if S.castT == T or (plan.ok and now > plan.castAt + 0.15) then
		T = T + 60
		plan = make_plan(target, T)
	end
	S.plan = plan
	if not plan.ok then S.reason = plan.reason return end

	local reason = readiness(plan, now)
	S.reason = reason
	if plan.castAt - now < 2 then S.lock = { camp = target, until_ = plan.T } end
	if reason then
		if now >= plan.castAt then target.miss = { T = plan.T, text = reason } end
		return
	end

	local ab = S.ab
	if Ability.IsHidden(ab.tornado) then
		if now >= plan.castAt - 2.5 and now - S.invokeAt > 0.4 then
			order_no_target(ab.quas)
			order_no_target(ab.wex)
			order_no_target(ab.wex)
			order_no_target(ab.invoke)
			S.invokeAt = now
		end
		return
	end

	if now >= plan.castAt and S.castT ~= plan.T then
		if NPC.IsStunned(hero) or NPC.IsSilenced(hero) then
			target.miss = { T = plan.T, text = L("ias_r_disabled") }
			return
		end
		order_cast_pos(ab.tornado, plan.pos)
		start_pending(target, plan.T, now, plan)
	end
end

local script = {}

function script.OnUpdate()
	local ok, err = pcall(update)
	if not ok and S.lastErr ~= err then
		S.lastErr = err
		Log.Write(K.TAG .. "update: " .. tostring(err))
	end
end

function script.OnModifierCreate(ent, mod)
	if not S.active or not ent then return end
	if safe(Modifier.GetName, mod) ~= K.TORNADO_MOD then return end
	if not safe(NPC.IsNeutral, ent) then return end
	local now = game_clock()
	if not now then return end
	local idx, pos = Entity.GetIndex(ent), Entity.GetAbsOrigin(ent)
	local seen = S.firstSeen[idx] or now
	for _, camp in ipairs(S.list) do
		local p = camp.pending
		local blind_ok = p and p.blind and dist2(pos.x, pos.y, camp.hx, camp.hy) < 700
			and now < p.T + 0.6 and (now < p.T or seen < p.T - 0.05)
		if p and (p.mine[idx] or blind_ok) then
			if not p.lifted[idx] then
				p.lifted[idx] = true
				p.hits = p.hits + 1
			end
			p.firstLift = min(p.firstLift or now, now)
			p.lastLift = max(p.lastLift or now, now)
			local dur = safe(Modifier.GetDuration, mod)
			if dur and dur > 0 then
				p.land[idx] = now + dur
				local lvl = quas_level()
				if S.liftDur[lvl] ~= dur then
					S.liftDur[lvl] = dur
					log(string.format("lift duration %.2f s at quas %d", dur, lvl))
				end
			end
		end
	end
end

function script.OnModifierDestroy(ent, mod)
	if not S.active or not ent then return end
	if safe(Modifier.GetName, mod) ~= K.TORNADO_MOD then return end
	local now = game_clock()
	if not now then return end
	local idx = safe(Entity.GetIndex, ent)
	for _, camp in ipairs(S.list) do
		local p = camp.pending
		if p and idx and p.lifted[idx] then p.land[idx] = now end
	end
end

function script.OnNpcSpawned(npc)
	if not S.active or not npc or not safe(NPC.IsNeutral, npc) then return end
	local now = game_clock()
	if not now then return end
	local pos = Entity.GetAbsOrigin(npc)
	local camp = camp_of(pos.x, pos.y)
	if not camp then return end
	local p = camp.pending
	if p and now >= p.T - 0.1 and now <= p.T + 1.6 then p.spawned = true end
end

local function camp_under_cursor()
	local cur = Input.GetWorldCursorPos()
	if not cur then return nil end
	local best, bd = nil, K.RING_R + K.GRAB_PAD
	for _, c in ipairs(S.list) do
		local d = dist2(cur.x, cur.y, c.rx, c.ry)
		if d < bd then best, bd = c, d end
	end
	return best
end

local function drag_move()
	local d = S.drag
	if not d then return end
	local cur = Input.GetWorldCursorPos()
	if cur then d.camp.hx, d.camp.hy = cur.x + d.ox, cur.y + d.oy end
end

local function drag_allowed()
	local mode = ui.drag:Get()
	if mode == K.DRAG_OFF then return false end
	local mods = K.DRAG_MODS[mode]
	if not mods then return true end
	return Input.IsKeyDown(mods[1]) == true or Input.IsKeyDown(mods[2]) == true
end

function script.OnKeyEvent(e)
	if e.key ~= Enum.ButtonCode.KEY_MOUSE1 then return true end
	if e.event == Enum.EKeyEvent.EKeyEvent_KEY_DOWN then
		if not script_on() or not S.active or Menu.Opened() or Input.IsInputCaptured() then return true end
		if not drag_allowed() then return true end
		local camp = camp_under_cursor()
		local cur = camp and Input.GetWorldCursorPos()
		if cur then
			S.drag = { camp = camp, ox = camp.hx - cur.x, oy = camp.hy - cur.y }
			return false
		end
	elseif e.event == Enum.EKeyEvent.EKeyEvent_KEY_UP and S.drag then
		drag_move()
		local camp = S.drag.camp
		S.drag = nil
		cfg_write_s(camp.key, string.format("%.0f,%.0f", camp.hx, camp.hy))
		log("moved camp " .. camp_name(camp) .. " to " .. string.format("%.0f,%.0f", camp.hx, camp.hy))
		return false
	end
	return true
end

local function world_circle(cx, cy, cz, r, color, th)
	local pts = {}
	for i = 0, 36 do
		local a = i / 36 * math.pi * 2
		local s, vis = Render.WorldToScreen(Vector(cx + r * math.cos(a), cy + r * math.sin(a), cz))
		if not vis then return end
		pts[#pts + 1] = s
	end
	Render.PolyLine(pts, color, th)
end

local function text_c(txt, x, y, color)
	local sz = Render.TextSize(font, K.FS, txt)
	local px = x - sz.x / 2
	Render.Text(font, K.FS, txt, Vec2(px + 1, y + 1), C.SHADOW)
	Render.Text(font, K.FS, txt, Vec2(px, y), color)
	return sz.y
end

local function status_line(camp, now)
	local p = S.plan
	if camp ~= S.target or not p then return nil end
	if camp.pending then return nil end
	if not p.ok then return p.reason, C.WARN end
	if S.reason then return string.format(L("ias_st_wont"), S.reason), C.BAD end
	return string.format(L("ias_st_cast_in"), max(0, p.castAt - now)), C.TARGET
end

local function draw()
	local now = game_clock() or 0
	local clock = os.clock()
	local dt = min(0.1, max(0, clock - (S.lastDraw or clock)))
	S.lastDraw = clock
	local k = 1 - math.exp(-dt * K.SMOOTH)
	drag_move()
	local hover = (S.drag and S.drag.camp) or (drag_allowed() and camp_under_cursor()) or nil

	for _, camp in ipairs(S.list) do
		camp.rx = camp.rx + (camp.hx - camp.rx) * k
		camp.ry = camp.ry + (camp.hy - camp.ry) * k
		local is_t = (camp == S.target)
		camp.hl = camp.hl + (((is_t or camp == hover) and 1 or 0) - camp.hl) * k
		world_circle(camp.rx, camp.ry, camp.hz, K.RING_R, is_t and C.TARGET or C.RING, 1.5 + 1.5 * camp.hl)

		local s, vis = Render.WorldToScreen(Vector(camp.rx, camp.ry, camp.hz + 120))
		if vis then
			local y = s.y - K.FS * 2
			local res = camp.result
			if res and now - res.time < K.RESULT_TIME then
				y = y + text_c(res.text, s.x, y, res.color)
			end
			local txt, color = status_line(camp, now)
			if txt then text_c(txt, s.x, y, color) end
		end
	end
end

function script.OnDraw()
	if not script_on() or not S.active then S.drag = nil return end
	local ok, err = pcall(draw)
	if not ok and err ~= S.drawErr then
		S.drawErr = err
		Log.Write(K.TAG .. "draw: " .. tostring(err))
	end
end

function script.OnGameEnd()
	S.list, S.byKey, S.lastRefresh, S.castT, S.lock, S.drag = {}, {}, -100, -1, nil, nil
end

return script
