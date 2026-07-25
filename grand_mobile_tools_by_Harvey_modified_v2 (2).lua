--[[
    ╔═══════════════════════════════════════════════════════════════════════════╗
    ║                     GRAND MOBILE ENTERPRISE ADMIN SYSTEM                  ║
    ║                         Grand Mobile Tools by Harvey         ║
    ╠═══════════════════════════════════════════════════════════════════════════╣
    ║  Script Name: Grand Mobile Tools by Harvey                        ║
    ║  Author: Harvey                                             ║
    ║  Version: 2.1.0                                                           ║
    ║  Description: Grand Mobile Tools by Harvey ║
    ║  License: Harvey                                                      ║
    ║  Timezone: UTC+5 (Uzbekistan)                                             ║
    ║  Hotkey: M - Toggle Menu                                                  ║
    ╚═══════════════════════════════════════════════════════════════════════════╝
]]

script_name("Grand Mobile Tools by Harvey")
script_author("Harvey")
script_version("2.1.0")
script_description("Grand Mobile Tools by Harvey")
script_properties("work-in-pause", "forced-reloading-only")

-- ============================================
-- REQUIRED LIBRARIES
-- ============================================
local sampev = require("lib.samp.events")
local imgui = require("mimgui")
local inicfg = require("inicfg")
local vkeys = require("vkeys")
local encoding = require("encoding")
local ffi = require("ffi")
local user32 = nil
-- FFI declaration can fail on reload (already declared); loading user32 must still continue.
pcall(function()
    ffi.cdef[[
        short __stdcall GetAsyncKeyState(int vKey);
    ]]
end)
pcall(function()
    user32 = ffi.load("user32")
end)
encoding.default = "CP1251"
local u8 = encoding.UTF8

-- mimgui compatibility for older builds (common on SA-MP 0.3.7 R1 setups)
if not imgui.ImBool and imgui.new and imgui.new.bool then
    imgui.ImBool = function(v) return imgui.new.bool(v or false) end
end
if not imgui.ImInt and imgui.new and imgui.new.int then
    imgui.ImInt = function(v) return imgui.new.int(v or 0) end
end
if not imgui.ImFloat and imgui.new and imgui.new.float then
    imgui.ImFloat = function(v) return imgui.new.float(v or 0.0) end
end

-- ============================================
-- GLOBAL CONSTANTS
-- ============================================
local CONFIG = {
    VERSION = "2.1.0",
    TIMEZONE_OFFSET = 5, -- UTC+5
    AUTO_SAVE_INTERVAL = 60, -- seconds
    AFK_TIMEOUT = 120, -- seconds
    MAX_LOG_ENTRIES = 1000,
    MAX_REPORT_HISTORY = 50,
    UI = {
        ROUNDING = 12,
        SHADOW_ALPHA = 0.3,
        ANIMATION_SPEED = 0.15,
        TAB_COUNT = 13
    }
}

-- Colors will be initialized after imgui is ready
local COLORS = {}

-- ============================================
-- UTILITY MANAGER
-- ============================================
local UtilityManager = {
    data = {},
    timers = {},
    cache = {}
}

function UtilityManager.initialize()
    UtilityManager.data.startTime = os.clock()
    UtilityManager.data.sessionId = string.format("%08X", os.time())
end

function UtilityManager.getTimestamp()
    return os.time()
end

function UtilityManager.getUzTimestamp()
    return UtilityManager.getTimestamp() + (CONFIG.TIMEZONE_OFFSET * 3600)
end

function UtilityManager.getUzDateTable(timestamp)
    local uzTimestamp = tonumber(timestamp) or UtilityManager.getUzTimestamp()
    return os.date("!*t", uzTimestamp)
end

function UtilityManager.getUzWeekdayIndex(timestamp)
    local uzTimestamp = tonumber(timestamp) or UtilityManager.getUzTimestamp()
    local weekday = tonumber(os.date("!%w", uzTimestamp)) or 0
    if weekday == 0 then
        return 7
    end
    return weekday
end

function UtilityManager.getUzMonthString(timestamp)
    local t = UtilityManager.getUzDateTable(timestamp)
    return string.format("%04d-%02d", tonumber(t.year) or 0, tonumber(t.month) or 0)
end

function UtilityManager.getUzWeekStartString(timestamp)
    local uzTimestamp = tonumber(timestamp) or UtilityManager.getUzTimestamp()
    local t = UtilityManager.getUzDateTable(uzTimestamp)
    local dayStart = uzTimestamp - (((t.hour or 0) * 3600) + ((t.min or 0) * 60) + (t.sec or 0))
    local weekdayIndex = UtilityManager.getUzWeekdayIndex(uzTimestamp)
    local mondayStart = dayStart - ((weekdayIndex - 1) * 86400)
    return UtilityManager.getDateString(mondayStart)
end

function UtilityManager.formatTime(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d:%02d", hours, mins, secs)
end

function UtilityManager.formatDuration(startTime)
    return UtilityManager.formatTime(os.clock() - startTime)
end

function UtilityManager.getDateString(timestamp)
    local t = UtilityManager.getUzDateTable(timestamp)
    return string.format("%04d-%02d-%02d", tonumber(t.year) or 0, tonumber(t.month) or 0, tonumber(t.day) or 0)
end

function UtilityManager.isNewDay(lastDate)
    local current = UtilityManager.getDateString()
    return current ~= lastDate
end

function UtilityManager.isNewWeek()
    return UtilityManager.getUzWeekdayIndex() == 1 and (UtilityManager.getUzDateTable().hour or 0) == 0
end

function UtilityManager.isNewMonth()
    local t = UtilityManager.getUzDateTable()
    return (tonumber(t.day) or 0) == 1 and (tonumber(t.hour) or 0) == 0
end

function UtilityManager.tableCopy(tbl)
    local copy = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            copy[k] = UtilityManager.tableCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

function UtilityManager.clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

function UtilityManager.lerp(a, b, t)
    return a + (b - a) * t
end

function UtilityManager.rgbToFloat(r, g, b, a)
    return imgui.ImVec4(r / 255, g / 255, b / 255, (a or 255) / 255)
end

function UtilityManager.generateId()
    return string.format("%08X%04X", os.time(), math.random(0, 65535))
end

function UtilityManager.getConfigPath(fileName)
    -- inicfg expects config name (without full path); it writes to moonloader/config automatically
    local name = tostring(fileName or "config")
    name = name:gsub("\\", "/")
    name = name:match("([^/]+)$") or name
    name = name:gsub("%.ini$", "")
    return name
end

function UtilityManager.safeIniSave(data, path)
    local ok, err = pcall(inicfg.save, data, path)
    if not ok then
        LogManager.error(string.format("INI save failed (%s): %s", path, tostring(err)))
        return false
    end
    return true
end

function UtilityManager.getPlayerCoords()
    if not PLAYER_PED or (doesCharExist and not doesCharExist(PLAYER_PED)) then
        return false, 0, 0, 0
    end

    local a, b, c, d = getCharCoordinates(PLAYER_PED)

    -- Some MoonLoader builds return: success, x, y, z
    if type(a) == "boolean" then
        if not a then return false, 0, 0, 0 end
        return true, b or 0, c or 0, d or 0
    end

    -- Other builds return: x, y, z
    return true, a or 0, b or 0, c or 0
end

function UtilityManager.splitString(str, delimiter)
    local result = {}
    for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

function UtilityManager.trim(s)
    return s:match("^%s*(.-)%s*$")
end

function UtilityManager.casefoldUtf8Cyrillic(text)
    local value = tostring(text or "")
    local map = {
        ["А"] = "а", ["Б"] = "б", ["В"] = "в", ["Г"] = "г", ["Д"] = "д",
        ["Е"] = "е", ["Ё"] = "ё", ["Ж"] = "ж", ["З"] = "з", ["И"] = "и",
        ["Й"] = "й", ["К"] = "к", ["Л"] = "л", ["М"] = "м", ["Н"] = "н",
        ["О"] = "о", ["П"] = "п", ["Р"] = "р", ["С"] = "с", ["Т"] = "т",
        ["У"] = "у", ["Ф"] = "ф", ["Х"] = "х", ["Ц"] = "ц", ["Ч"] = "ч",
        ["Ш"] = "ш", ["Щ"] = "щ", ["Ъ"] = "ъ", ["Ы"] = "ы", ["Ь"] = "ь",
        ["Э"] = "э", ["Ю"] = "ю", ["Я"] = "я"
    }
    for upper, lower in pairs(map) do
        value = value:gsub(upper, lower)
    end
    return value:lower()
end

function UtilityManager.casefoldCp1251Cyrillic(text)
    local value = tostring(text or "")
    local out = {}
    for i = 1, #value do
        local b = value:byte(i)
        if b >= 65 and b <= 90 then
            b = b + 32
        elseif b >= 192 and b <= 223 then
            b = b + 32
        elseif b == 168 then
            b = 184
        end
        out[i] = string.char(b)
    end
    return table.concat(out)
end

function UtilityManager.getMatchVariants(text)
    local source = UtilityManager.trim(tostring(text or ""))
    if source == "" then
        return {}
    end

    local variants = {}
    local seen = {}

    local function addVariant(value)
        local candidate = UtilityManager.trim(tostring(value or ""))
        if candidate ~= "" and not seen[candidate] then
            seen[candidate] = true
            table.insert(variants, candidate)
        end
    end

    local function addWithCasefold(value)
        addVariant(value)
        addVariant(UtilityManager.casefoldUtf8Cyrillic(value))
        addVariant(UtilityManager.casefoldCp1251Cyrillic(value))
    end

    addWithCasefold(source)

    local okUtf8, utf8Value = pcall(function()
        return u8(source)
    end)
    if okUtf8 and type(utf8Value) == "string" then
        addWithCasefold(utf8Value)
    end

    if type(u8) == "table" and type(u8.decode) == "function" then
        local okDecode, decoded = pcall(u8.decode, u8, source)
        if okDecode and type(decoded) == "string" then
            addWithCasefold(decoded)
        end
    end

    if type(u8) == "table" and type(u8.encode) == "function" then
        local okEncode, encoded = pcall(u8.encode, u8, source)
        if okEncode and type(encoded) == "string" then
            addWithCasefold(encoded)
        end
    end

    return variants
end

function UtilityManager.toUtf8(text)
    local value = tostring(text or "")
    if value == "" then
        return ""
    end

    local ok, converted = pcall(u8, value)
    if ok and type(converted) == "string" and converted ~= "" then
        return converted
    end

    return value
end

function UtilityManager.startsWith(str, prefix)
    return str:sub(1, #prefix) == prefix
end

function UtilityManager.contains(table, value)
    for _, v in pairs(table) do
        if v == value then return true end
    end
    return false
end

-- ============================================
-- LOG MANAGER
-- ============================================
local LogManager = {
    logs = {},
    categories = {
        SYSTEM = "SYSTEM",
        SECURITY = "SECURITY",
        ADMIN = "ADMIN",
        PLAYER = "PLAYER",
        REPORT = "REPORT",
        ERROR = "ERROR"
    }
}

function LogManager.initialize()
    LogManager.logs = {}
end

function LogManager.add(category, message, data)
    local entry = {
        id = UtilityManager.generateId(),
        timestamp = os.time(),
        formattedTime = os.date("%H:%M:%S"),
        category = category,
        message = message,
        data = data or {}
    }

    table.insert(LogManager.logs, 1, entry)

    if #LogManager.logs > CONFIG.MAX_LOG_ENTRIES then
        table.remove(LogManager.logs)
    end

    return entry.id
end

function LogManager.system(message, data)
    return LogManager.add(LogManager.categories.SYSTEM, message, data)
end

function LogManager.security(message, data)
    return LogManager.add(LogManager.categories.SECURITY, message, data)
end

function LogManager.admin(message, data)
    return LogManager.add(LogManager.categories.ADMIN, message, data)
end

function LogManager.player(message, data)
    return LogManager.add(LogManager.categories.PLAYER, message, data)
end

function LogManager.report(message, data)
    return LogManager.add(LogManager.categories.REPORT, message, data)
end

function LogManager.error(message, data)
    return LogManager.add(LogManager.categories.ERROR, message, data)
end

function LogManager.getByCategory(category)
    local result = {}
    for _, log in ipairs(LogManager.logs) do
        if log.category == category then
            table.insert(result, log)
        end
    end
    return result
end

function LogManager.getRecent(count)
    count = count or 50
    local result = {}
    for i = 1, math.min(count, #LogManager.logs) do
        table.insert(result, LogManager.logs[i])
    end
    return result
end

function LogManager.clear()
    LogManager.logs = {}
    LogManager.system("Logs cleared")
end

function LogManager.exportToFile(filename)
    local file = io.open(filename, "w")
    if file then
        for _, log in ipairs(LogManager.logs) do
            file:write(string.format("[%s] [%s] %s\n",
                log.formattedTime, log.category, log.message))
        end
        file:close()
        return true
    end
    return false
end

-- ============================================
-- SETTINGS MANAGER
-- ============================================
local SettingsManager = {
    data = {},
    defaults = {
        theme = "dark",
        primaryColor = {27, 174, 96},
        hotkey = vkeys.VK_M,
        afkEnabled = true,
        autoSave = false,
        saveInterval = 60,
        notifications = true,
        language = "uz",
        confirmReset = true,
        soundEnabled = true,
        autoAcceptReports = false,
        autoReplyTemplate = "Admin tekshiruvida. Iltimos, kuting.",
        godMode = false,
        invisible = false,
        adminDuty = false,
        furaKillEnabled = false,
        spectateQuickPosX = 0,
        spectateQuickPosY = 0,
        spectateQuickWidth = 460,
        spectateQuickHeight = 120,
        spectateModerationPosX = 14,
        spectateModerationPosY = 0,
        spectateModerationWidth = 360,
        spectateModerationHeight = 214,
        hudClockEnabled = false,
        hudClockPosX = 0,
        hudClockPosY = 0,
        hudDateEnabled = false,
        hudDatePosX = 0,
        hudDatePosY = 0,
        hudAdminEnabled = false,
        hudAdminPosX = 0,
        hudAdminPosY = 0,
        hudScale = 1.0,
        hudOpacity = 1.0,
        hudAdminCommand = "/admin"
    },
    configPath = ""
}

function SettingsManager.initialize()
    SettingsManager.configPath = UtilityManager.getConfigPath("GrandMobileAdmin.ini")
    SettingsManager.load()
end

function UtilityManager.bufferToString(buf)
    if type(buf) == "cdata" then
        return ffi.string(buf)
    end
    return tostring(buf or "")
end

function UtilityManager.setBufferString(buf, text)
    if type(buf) ~= "cdata" then
        return false
    end

    local value = tostring(text or "")
    local size = tonumber(ffi.sizeof(buf)) or 0
    if size <= 0 then
        return false
    end

    ffi.fill(buf, size, 0)
    if value ~= "" and size > 1 then
        local clipped = value:sub(1, size - 1)
        ffi.copy(buf, clipped)
    end

    return true
end

function SettingsManager.load()
    local dir = getWorkingDirectory() .. "\\config"
    if not doesDirectoryExist(dir) then
        createDirectory(dir)
    end

    local rawConfig = inicfg.load(nil, SettingsManager.configPath)
    local config = nil
    if type(rawConfig) == "table" then
        if type(rawConfig.main) == "table" then
            config = rawConfig.main
        else
            -- Backward compatibility with old flat/no-section format.
            config = rawConfig
        end
    end

    SettingsManager.data = UtilityManager.tableCopy(SettingsManager.defaults)
    if type(config) == "table" then
        for key, value in pairs(config) do
            if type(value) == "table" and type(SettingsManager.data[key]) == "table" then
                for innerKey, innerValue in pairs(value) do
                    SettingsManager.data[key][innerKey] = innerValue
                end
            else
                SettingsManager.data[key] = value
            end
        end
    end

    -- Normalize color table because some INI parsers store indexes as strings.
    local primary = SettingsManager.data.primaryColor
    if type(primary) == "table" then
        local r = tonumber(primary[1] or primary["1"]) or 27
        local g = tonumber(primary[2] or primary["2"]) or 174
        local b = tonumber(primary[3] or primary["3"]) or 96
        SettingsManager.data.primaryColor = { r, g, b }
    else
        SettingsManager.data.primaryColor = { 27, 174, 96 }
    end

    -- Force panel toggle to M for consistent behavior
    SettingsManager.data.hotkey = vkeys.VK_M
    -- Disable autosave to avoid repeated inicfg exceptions on this environment
    SettingsManager.data.autoSave = false
    LogManager.system("Settings loaded")
end

function SettingsManager.save()
    local dir = getWorkingDirectory() .. "\\config"
    if not doesDirectoryExist(dir) then
        createDirectory(dir)
    end

    UtilityManager.safeIniSave({ main = SettingsManager.data }, SettingsManager.configPath)
    LogManager.system("Settings saved")
end

function SettingsManager.get(key)
    return SettingsManager.data[key]
end

function SettingsManager.set(key, value)
    SettingsManager.data[key] = value
    if SettingsManager.data.autoSave then
        SettingsManager.save()
    end
end

function SettingsManager.reset()
    SettingsManager.data = UtilityManager.tableCopy(SettingsManager.defaults)
    SettingsManager.save()
    LogManager.system("Settings reset to defaults")
end

function SettingsManager.getHotkeyName()
    return vkeys.id_to_name(SettingsManager.data.hotkey) or "M"
end

-- Forward declaration (used by StatsManager before AFKManager table is defined)
local AFKManager
-- Forward declaration (used by ReportCatchManager before MainUI table is defined)
local MainUI
-- Forward declaration (used by SpectateQuickPanel for shared templates)
local ReportCatchManager
-- Forward declaration (used by MainUI before manager body is defined)
local AdminModesManager
-- Forward declaration (used by MainUI render loop)
local TeleportClickManager

-- ============================================
-- STATS MANAGER
-- ============================================
local StatsManager = {
    schemaVersion = 2,
    weekdayLabels = {
        u8"Dushanba",
        u8"Seshanba",
        u8"Chorshanba",
        u8"Payshanba",
        u8"Juma",
        u8"Shanba",
        u8"Yakshanba"
    },
    data = {
        daily = { answers = 0, playtime = 0, date = "" },
        weekly = { answers = 0, playtime = 0, week = "", weekStart = "" },
        monthly = { answers = 0, playtime = 0, month = "" },
        session = { answers = 0, playtime = 0, startTime = 0 },
        weekdays = {},
        lastAnswerId = 0,
        efficiency = 0,
        rank = "Bronze",
        trend = {},
        schemaVersion = 2
    },
    history = {},
    lastResetCheck = 0,
    lastPersistTime = 0,
    lastPlaytimeTick = 0,
    pendingAnswerConfirmations = {},
    lastOutgoingAnswer = { signature = "", time = 0 }
}

function StatsManager.makeEmptyWeekdays()
    local days = {}
    for i = 1, 7 do
        days[i] = { answers = 0, playtime = 0 }
    end
    return days
end

function StatsManager.ensureWeekdays()
    if type(StatsManager.data.weekdays) ~= "table" then
        StatsManager.data.weekdays = StatsManager.makeEmptyWeekdays()
        return
    end

    for i = 1, 7 do
        local day = StatsManager.data.weekdays[i]
        if type(day) ~= "table" then
            StatsManager.data.weekdays[i] = { answers = 0, playtime = 0 }
        else
            day.answers = math.max(0, math.floor(tonumber(day.answers) or 0))
            day.playtime = math.max(0, math.floor(tonumber(day.playtime) or 0))
        end
    end
end

function StatsManager.getWeekdayLabel(index)
    local idx = tonumber(index) or 1
    return StatsManager.weekdayLabels[idx] or tostring(idx)
end

function StatsManager.getWeekdayData(index)
    StatsManager.ensureWeekdays()
    local idx = UtilityManager.clamp(tonumber(index) or 1, 1, 7)
    return StatsManager.data.weekdays[idx]
end

function StatsManager.getCurrentContext()
    local uzNow = UtilityManager.getUzTimestamp()
    return {
        now = uzNow,
        dayIndex = UtilityManager.getUzWeekdayIndex(uzNow),
        date = UtilityManager.getDateString(uzNow),
        weekStart = UtilityManager.getUzWeekStartString(uzNow),
        month = UtilityManager.getUzMonthString(uzNow)
    }
end

function StatsManager.recalculateWeeklyTotals()
    StatsManager.ensureWeekdays()
    local answers = 0
    local playtime = 0
    for i = 1, 7 do
        answers = answers + (tonumber(StatsManager.data.weekdays[i].answers) or 0)
        playtime = playtime + (tonumber(StatsManager.data.weekdays[i].playtime) or 0)
    end
    StatsManager.data.weekly.answers = answers
    StatsManager.data.weekly.playtime = playtime
end

function StatsManager.resetAllNow(silent)
    local ctx = StatsManager.getCurrentContext()
    StatsManager.data.weekdays = StatsManager.makeEmptyWeekdays()
    StatsManager.data.daily = { answers = 0, playtime = 0, date = ctx.date }
    StatsManager.data.weekly = { answers = 0, playtime = 0, week = ctx.weekStart, weekStart = ctx.weekStart }
    StatsManager.data.monthly = { answers = 0, playtime = 0, month = ctx.month }
    StatsManager.data.session = { answers = 0, playtime = 0, startTime = os.time() }
    StatsManager.data.lastAnswerId = 0
    StatsManager.data.efficiency = 0
    StatsManager.data.rank = "Bronze"
    StatsManager.data.trend = {}
    StatsManager.data.schemaVersion = StatsManager.schemaVersion
    StatsManager.lastPlaytimeTick = os.time()
    if not silent then
        LogManager.system("Stats reset: Hozir/Hafta/Oy 0 ga tushirildi")
    end
end

function StatsManager.initialize()
    StatsManager.lastPlaytimeTick = os.time()
    StatsManager.load()
    StatsManager.syncPeriods()
    StatsManager.updateRank()
    StatsManager.updateEfficiency()
    LogManager.system("Stats manager initialized")
end

function StatsManager.load()
    local dir = getWorkingDirectory() .. "\\config"
    if not doesDirectoryExist(dir) then
        createDirectory(dir)
    end

    local path = UtilityManager.getConfigPath("stats.ini")
    local ok, saved = pcall(inicfg.load, nil, path)
    if not ok then
        LogManager.error(string.format("Stats load failed (%s): %s", path, tostring(saved)))
        saved = nil
    end

    if not saved then
        local fallbackOk, fallbackSaved = pcall(inicfg.load, nil, "stats")
        if fallbackOk then
            saved = fallbackSaved
        end
    end

    local meta = saved and saved.meta or {}
    local loadedSchema = tonumber(meta.schema or meta.schemaVersion or 0) or 0

    StatsManager.resetAllNow(true)

    if saved and loadedSchema >= StatsManager.schemaVersion then
        local daily = saved.daily or {}
        local weekly = saved.weekly or {}
        local monthly = saved.monthly or {}
        local session = saved.session or {}
        local weekdaysSaved = saved.weekdays or {}

        StatsManager.data.daily.answers = math.max(0, math.floor(tonumber(daily.answers) or 0))
        StatsManager.data.daily.playtime = math.max(0, math.floor(tonumber(daily.playtime) or 0))
        StatsManager.data.daily.date = tostring(daily.date or StatsManager.data.daily.date)

        StatsManager.data.weekly.answers = math.max(0, math.floor(tonumber(weekly.answers) or 0))
        StatsManager.data.weekly.playtime = math.max(0, math.floor(tonumber(weekly.playtime) or 0))
        StatsManager.data.weekly.weekStart = tostring(weekly.weekStart or weekly.week or StatsManager.data.weekly.weekStart)
        StatsManager.data.weekly.week = tostring(weekly.week or StatsManager.data.weekly.weekStart)

        StatsManager.data.monthly.answers = math.max(0, math.floor(tonumber(monthly.answers) or 0))
        StatsManager.data.monthly.playtime = math.max(0, math.floor(tonumber(monthly.playtime) or 0))
        StatsManager.data.monthly.month = tostring(monthly.month or StatsManager.data.monthly.month)

        StatsManager.data.session.answers = math.max(0, math.floor(tonumber(session.answers) or 0))
        StatsManager.data.session.playtime = math.max(0, math.floor(tonumber(session.playtime) or 0))
        StatsManager.data.session.startTime = tonumber(session.startTime) or os.time()
        StatsManager.data.lastAnswerId = math.max(0, math.floor(tonumber(session.lastAnswerId) or tonumber(saved.lastAnswerId) or 0))

        StatsManager.ensureWeekdays()
        local hasWeekdayData = false
        for i = 1, 7 do
            local ansKey = "d" .. i .. "_answers"
            local playKey = "d" .. i .. "_playtime"
            local answers = tonumber(weekdaysSaved[ansKey])
            local playtime = tonumber(weekdaysSaved[playKey])
            if answers ~= nil then
                StatsManager.data.weekdays[i].answers = math.max(0, math.floor(answers))
                hasWeekdayData = true
            end
            if playtime ~= nil then
                StatsManager.data.weekdays[i].playtime = math.max(0, math.floor(playtime))
                hasWeekdayData = true
            end
        end

        if not hasWeekdayData then
            local currentDayIndex = UtilityManager.getUzWeekdayIndex()
            StatsManager.data.weekdays[currentDayIndex].answers = StatsManager.data.daily.answers
            StatsManager.data.weekdays[currentDayIndex].playtime = StatsManager.data.daily.playtime
        end
    else
        -- One-time migration for old stats layout: reset counters from now.
        StatsManager.resetAllNow(false)
    end

    StatsManager.data.schemaVersion = StatsManager.schemaVersion
    StatsManager.recalculateWeeklyTotals()
    local _, changed = StatsManager.syncPeriods()
    if changed or loadedSchema < StatsManager.schemaVersion then
        StatsManager.save()
    end
end

function StatsManager.save()
    local dir = getWorkingDirectory() .. "\\config"
    if not doesDirectoryExist(dir) then
        createDirectory(dir)
    end

    local path = UtilityManager.getConfigPath("stats.ini")
    local weekdaysToSave = {}
    StatsManager.ensureWeekdays()
    for i = 1, 7 do
        weekdaysToSave["d" .. i .. "_answers"] = tonumber(StatsManager.data.weekdays[i].answers) or 0
        weekdaysToSave["d" .. i .. "_playtime"] = tonumber(StatsManager.data.weekdays[i].playtime) or 0
    end

    local data = {
        meta = {
            schema = StatsManager.schemaVersion,
            savedAt = os.time()
        },
        daily = StatsManager.data.daily,
        weekly = StatsManager.data.weekly,
        monthly = StatsManager.data.monthly,
        session = {
            answers = tonumber(StatsManager.data.session.answers) or 0,
            playtime = tonumber(StatsManager.data.session.playtime) or 0,
            startTime = tonumber(StatsManager.data.session.startTime) or os.time(),
            lastAnswerId = tonumber(StatsManager.data.lastAnswerId) or 0
        },
        weekdays = weekdaysToSave,
        lastAnswerId = tonumber(StatsManager.data.lastAnswerId) or 0
    }

    local ok, err = pcall(inicfg.save, data, path)
    if not ok then
        LogManager.error(string.format("Stats save failed (%s): %s", path, tostring(err)))
        local fallbackOk, fallbackErr = pcall(inicfg.save, data, "stats")
        if not fallbackOk then
            LogManager.error(string.format("Stats fallback save failed (stats): %s", tostring(fallbackErr)))
            return false
        end
    end

    return true
end

function StatsManager.addAnswer(id)
    local ctx = StatsManager.syncPeriods()
    StatsManager.ensureWeekdays()
    local dayBucket = StatsManager.data.weekdays[ctx.dayIndex]
    StatsManager.data.session.answers = StatsManager.data.session.answers + 1
    dayBucket.answers = (tonumber(dayBucket.answers) or 0) + 1
    StatsManager.data.daily.answers = dayBucket.answers
    StatsManager.data.weekly.answers = StatsManager.data.weekly.answers + 1
    StatsManager.data.monthly.answers = StatsManager.data.monthly.answers + 1
    StatsManager.data.lastAnswerId = id

    table.insert(StatsManager.data.trend, {
        time = os.time(),
        answers = StatsManager.data.session.answers
    })

    if #StatsManager.data.trend > 100 then
        table.remove(StatsManager.data.trend, 1)
    end

    StatsManager.updateRank()
    StatsManager.updateEfficiency()
    StatsManager.save()
end

function StatsManager.registerOutgoingAnswer(id, rawCommand)
    local answerId = tonumber(id)
    if not answerId then
        return false
    end

    local nowClock = os.clock()
    local signature = string.format("%d|%s", answerId, tostring(rawCommand or ""))
    if StatsManager.lastOutgoingAnswer.signature == signature and
       nowClock - (StatsManager.lastOutgoingAnswer.time or 0) < 0.25 then
        return false
    end

    StatsManager.lastOutgoingAnswer.signature = signature
    StatsManager.lastOutgoingAnswer.time = nowClock

    local now = os.time()
    table.insert(StatsManager.pendingAnswerConfirmations, {
        id = answerId,
        time = now
    })

    if #StatsManager.pendingAnswerConfirmations > 200 then
        table.remove(StatsManager.pendingAnswerConfirmations, 1)
    end

    return true
end

function StatsManager.consumeOutgoingAnswer(id)
    local answerId = tonumber(id)
    if not answerId then
        return false
    end

    local now = os.time()
    local pending = StatsManager.pendingAnswerConfirmations
    local matchedIndex = nil

    for i = #pending, 1, -1 do
        local item = pending[i]
        if not item or now - (item.time or 0) > 20 then
            table.remove(pending, i)
        elseif not matchedIndex and tonumber(item.id) == answerId then
            matchedIndex = i
        end
    end

    if matchedIndex then
        table.remove(pending, matchedIndex)
        return true
    end

    return false
end

function StatsManager.updatePlaytime()
    local now = os.time()
    if StatsManager.lastPlaytimeTick == 0 then
        StatsManager.lastPlaytimeTick = now
        return
    end

    local delta = now - StatsManager.lastPlaytimeTick
    if delta <= 0 then
        return
    end
    StatsManager.lastPlaytimeTick = now

    local isAfk = AFKManager and AFKManager.isAFK
    local steps = math.min(delta, 600)
    for _ = 1, steps do
        local ctx = StatsManager.syncPeriods()
        if not isAfk then
            StatsManager.ensureWeekdays()
            local dayBucket = StatsManager.data.weekdays[ctx.dayIndex]
            StatsManager.data.session.playtime = (tonumber(StatsManager.data.session.playtime) or 0) + 1
            dayBucket.playtime = (tonumber(dayBucket.playtime) or 0) + 1
            StatsManager.data.daily.playtime = dayBucket.playtime
            StatsManager.data.weekly.playtime = (tonumber(StatsManager.data.weekly.playtime) or 0) + 1
            StatsManager.data.monthly.playtime = (tonumber(StatsManager.data.monthly.playtime) or 0) + 1
        end
    end

    if delta > steps then
        local ctx = StatsManager.syncPeriods()
        local rest = delta - steps
        if not isAfk then
            StatsManager.ensureWeekdays()
            local dayBucket = StatsManager.data.weekdays[ctx.dayIndex]
            StatsManager.data.session.playtime = (tonumber(StatsManager.data.session.playtime) or 0) + rest
            dayBucket.playtime = (tonumber(dayBucket.playtime) or 0) + rest
            StatsManager.data.daily.playtime = dayBucket.playtime
            StatsManager.data.weekly.playtime = (tonumber(StatsManager.data.weekly.playtime) or 0) + rest
            StatsManager.data.monthly.playtime = (tonumber(StatsManager.data.monthly.playtime) or 0) + rest
        end
    end

    if now - StatsManager.lastPersistTime >= 30 then
        StatsManager.save()
        StatsManager.lastPersistTime = now
    end
end

function StatsManager.updateRank()
    local answers = StatsManager.data.monthly.answers
    if answers >= 1000 then
        StatsManager.data.rank = "Diamond"
    elseif answers >= 500 then
        StatsManager.data.rank = "Platinum"
    elseif answers >= 250 then
        StatsManager.data.rank = "Gold"
    elseif answers >= 100 then
        StatsManager.data.rank = "Silver"
    else
        StatsManager.data.rank = "Bronze"
    end
end

function StatsManager.updateEfficiency()
    local sessionDuration = StatsManager.getSessionDuration()
    if sessionDuration > 0 then
        StatsManager.data.efficiency = math.min(100,
            (StatsManager.data.session.answers / (sessionDuration / 3600)) * 10)
    else
        StatsManager.data.efficiency = 0
    end
end

function StatsManager.checkReset()
    local currentTime = os.time()
    if currentTime - StatsManager.lastResetCheck < 60 then return end
    StatsManager.lastResetCheck = currentTime

    local _, changed = StatsManager.syncPeriods()
    if changed then
        StatsManager.save()
    end
end

function StatsManager.resetDaily(context, silent)
    local ctx = context or StatsManager.getCurrentContext()
    StatsManager.ensureWeekdays()
    local dayBucket = StatsManager.data.weekdays[ctx.dayIndex]
    dayBucket.answers = 0
    dayBucket.playtime = 0
    StatsManager.recalculateWeeklyTotals()
    StatsManager.data.daily = { answers = 0, playtime = 0, date = ctx.date }
    if not silent then
        LogManager.system("Daily stats reset")
    end
end

function StatsManager.resetWeekly(context, silent)
    local ctx = context or StatsManager.getCurrentContext()
    StatsManager.data.weekdays = StatsManager.makeEmptyWeekdays()
    StatsManager.data.weekly = { answers = 0, playtime = 0, week = ctx.weekStart, weekStart = ctx.weekStart }
    if not silent then
        LogManager.system("Weekly stats reset")
    end
end

function StatsManager.resetMonthly(context, silent)
    local ctx = context or StatsManager.getCurrentContext()
    StatsManager.data.monthly = { answers = 0, playtime = 0, month = ctx.month }
    if not silent then
        LogManager.system("Monthly stats reset")
    end
end

function StatsManager.syncPeriods()
    local ctx = StatsManager.getCurrentContext()
    local changed = false

    StatsManager.ensureWeekdays()
    if tostring(StatsManager.data.weekly.weekStart or "") ~= tostring(ctx.weekStart) then
        StatsManager.resetWeekly(ctx, true)
        changed = true
    end

    if tostring(StatsManager.data.monthly.month or "") ~= tostring(ctx.month) then
        StatsManager.resetMonthly(ctx, true)
        changed = true
    end

    if tostring(StatsManager.data.daily.date or "") ~= tostring(ctx.date) then
        StatsManager.resetDaily(ctx, true)
        changed = true
    end

    StatsManager.ensureWeekdays()
    local dayBucket = StatsManager.data.weekdays[ctx.dayIndex]
    StatsManager.data.daily.answers = tonumber(dayBucket.answers) or 0
    StatsManager.data.daily.playtime = tonumber(dayBucket.playtime) or 0
    StatsManager.data.weekly.weekStart = ctx.weekStart
    StatsManager.data.weekly.week = ctx.weekStart
    StatsManager.data.schemaVersion = StatsManager.schemaVersion

    if changed then
        LogManager.system(string.format(
            "Stats period changed (UZ): day=%s week=%s month=%s",
            ctx.date, ctx.weekStart, ctx.month))
    end

    return ctx, changed
end

function StatsManager.getSessionDuration()
    return math.max(0, math.floor(tonumber(StatsManager.data.session.playtime) or 0))
end

function StatsManager.getPerformanceScore()
    local score = 0
    score = score + (StatsManager.data.session.answers * 10)
    score = score + (StatsManager.data.efficiency * 5)
    score = score + (StatsManager.getSessionDuration() / 60)
    return math.floor(score)
end

function StatsManager.getUptime()
    local activeTime = StatsManager.getSessionDuration()
    local afkTime = math.max(0, math.floor((AFKManager and AFKManager.totalAFKTime) or 0))
    local total = activeTime + afkTime
    if total <= 0 then return 100 end
    return math.floor((activeTime / total) * 100)
end

function StatsManager.getWeeklyTrend()
    if #StatsManager.data.trend < 2 then return 0 end
    local first = StatsManager.data.trend[1].answers
    local last = StatsManager.data.trend[#StatsManager.data.trend].answers
    if first == 0 then return 0 end
    return math.floor(((last - first) / first) * 100)
end

-- ============================================
-- AFK MANAGER
-- ============================================
AFKManager = {
    isAFK = false,
    lastActivity = 0,
    afkStartTime = 0,
    totalAFKTime = 0,
    position = { x = 0, y = 0, z = 0 }
}

function AFKManager.initialize()
    AFKManager.lastActivity = os.clock()
    AFKManager.checkPosition()
end

function AFKManager.checkPosition()
    local result, x, y, z = UtilityManager.getPlayerCoords()
    if result then
        local moved = math.abs(x - AFKManager.position.x) > 0.5 or
                      math.abs(y - AFKManager.position.y) > 0.5 or
                      math.abs(z - AFKManager.position.z) > 0.5

        if moved then
            if AFKManager.isAFK then
                AFKManager.endAFK()
            end
            AFKManager.lastActivity = os.clock()
        elseif not AFKManager.isAFK then
            local inactive = os.clock() - AFKManager.lastActivity
            if inactive >= CONFIG.AFK_TIMEOUT then
                AFKManager.startAFK()
            end
        end

        AFKManager.position.x, AFKManager.position.y, AFKManager.position.z = x, y, z
    end
end

function AFKManager.startAFK()
    AFKManager.isAFK = true
    AFKManager.afkStartTime = os.clock()
    LogManager.system("AFK started")
end

function AFKManager.endAFK()
    if AFKManager.isAFK then
        AFKManager.totalAFKTime = AFKManager.totalAFKTime + (os.clock() - AFKManager.afkStartTime)
        AFKManager.isAFK = false
        AFKManager.lastActivity = os.clock()
        LogManager.system("AFK ended")
    end
end

function AFKManager.getCurrentAFKTime()
    if AFKManager.isAFK then
        return os.clock() - AFKManager.afkStartTime
    end
    return 0
end

-- ============================================
-- REPORT MANAGER
-- ============================================
local ReportManager = {
    reports = {},
    history = {},
    templates = {},
    autoAccept = false,
    lastReportTime = 0,
    cooldown = 5,
    spamDetection = {}
}

function ReportManager.initialize()
    ReportManager.loadTemplates()
    ReportManager.loadHistory()
    LogManager.system("Report manager initialized")
end

function ReportManager.loadTemplates()
    ReportManager.templates = {
        { id = 1, name = "Tekshiruvda", text = "Admin tekshiruvida. Iltimos, kuting." },
        { id = 2, name = "DM Check", text = "DeathMatch tekshiruvi o'tkazilmoqda." },
        { id = 3, name = "DB Check", text = "DriveBy tekshiruvi o'tkazilmoqda." },
        { id = 4, name = "SK Check", text = "SpawnKill tekshiruvi o'tkazilmoqda." },
        { id = 5, name = "Raketa", text = "Raketa tekshiruvi o'tkazilmoqda." }
    }
end

function ReportManager.loadHistory()
    local path = getWorkingDirectory() .. "/config/reports.ini"
end

function ReportManager.saveHistory()
end

function ReportManager.addReport(id, reporter, suspect, reason, category)
    local report = {
        id = id,
        reporter = reporter,
        suspect = suspect,
        reason = reason,
        category = category or "General",
        timestamp = os.time(),
        status = "pending",
        priority = "normal",
        admin = nil,
        resolution = nil
    }

    if ReportManager.spamDetection[reporter] then
        local lastTime = ReportManager.spamDetection[reporter]
        if os.time() - lastTime < 30 then
            report.priority = "spam"
        end
    end
    ReportManager.spamDetection[reporter] = os.time()

    for _, r in ipairs(ReportManager.reports) do
        if r.reporter == reporter and r.suspect == suspect and r.reason == reason then
            report.priority = "duplicate"
            break
        end
    end

    table.insert(ReportManager.reports, 1, report)

    if ReportManager.autoAccept and os.time() - ReportManager.lastReportTime > ReportManager.cooldown then
        ReportManager.acceptReport(id)
        ReportManager.lastReportTime = os.time()
    end

    LogManager.report(string.format("New report #%d from %s", id, reporter))
    return report
end

function ReportManager.acceptReport(id)
    for _, report in ipairs(ReportManager.reports) do
        if report.id == id then
            report.status = "accepted"
            report.admin = "You"
            LogManager.report(string.format("Report #%d accepted", id))
            return true
        end
    end
    return false
end

function ReportManager.closeReport(id, resolution)
    for i, report in ipairs(ReportManager.reports) do
        if report.id == id then
            report.status = "closed"
            report.resolution = resolution
            table.insert(ReportManager.history, 1, report)
            table.remove(ReportManager.reports, i)

            if #ReportManager.history > CONFIG.MAX_REPORT_HISTORY then
                table.remove(ReportManager.history)
            end

            LogManager.report(string.format("Report #%d closed: %s", id, resolution))
            return true
        end
    end
    return false
end

function ReportManager.teleportToReporter(id)
    local report = ReportManager.getReport(id)
    if report then
        return true
    end
    return false
end

function ReportManager.teleportToSuspect(id)
    local report = ReportManager.getReport(id)
    if report then
        return true
    end
    return false
end

function ReportManager.getReport(id)
    for _, report in ipairs(ReportManager.reports) do
        if report.id == id then
            return report
        end
    end
    return nil
end

function ReportManager.getByCategory(category)
    local result = {}
    for _, report in ipairs(ReportManager.reports) do
        if report.category == category then
            table.insert(result, report)
        end
    end
    return result
end

function ReportManager.getStatistics()
    local stats = {
        total = #ReportManager.reports + #ReportManager.history,
        pending = 0,
        accepted = 0,
        closed = #ReportManager.history,
        spam = 0,
        duplicate = 0
    }

    for _, report in ipairs(ReportManager.reports) do
        if report.status == "pending" then
            stats.pending = stats.pending + 1
        elseif report.status == "accepted" then
            stats.accepted = stats.accepted + 1
        end
        if report.priority == "spam" then
            stats.spam = stats.spam + 1
        elseif report.priority == "duplicate" then
            stats.duplicate = stats.duplicate + 1
        end
    end

    return stats
end

function ReportManager.addTemplate(name, text)
    table.insert(ReportManager.templates, {
        id = #ReportManager.templates + 1,
        name = name,
        text = text
    })
end

function ReportManager.deleteTemplate(id)
    for i, template in ipairs(ReportManager.templates) do
        if template.id == id then
            table.remove(ReportManager.templates, i)
            return true
        end
    end
    return false
end

-- ============================================
-- SPECTATE QUICK PANEL
-- ============================================
local SpectateQuickPanel = {
    active = false,
    targetId = nil,
    targetNick = "",
    cursorVisible = true,
    rightMouseLastState = false,
    spaceLastState = false,
    rightMouseToggleRequested = false,
    reportReviewMode = false,
    reportAnswerId = nil,
    showTemplatePicker = false,
    showTpCarModePicker = false,
    tpCarBusy = false,
    getCarBusy = false,
    moderationMode = "none",
    form = nil,
    ui = {
        width = 460,
        height = 86,
        bottomOffset = 16,
        quickInitialized = false,
        quickPos = { x = 0, y = 0 },
        quickSize = { width = 460, height = 120 },
        moderationInitialized = false,
        moderationPos = { x = 14, y = 0 },
        moderationSize = { width = 360, height = 214 }
    }
}

local NavigatorManager = {
    pending = nil,
    lastDialog = nil
}

function NavigatorManager.clearPending()
    NavigatorManager.pending = nil
    NavigatorManager.lastDialog = nil
end

function NavigatorManager.isGpsDialogTitle(title)
    local variants = UtilityManager.getMatchVariants(title or "")
    if #variants == 0 then
        table.insert(variants, tostring(title or ""))
    end

    for _, variant in ipairs(variants) do
        local loweredUtf8 = UtilityManager.casefoldUtf8Cyrillic(tostring(variant or ""))
        local loweredCp = UtilityManager.casefoldCp1251Cyrillic(tostring(variant or ""))
        if loweredUtf8:find("gps", 1, true) or
           loweredUtf8:find("navigator", 1, true) or
           loweredUtf8:find("navig", 1, true) or
           loweredUtf8:find("нави", 1, true) or
           loweredCp:find("gps", 1, true) or
           loweredCp:find("navigator", 1, true) then
            return true
        end
    end

    return false
end

function NavigatorManager.normalizeMarkerText(rawText)
    local value = tostring(rawText or ""):gsub("{%x%x%x%x%x%x}", "")
    local firstColumn = value:match("^[^\t]+")
    if firstColumn and UtilityManager.trim(firstColumn or "") ~= "" then
        value = firstColumn
    end
    value = value:gsub("^%s*[%d%[%]%.%-%)]+%s*", "")
    value = value:gsub("[\r\n]+", " ")
    value = value:gsub("%s%s+", " ")
    value = UtilityManager.trim(value)
    if #value > 110 then
        value = value:sub(1, 107) .. "..."
    end
    return value
end

function NavigatorManager.getMarkerControlAction(markerText)
    local marker = UtilityManager.casefoldUtf8Cyrillic(tostring(markerText or ""))
    marker = UtilityManager.trim(marker)
    if marker == "" then
        return "empty"
    end

    local backExact = {
        ["orqaga"] = true,
        ["back"] = true,
        ["назад"] = true
    }
    local exitExact = {
        ["bekor"] = true,
        ["cancel"] = true,
        ["chiqish"] = true,
        ["exit"] = true,
        ["отмена"] = true,
        ["выход"] = true
    }

    if backExact[marker] then
        return "back"
    end
    if exitExact[marker] then
        return "exit"
    end
    return nil
end

function NavigatorManager.appendTrail(marker)
    local pending = NavigatorManager.pending
    if not pending then
        return
    end
    pending.trail = pending.trail or {}
    local value = UtilityManager.trim(tostring(marker or ""))
    if value == "" then
        return
    end
    local last = pending.trail[#pending.trail]
    if last and NavigatorManager.normalizeMarkerText(last) == NavigatorManager.normalizeMarkerText(value) then
        return
    end
    table.insert(pending.trail, value)
end

function NavigatorManager.popTrail()
    local pending = NavigatorManager.pending
    if not pending or not pending.trail or #pending.trail == 0 then
        return
    end
    table.remove(pending.trail, #pending.trail)
end

function NavigatorManager.buildPayloadText()
    local pending = NavigatorManager.pending
    if not pending then
        return ""
    end
    local trail = pending.trail or {}
    if #trail == 0 then
        return ""
    end
    local path = table.concat(trail, " -> ")
    path = UtilityManager.trim(path)
    if path == "" then
        return ""
    end
    local payload = "/gps " .. path
    if #payload > 120 then
        payload = payload:sub(1, 117) .. "..."
    end
    return payload
end

function NavigatorManager.finalizePendingAnswer()
    local pending = NavigatorManager.pending
    if not pending then
        return
    end

    local targetId = tonumber(pending.targetId)
    if not targetId then
        sampAddChatMessage("[Harvey] NAVIGATOR: target ID yo'qoldi.", 0xFF6666)
        NavigatorManager.clearPending()
        return
    end

    local payload = NavigatorManager.buildPayloadText()
    if payload == "" then
        sampAddChatMessage("[Harvey] NAVIGATOR: tanlangan metka topilmadi.", 0xFF6666)
        NavigatorManager.clearPending()
        return
    end

    sampSendChat(string.format("/ans %d %s", targetId, payload))
    sampAddChatMessage(string.format("[Harvey] NAVIGATOR: /ans %d %s", targetId, payload), 0x33FF66)
    LogManager.report(string.format(
        "Navigator answer sent (%s): /ans %d %s",
        tostring(pending.source or "unknown"),
        targetId,
        payload
    ))

    NavigatorManager.clearPending()
end

function NavigatorManager.startForTarget(targetId, sourceTag)
    local id = tonumber(targetId)
    if not id or id <= 0 then
        sampAddChatMessage("[Harvey] NAVIGATOR: target ID topilmadi.", 0xFF6666)
        return false
    end

    if type(sampSendChat) ~= "function" then
        sampAddChatMessage("[Harvey] NAVIGATOR: chat API topilmadi.", 0xFF6666)
        return false
    end

    NavigatorManager.pending = {
        targetId = id,
        source = tostring(sourceTag or "unknown"),
        startedAt = os.clock(),
        dialogId = nil,
        trail = {},
        waitFinalize = false,
        finalizeAt = 0
    }
    NavigatorManager.lastDialog = nil

    sampSendChat("/gps")
    sampAddChatMessage(string.format(
        "[Harvey] NAVIGATOR: /gps ochildi. Nuqtani tanlang, /ans %d ga yuboriladi.",
        id
    ), 0x33FF66)
    return true
end

function NavigatorManager.captureGpsDialog(dialogId, style, title, button1, button2, text)
    if not NavigatorManager.pending then
        return
    end

    if not NavigatorManager.isGpsDialogTitle(title) then
        return
    end

    NavigatorManager.lastDialog = {
        id = tonumber(dialogId),
        style = tonumber(style) or 0,
        title = tostring(title or ""),
        button1 = tostring(button1 or ""),
        button2 = tostring(button2 or ""),
        text = tostring(text or "")
    }
    NavigatorManager.pending.dialogId = tonumber(dialogId)
    NavigatorManager.pending.waitFinalize = false
    NavigatorManager.pending.finalizeAt = 0
end

function NavigatorManager.extractMarkerFromDialog(dialogInfo, listboxId, inputText)
    local info = dialogInfo or {}
    local style = tonumber(info.style) or 0
    local rawText = tostring(info.text or "")
    local lines = {}

    for line in rawText:gmatch("[^\r\n]+") do
        local cleaned = UtilityManager.trim(tostring(line or ""):gsub("{%x%x%x%x%x%x}", ""))
        if cleaned ~= "" then
            table.insert(lines, line)
        end
    end

    local selectable = {}
    local startAt = (style == 5) and 2 or 1 -- TABLIST_HEADERS has a header row.
    for i = startAt, #lines do
        table.insert(selectable, lines[i])
    end
    if #selectable == 0 then
        selectable = lines
    end

    local selectedIndex = (tonumber(listboxId) or 0) + 1
    local selectedLine = selectable[selectedIndex]
    if not selectedLine then
        selectedLine = selectable[1]
    end

    local marker = NavigatorManager.normalizeMarkerText(selectedLine)
    if marker == "" then
        marker = NavigatorManager.normalizeMarkerText(inputText)
    end

    return marker
end

function NavigatorManager.handleDialogResponse(dialogId, button, listboxId, inputText)
    local pending = NavigatorManager.pending
    if not pending then
        return
    end

    local responseDialogId = tonumber(dialogId)
    local expectedDialogId = tonumber(pending.dialogId)
    if expectedDialogId and responseDialogId and expectedDialogId ~= responseDialogId then
        return
    end

    local clickedButton = tonumber(button) or 0
    if clickedButton ~= 1 then
        sampAddChatMessage("[Harvey] NAVIGATOR: bekor qilindi.", 0xFF9933)
        NavigatorManager.clearPending()
        return
    end

    local marker = NavigatorManager.extractMarkerFromDialog(
        NavigatorManager.lastDialog,
        listboxId,
        inputText
    )

    if marker == "" then
        sampAddChatMessage("[Harvey] NAVIGATOR: tanlangan metka topilmadi.", 0xFF6666)
        NavigatorManager.clearPending()
        return
    end

    local action = NavigatorManager.getMarkerControlAction(marker)
    if action == "back" then
        NavigatorManager.popTrail()
        pending.waitFinalize = false
        pending.finalizeAt = 0
        return
    end
    if action == "exit" or action == "empty" then
        NavigatorManager.clearPending()
        return
    end

    NavigatorManager.appendTrail(marker)
    pending.waitFinalize = true
    pending.finalizeAt = os.clock() + 1.75
end

function NavigatorManager.update()
    local pending = NavigatorManager.pending
    if not pending or not pending.waitFinalize then
        return
    end

    local now = os.clock()
    if now < (tonumber(pending.finalizeAt) or 0) then
        return
    end

    if type(sampIsDialogActive) == "function" and sampIsDialogActive() then
        pending.finalizeAt = now + 0.40
        return
    end

    NavigatorManager.finalizePendingAnswer()
end

function SpectateQuickPanel.loadUiFromSettings()
    if not SettingsManager or not SettingsManager.get then
        return
    end

    local ui = SpectateQuickPanel.ui
    ui.quickPos = ui.quickPos or { x = 0, y = 0 }
    ui.quickSize = ui.quickSize or { width = 460, height = 120 }
    ui.moderationPos = ui.moderationPos or { x = 14, y = 0 }
    ui.moderationSize = ui.moderationSize or { width = 360, height = 214 }

    ui.quickPos.x = tonumber(SettingsManager.get("spectateQuickPosX")) or ui.quickPos.x
    ui.quickPos.y = tonumber(SettingsManager.get("spectateQuickPosY")) or ui.quickPos.y
    ui.quickSize.width = tonumber(SettingsManager.get("spectateQuickWidth")) or ui.quickSize.width
    ui.quickSize.height = tonumber(SettingsManager.get("spectateQuickHeight")) or ui.quickSize.height

    ui.moderationPos.x = tonumber(SettingsManager.get("spectateModerationPosX")) or ui.moderationPos.x
    ui.moderationPos.y = tonumber(SettingsManager.get("spectateModerationPosY")) or ui.moderationPos.y
    ui.moderationSize.width = tonumber(SettingsManager.get("spectateModerationWidth")) or ui.moderationSize.width
    ui.moderationSize.height = tonumber(SettingsManager.get("spectateModerationHeight")) or ui.moderationSize.height

    ui.quickInitialized = false
    ui.moderationInitialized = false
end

function SpectateQuickPanel.storeUiToSettings()
    if not SettingsManager or not SettingsManager.data then
        return
    end

    local ui = SpectateQuickPanel.ui
    local quickPos = ui.quickPos or {}
    local quickSize = ui.quickSize or {}
    local modPos = ui.moderationPos or {}
    local modSize = ui.moderationSize or {}

    SettingsManager.data.spectateQuickPosX = tonumber(quickPos.x) or 0
    SettingsManager.data.spectateQuickPosY = tonumber(quickPos.y) or 0
    SettingsManager.data.spectateQuickWidth = tonumber(quickSize.width) or 460
    SettingsManager.data.spectateQuickHeight = tonumber(quickSize.height) or 120
    SettingsManager.data.spectateModerationPosX = tonumber(modPos.x) or 14
    SettingsManager.data.spectateModerationPosY = tonumber(modPos.y) or 0
    SettingsManager.data.spectateModerationWidth = tonumber(modSize.width) or 360
    SettingsManager.data.spectateModerationHeight = tonumber(modSize.height) or 214
end

function SpectateQuickPanel.saveUiToDisk()
    SpectateQuickPanel.storeUiToSettings()
    if SettingsManager and SettingsManager.save then
        SettingsManager.save()
    end
end

function SpectateQuickPanel.start(playerId)
    local id = tonumber(playerId)
    if not id then return end

    SpectateQuickPanel.active = true
    SpectateQuickPanel.targetId = id
    SpectateQuickPanel.cursorVisible = true
    SpectateQuickPanel.rightMouseLastState = false
    SpectateQuickPanel.spaceLastState = false
    SpectateQuickPanel.rightMouseToggleRequested = false
    SpectateQuickPanel.reportReviewMode = false
    SpectateQuickPanel.reportAnswerId = nil
    SpectateQuickPanel.showTemplatePicker = false
    SpectateQuickPanel.showTpCarModePicker = false
    SpectateQuickPanel.tpCarBusy = false
    SpectateQuickPanel.getCarBusy = false
    SpectateQuickPanel.moderationMode = "none"
    SpectateQuickPanel.ui.moderationInitialized = false

    if sampIsPlayerConnected(id) then
        SpectateQuickPanel.targetNick = sampGetPlayerNickname(id) or ""
    else
        SpectateQuickPanel.targetNick = ""
    end
end

function SpectateQuickPanel.stop()
    SpectateQuickPanel.active = false
    SpectateQuickPanel.targetId = nil
    SpectateQuickPanel.targetNick = ""
    SpectateQuickPanel.cursorVisible = true
    SpectateQuickPanel.rightMouseLastState = false
    SpectateQuickPanel.spaceLastState = false
    SpectateQuickPanel.rightMouseToggleRequested = false
    SpectateQuickPanel.reportReviewMode = false
    SpectateQuickPanel.reportAnswerId = nil
    SpectateQuickPanel.showTemplatePicker = false
    SpectateQuickPanel.showTpCarModePicker = false
    SpectateQuickPanel.tpCarBusy = false
    SpectateQuickPanel.getCarBusy = false
    SpectateQuickPanel.moderationMode = "none"
    SpectateQuickPanel.ui.moderationInitialized = false
end

function SpectateQuickPanel.enableReportReviewMode(reportAnswerId)
    local id = tonumber(reportAnswerId)
    if not id then return end
    SpectateQuickPanel.reportReviewMode = true
    SpectateQuickPanel.reportAnswerId = id
end

function SpectateQuickPanel.clearReportReviewMode()
    SpectateQuickPanel.reportReviewMode = false
    SpectateQuickPanel.reportAnswerId = nil
end

function SpectateQuickPanel.ensureFormState()
    if SpectateQuickPanel.form then
        return
    end

    SpectateQuickPanel.form = {
        jailMinutes = imgui.ImInt(60),
        banDays = imgui.ImInt(3),
        muteMinutes = imgui.ImInt(60),
        rmuteMinutes = imgui.ImInt(60),
        jailReason = imgui.new.char[128](),
        banReason = imgui.new.char[128](),
        warnReason = imgui.new.char[128](),
        muteReason = imgui.new.char[128](),
        rmuteReason = imgui.new.char[128](),
        runmuteReason = imgui.new.char[128](),
        unmuteReason = imgui.new.char[128]()
    }
end

function SpectateQuickPanel.getReasonFromBuffer(buf, fallback)
    local value = UtilityManager.trim(UtilityManager.bufferToString(buf) or "")
    if value == "" then
        return fallback or "No reason"
    end
    return value
end

function SpectateQuickPanel.getSharedReplyTemplates()
    if ReportCatchManager and ReportCatchManager.templates then
        return ReportCatchManager.templates
    end
    return {}
end

function SpectateQuickPanel.resolveAnswerId()
    local fromSpec = tonumber(SpectateQuickPanel.reportAnswerId)
    if fromSpec and fromSpec > 0 then
        return fromSpec
    end

    if ReportCatchManager and ReportCatchManager.currentReport then
        local fromCurrent = tonumber(ReportCatchManager.currentReport.id)
        if fromCurrent and fromCurrent > 0 then
            return fromCurrent
        end
    end

    if ReportCatchManager and ReportCatchManager.waitingReportId then
        local fromWaiting = tonumber(ReportCatchManager.waitingReportId)
        if fromWaiting and fromWaiting > 0 then
            return fromWaiting
        end
    end

    return nil
end

function SpectateQuickPanel.toggleTemplatePicker()
    SpectateQuickPanel.showTemplatePicker = not SpectateQuickPanel.showTemplatePicker
end

function SpectateQuickPanel.sendSlap()
    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then return end

    sampSendChat(string.format("/slap %d", id))
    LogManager.admin(string.format("Quick panel: /slap %d", id))
end

function SpectateQuickPanel.sendSharedTemplateReply(templateId)
    local targetId = SpectateQuickPanel.resolveTemplateTargetId()
    if not targetId then
        sampAddChatMessage("[Harvey] Javob yuborish uchun SP target ID topilmadi.", 0xFF6666)
        return
    end

    local templates = SpectateQuickPanel.getSharedReplyTemplates()
    local picked = nil
    for _, template in ipairs(templates) do
        if tonumber(template.id) == tonumber(templateId) then
            picked = template
            break
        end
    end

    if not picked then
        return
    end

    sampSendChat(string.format("/ans %d %s", targetId, picked.text or ""))
    LogManager.report(string.format(
        "Spectate template reply sent: player #%d via template #%d",
        targetId,
        tonumber(picked.id) or 0))

    if ReportCatchManager and ReportCatchManager.markAnswered then
        ReportCatchManager.markAnswered(targetId)
    end
    if ReportCatchManager and ReportCatchManager.popupOpen and ReportCatchManager.currentReport and
       tonumber(ReportCatchManager.currentReport.id) == tonumber(targetId) and
       ReportCatchManager.closePopup then
        ReportCatchManager.closePopup()
    end
end

function SpectateQuickPanel.openModerationMode(mode)
    SpectateQuickPanel.ensureFormState()
    SpectateQuickPanel.moderationMode = mode or "none"
end

function SpectateQuickPanel.applyJailToTarget()
    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then return end
    SpectateQuickPanel.ensureFormState()

    local minutes = tonumber(SpectateQuickPanel.form.jailMinutes[0]) or 60
    minutes = math.max(1, minutes)
    local reason = SpectateQuickPanel.getReasonFromBuffer(SpectateQuickPanel.form.jailReason, "DM")

    sampSendChat(string.format("/jail %d %d %s", id, minutes, reason))
    LogManager.admin(string.format("Quick panel: /jail %d %d %s", id, minutes, reason))
end

function SpectateQuickPanel.applyBanToTarget()
    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then return end
    SpectateQuickPanel.ensureFormState()

    local days = tonumber(SpectateQuickPanel.form.banDays[0]) or 1
    days = math.max(1, days)
    local reason = SpectateQuickPanel.getReasonFromBuffer(SpectateQuickPanel.form.banReason, "Ban")

    sampSendChat(string.format("/ban %d %d %s", id, days, reason))
    LogManager.admin(string.format("Quick panel: /ban %d %d %s", id, days, reason))
end

function SpectateQuickPanel.applyWarnToTarget()
    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then return end
    SpectateQuickPanel.ensureFormState()

    local reason = SpectateQuickPanel.getReasonFromBuffer(SpectateQuickPanel.form.warnReason, "Warn")

    sampSendChat(string.format("/warn %d %s", id, reason))
    LogManager.admin(string.format("Quick panel: /warn %d %s", id, reason))
end

function SpectateQuickPanel.applyMuteToTarget()
    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then return end
    SpectateQuickPanel.ensureFormState()

    local minutes = tonumber(SpectateQuickPanel.form.muteMinutes[0]) or 60
    minutes = math.max(1, minutes)
    local reason = SpectateQuickPanel.getReasonFromBuffer(SpectateQuickPanel.form.muteReason, "Mute")

    sampSendChat(string.format("/mute %d %d %s", id, minutes, reason))
    LogManager.admin(string.format("Quick panel: /mute %d %d %s", id, minutes, reason))
end

function SpectateQuickPanel.applyRMuteToTarget()
    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then return end
    SpectateQuickPanel.ensureFormState()

    local minutes = tonumber(SpectateQuickPanel.form.rmuteMinutes[0]) or 60
    minutes = math.max(1, minutes)
    local reason = SpectateQuickPanel.getReasonFromBuffer(SpectateQuickPanel.form.rmuteReason, "RMute")

    sampSendChat(string.format("/rmute %d %d %s", id, minutes, reason))
    LogManager.admin(string.format("Quick panel: /rmute %d %d %s", id, minutes, reason))
end

function SpectateQuickPanel.applyRunmuteToTarget()
    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then return end
    SpectateQuickPanel.ensureFormState()

    local reason = SpectateQuickPanel.getReasonFromBuffer(SpectateQuickPanel.form.runmuteReason, "Runmute")

    sampSendChat(string.format("/runmute %d %s", id, reason))
    LogManager.admin(string.format("Quick panel: /runmute %d %s", id, reason))
end

function SpectateQuickPanel.applyUnmuteToTarget()
    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then return end
    SpectateQuickPanel.ensureFormState()

    local reason = SpectateQuickPanel.getReasonFromBuffer(SpectateQuickPanel.form.unmuteReason, "Unmute")

    sampSendChat(string.format("/unmute %d %s", id, reason))
    LogManager.admin(string.format("Quick panel: /unmute %d %s", id, reason))
end

function SpectateQuickPanel.isRightMouseClicked()
    local down = false

    -- Keep RMB toggle strict edge-only. Some builds report double press with wasKeyPressed/isKeyJustPressed.
    if isKeyDown then
        local ok, keyDown = pcall(isKeyDown, vkeys.VK_RBUTTON)
        if ok and keyDown then
            down = true
        end
    end

    if not down and user32 and user32.GetAsyncKeyState then
        local ok, state = pcall(user32.GetAsyncKeyState, 0x02)
        if ok and state ~= nil then
            local value = tonumber(state) or 0
            down = (value < 0) or (value >= 0x8000)
        end
    end

    local clicked = down and not SpectateQuickPanel.rightMouseLastState

    SpectateQuickPanel.rightMouseLastState = down
    return clicked
end

function SpectateQuickPanel.isSpacePressed()
    if isKeyJustPressed then
        local ok, pressed = pcall(isKeyJustPressed, vkeys.VK_SPACE)
        if ok and pressed then
            SpectateQuickPanel.spaceLastState = true
            return true
        end
    end

    if wasKeyPressed then
        local ok, pressed = pcall(wasKeyPressed, vkeys.VK_SPACE)
        if ok and pressed then
            SpectateQuickPanel.spaceLastState = true
            return true
        end
    end

    local down = false
    if isKeyDown then
        local ok, keyDown = pcall(isKeyDown, vkeys.VK_SPACE)
        if ok and keyDown then
            down = true
        end
    end

    if not down and user32 and user32.GetAsyncKeyState then
        local ok, state = pcall(user32.GetAsyncKeyState, 0x20)
        if ok and state ~= nil then
            local value = tonumber(state) or 0
            down = (value < 0) or (value >= 0x8000)
        end
    end

    local pressed = down and not SpectateQuickPanel.spaceLastState
    SpectateQuickPanel.spaceLastState = down
    return pressed
end

function SpectateQuickPanel.requestRightMouseToggle()
    SpectateQuickPanel.rightMouseToggleRequested = true
end

function SpectateQuickPanel.consumeRightMouseToggleRequest()
    if SpectateQuickPanel.rightMouseToggleRequested then
        SpectateQuickPanel.rightMouseToggleRequested = false
        return true
    end
    return false
end

function SpectateQuickPanel.handleCommand(command, args)
    if command == "sp" or command == "spec" then
        local id = tonumber(args[2])
        if id then
            SpectateQuickPanel.start(id)
        end
        return
    end

    if command == "spoff" or command == "specoff" then
        SpectateQuickPanel.stop()
        return
    end

    if SpectateQuickPanel.active and (command == "goto" or command == "gethere") then
        SpectateQuickPanel.stop()
    end
end

function SpectateQuickPanel.getTargetDisplay()
    local id = SpectateQuickPanel.targetId
    if not id then
        return "No target"
    end

    if sampIsPlayerConnected(id) then
        local nick = sampGetPlayerNickname(id) or ""
        SpectateQuickPanel.targetNick = nick
        return string.format("[%d] %s", id, nick)
    end

    if SpectateQuickPanel.targetNick ~= "" then
        return string.format("[%d] %s", id, SpectateQuickPanel.targetNick)
    end

    return string.format("[%d]", id)
end

function SpectateQuickPanel.sendSpoff()
    local id = SpectateQuickPanel.targetId
    if not id then return end
    sampSendChat(string.format("/spoff %d", id))
    LogManager.admin(string.format("Quick panel: /spoff %d", id))
end

function SpectateQuickPanel.sendFlip()
    local id = SpectateQuickPanel.targetId
    if not id then return end
    sampSendChat(string.format("/flip %d", id))
    LogManager.admin(string.format("Quick panel: /flip %d", id))
end

function SpectateQuickPanel.sendGetinfo()
    local id = SpectateQuickPanel.targetId
    if not id then return end
    sampSendChat(string.format("/getinfo %d", id))
    LogManager.admin(string.format("Quick panel: /getinfo %d", id))
end

function SpectateQuickPanel.sendAfterSpOff(commandName)
    local id = SpectateQuickPanel.targetId
    if not id then return end

    sampSendChat("/spoff")
    lua_thread.create(function()
        wait(120)
        sampSendChat(string.format("/%s %d", commandName, id))
    end)

    SpectateQuickPanel.stop()
end

function SpectateQuickPanel.sendGoto()
    local id = SpectateQuickPanel.targetId
    if not id then return end
    SpectateQuickPanel.sendAfterSpOff("goto")
    LogManager.admin(string.format("Quick panel: /spoff + /goto %d", id))
end

function SpectateQuickPanel.sendGetHere()
    local id = SpectateQuickPanel.targetId
    if not id then return end
    SpectateQuickPanel.sendAfterSpOff("gethere")
    LogManager.admin(string.format("Quick panel: /spoff + /gethere %d", id))
end

function SpectateQuickPanel.sendGetCar()
    if SpectateQuickPanel.getCarBusy or SpectateQuickPanel.tpCarBusy then
        sampAddChatMessage("[SP] GETCAR: jarayon davom etmoqda...", 0xFF9933)
        return
    end

    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then
        sampAddChatMessage("[SP] GETCAR: target ID topilmadi.", 0xFF6666)
        return
    end

    if type(sampIsPlayerConnected) == "function" and not sampIsPlayerConnected(id) then
        sampAddChatMessage("[SP] GETCAR: target online emas.", 0xFF6666)
        return
    end

    if type(sampSendChat) ~= "function" or not (lua_thread and type(lua_thread.create) == "function") then
        sampAddChatMessage("[SP] GETCAR: chat/thread API topilmadi.", 0xFF6666)
        return
    end

    SpectateQuickPanel.getCarBusy = true
    lua_thread.create(function()
        local ok, err = pcall(function()
            local vehicleId = SpectateQuickPanel.resolveTargetVehicleIdForGetcar(id, 2100)
            if not vehicleId or vehicleId <= 0 then
                sampAddChatMessage("[SP] GETCAR: mashina ID topilmadi.", 0xFF6666)
                return
            end

            sampSendChat(string.format("/getcar %d", vehicleId))
            sampAddChatMessage(string.format("[SP] GETCAR: /getcar %d yuborildi.", vehicleId), 0x33FF66)
            LogManager.admin(string.format("Quick panel: /getcar %d (target #%d)", vehicleId, id))
        end)

        SpectateQuickPanel.getCarBusy = false
        if not ok then
            sampAddChatMessage("[SP] GETCAR xato: " .. tostring(err), 0xFF6666)
            LogManager.error("SP GETCAR failed: " .. tostring(err))
        end
    end)
end

function SpectateQuickPanel.toggleTpCarModePicker()
    if SpectateQuickPanel.tpCarBusy then
        sampAddChatMessage("[SP] TP CAR: jarayon davom etmoqda...", 0xFF9933)
        return
    end
    SpectateQuickPanel.showTpCarModePicker = not SpectateQuickPanel.showTpCarModePicker
end

function SpectateQuickPanel.sendTpCarRoadAsCar()
    SpectateQuickPanel.showTpCarModePicker = false
    SpectateQuickPanel.sendTpCarRoad("car")
end

function SpectateQuickPanel.sendTpCarRoadAsHere()
    SpectateQuickPanel.showTpCarModePicker = false
    SpectateQuickPanel.sendTpCarRoad("here")
end

function SpectateQuickPanel.sendAdminHelp()
    local id = SpectateQuickPanel.targetId
    if not id then return end
    sampSendChat(string.format("/a help %d", id))
    LogManager.admin(string.format("Quick panel: /a help %d", id))
end

function SpectateQuickPanel.sendSpawn()
    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then return end
    sampSendChat(string.format("/spawn %d", id))
    LogManager.admin(string.format("Quick panel: /spawn %d", id))
end

function SpectateQuickPanel.sendFreeze()
    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then return end
    sampSendChat(string.format("/freeze %d", id))
    LogManager.admin(string.format("Quick panel: /freeze %d", id))
end

function SpectateQuickPanel.sendUnfreeze()
    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then return end
    sampSendChat(string.format("/unfreeze %d", id))
    LogManager.admin(string.format("Quick panel: /unfreeze %d", id))
end

function SpectateQuickPanel.sendStats()
    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then return end
    sampSendChat(string.format(" %d", is))
    LogManager.admin(string.format("Quick panel:  %d", is))
end

function SpectateQuickPanel.sendWeap()
    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then return end
    sampSendChat(string.format("/weap %d", id))
    LogManager.admin(string.format("Quick panel: /weap %d", id))
end

function SpectateQuickPanel.sendGetInfo()
    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then return end
    sampSendChat(string.format("/getinfo %d", id))
    LogManager.admin(string.format("Quick panel: /getinfo %d", id))
end

function SpectateQuickPanel.sendPunishments()
    local playerId = tonumber(SpectateQuickPanel.targetId)
    if not playerId then
        sampAddChatMessage("[SP] JAZOLAR: target ID topilmadi.", 0xFF6666)
        return
    end

    local answerId = SpectateQuickPanel.resolveAnswerId()
    local nick = SpectateQuickPanel.targetNick or ""
    if ReportCatchManager.requestPunishmentsFor(answerId, playerId, nick, "spectate_panel") then
        LogManager.admin(string.format(
            "Quick panel: JAZOLAR check for target #%d (report #%s)",
            playerId, tostring(answerId or 0)))
    end
end

function SpectateQuickPanel.sendNavigator()
    local id = tonumber(SpectateQuickPanel.targetId)
    if not id then
        sampAddChatMessage("[SP] NAVIGATOR: target ID topilmadi.", 0xFF6666)
        return
    end

    if NavigatorManager.startForTarget(id, "spectate") then
        LogManager.admin(string.format("Quick panel: NAVIGATOR requested for #%d", id))
    end
end

function SpectateQuickPanel.getTargetPedAndVehicle(id)
    local playerId = tonumber(id)
    if not playerId then
        return nil, nil
    end

    local ped = nil
    if ReportCatchManager and type(ReportCatchManager.getPlayerPedHandle) == "function" then
        ped = ReportCatchManager.getPlayerPedHandle(playerId)
    end
    if not ped then
        return nil, nil
    end

    local vehicle = nil
    if type(isCharInAnyCar) == "function" then
        local okInCar, inCar = pcall(isCharInAnyCar, ped)
        if okInCar and inCar then
            if type(storeCarCharIsInNoSave) == "function" then
                local okCar, car = pcall(storeCarCharIsInNoSave, ped)
                if okCar then
                    vehicle = tonumber(car)
                end
            elseif type(storeCarCharIsIn) == "function" then
                local okCar, car = pcall(storeCarCharIsIn, ped)
                if okCar then
                    vehicle = tonumber(car)
                end
            end
        end
    end

    if vehicle and type(doesVehicleExist) == "function" then
        local okExists, exists = pcall(doesVehicleExist, vehicle)
        if okExists and not exists then
            vehicle = nil
        end
    end

    return ped, vehicle
end

function SpectateQuickPanel.getTargetCenterCoords(id)
    local ped, vehicle = SpectateQuickPanel.getTargetPedAndVehicle(id)
    if not ped then
        return nil
    end

    if vehicle and type(getCarCoordinates) == "function" then
        local okVeh, a, b, c = pcall(getCarCoordinates, vehicle)
        if okVeh then
            local vx, vy, vz = TeleportClickManager.extractCoords(a, b, c)
            if vx and vy and vz then
                return vx, vy, vz, true
            end
        end
    end

    if type(getCharCoordinates) == "function" then
        local okPed, a, b, c = pcall(getCharCoordinates, ped)
        if okPed then
            local px, py, pz = TeleportClickManager.extractCoords(a, b, c)
            if px and py and pz then
                return px, py, pz, false
            end
        end
    end

    return nil
end

function SpectateQuickPanel.findNearestRoadPoint(x, y, z)
    local cx = tonumber(x)
    local cy = tonumber(y)
    local cz = tonumber(z)
    if not cx or not cy or not cz then
        return nil
    end

    local function distance2D(ax, ay, bx, by)
        local dx = (ax or 0.0) - (bx or 0.0)
        local dy = (ay or 0.0) - (by or 0.0)
        return math.sqrt(dx * dx + dy * dy)
    end

    local function readWaterHeight(px, py, pz)
        if type(getWaterHeightAtCoords) ~= "function" then
            return nil
        end
        local ok, a, b, c = pcall(getWaterHeightAtCoords, px, py, pz)
        if not ok then
            ok, a, b, c = pcall(getWaterHeightAtCoords, px, py)
            if not ok then
                return nil
            end
        end

        local wx, wy, wz = TeleportClickManager.extractCoords(a, b, c)
        if wx and wy and wz then
            return wz
        end

        if type(a) == "boolean" then
            if a then
                return tonumber(b) or tonumber(c)
            end
            return nil
        end

        return tonumber(a) or tonumber(b) or tonumber(c)
    end

    local maxRadius = 4500.0
    local baseGroundAtTarget = TeleportClickManager.getGroundZ(cx, cy, cz + 80.0) or
                               TeleportClickManager.getGroundZ(cx, cy, cz + 220.0) or cz
    local waterAtTarget = readWaterHeight(cx, cy, cz + 1.0)
    local likelyTrappedLow = false
    if baseGroundAtTarget and (baseGroundAtTarget - cz) >= 4.0 then
        likelyTrappedLow = true
    end
    if waterAtTarget and cz <= (waterAtTarget + 1.8) then
        likelyTrappedLow = true
    end

    local bestFlat = nil
    local bestFlatScore = nil
    local bestFlatDist = nil
    local bestAny = nil
    local bestAnyScore = nil
    local bestElevated = nil
    local bestElevatedScore = nil

    local function evaluateCandidate(rx, ry, rz, isRoadNode)
        local tx = tonumber(rx)
        local ty = tonumber(ry)
        local tz = tonumber(rz)
        if not tx or not ty or not tz then
            return
        end

        local gz = TeleportClickManager.getGroundZ(tx, ty, tz + 60.0) or
                   TeleportClickManager.getGroundZ(tx, ty, cz + 60.0) or
                   TeleportClickManager.getGroundZ(tx, ty, tz) or
                   tz

        local d2 = distance2D(cx, cy, tx, ty)
        if d2 > maxRadius then
            return
        end

        local z1 = TeleportClickManager.getGroundZ(tx + 2.0, ty, gz + 10.0) or gz
        local z2 = TeleportClickManager.getGroundZ(tx - 2.0, ty, gz + 10.0) or gz
        local z3 = TeleportClickManager.getGroundZ(tx, ty + 2.0, gz + 10.0) or gz
        local z4 = TeleportClickManager.getGroundZ(tx, ty - 2.0, gz + 10.0) or gz
        local maxDiff = math.max(
            math.abs(z1 - gz),
            math.abs(z2 - gz),
            math.abs(z3 - gz),
            math.abs(z4 - gz)
        )

        local zDiff = math.abs((gz or 0.0) - cz)
        local score = d2 + (zDiff * 0.22) + (maxDiff * 26.0) + (isRoadNode and 0.0 or 35.0)

        if likelyTrappedLow then
            if gz > (cz + 3.0) then
                -- If target is under bridge / in water, prefer upper road level strongly.
                score = score - math.min(45.0, (gz - cz) * 1.45)
            else
                score = score + 24.0
            end
        end

        if not bestAnyScore or score < bestAnyScore then
            bestAny = { x = tx, y = ty, z = gz }
            bestAnyScore = score
        end

        if likelyTrappedLow and gz > (cz + 3.0) then
            if not bestElevatedScore or score < bestElevatedScore then
                bestElevated = { x = tx, y = ty, z = gz }
                bestElevatedScore = score
            end
        end

        if maxDiff <= 1.20 then
            if not bestFlatScore or score < bestFlatScore then
                bestFlat = { x = tx, y = ty, z = gz }
                bestFlatScore = score
                bestFlatDist = d2
            end
        end
    end

    local nodeProviders = {}
    if type(getClosestCarNodeWithHeading) == "function" then
        table.insert(nodeProviders, function(px, py, pz)
            return getClosestCarNodeWithHeading(px, py, pz)
        end)
    end
    if type(getClosestCarNode) == "function" then
        table.insert(nodeProviders, function(px, py, pz)
            return getClosestCarNode(px, py, pz)
        end)
    end

    local function probeRoadNode(px, py, pz)
        local seed = tonumber(pz) or cz
        local seedHeights = {
            seed,
            cz,
            cz + 80.0,
            cz + 160.0,
            cz + 260.0,
            seed + 120.0
        }
        for _, provider in ipairs(nodeProviders) do
            local used = {}
            for _, height in ipairs(seedHeights) do
                local h = tonumber(height)
                if h and not used[h] then
                    used[h] = true
                    local ok, a, b, c = pcall(provider, px, py, h)
                    if ok then
                        local rx, ry, rz = TeleportClickManager.extractCoords(a, b, c)
                        if rx and ry and rz then
                            evaluateCandidate(rx, ry, rz, true)
                        end
                    end
                end
            end
        end
    end

    -- Direct nearest road node from target point.
    probeRoadNode(cx, cy, cz)

    -- If needed, widen search to cover any place on map and pick nearest flat road center.
    local needExpandedSearch = (not bestFlat) or (likelyTrappedLow and (not bestElevated))
    if needExpandedSearch then
        local radii = { 0, 15, 30, 50, 80, 120, 170, 240, 330, 450, 620, 850, 1150, 1550, 2050, 2700, 3500, 4500 }
        for _, radius in ipairs(radii) do
            local angleStep = 20
            if radius <= 120 then
                angleStep = 12
            elseif radius >= 2050 then
                angleStep = 28
            end

            for angle = 0, 359, angleStep do
                local rad = math.rad(angle)
                local sx = cx + math.cos(rad) * radius
                local sy = cy + math.sin(rad) * radius
                local sz = TeleportClickManager.getGroundZ(sx, sy, cz + 80.0) or cz

                probeRoadNode(sx, sy, sz)
                evaluateCandidate(sx, sy, sz, false)
            end

            if likelyTrappedLow then
                if bestElevated then
                    break
                end
            elseif bestFlat and bestFlatDist and bestFlatDist <= (radius + 35.0) then
                break
            end
        end
    end

    local picked = nil
    if likelyTrappedLow and bestElevated then
        picked = bestElevated
    else
        picked = bestFlat or bestAny
    end
    if picked then
        return picked.x, picked.y, picked.z
    end
    return nil
end

function SpectateQuickPanel.isLocalNearPoint(x, y, z, radius, zTolerance)
    local ped = AdminModesManager.getLocalPed()
    if not ped or type(getCharCoordinates) ~= "function" then
        return false
    end

    local okPos, a, b, c = pcall(getCharCoordinates, ped)
    if not okPos then
        return false
    end

    local px, py, pz = TeleportClickManager.extractCoords(a, b, c)
    if not px or not py or not pz then
        return false
    end

    local dx = (tonumber(x) or 0.0) - px
    local dy = (tonumber(y) or 0.0) - py
    local dz = (tonumber(z) or 0.0) - pz
    local rr = tonumber(radius) or 6.0
    local zz = tonumber(zTolerance) or math.max(14.0, rr * 2.5)
    local dist2 = dx * dx + dy * dy
    if dist2 <= (rr * rr) and math.abs(dz) <= zz then
        return true
    end

    return (dist2 + dz * dz) <= (rr * rr)
end

function SpectateQuickPanel.resolveTargetVehicleIdForGetcar(targetId, timeoutMs)
    local id = tonumber(targetId)
    if not id or id <= 0 then
        return nil
    end

    if not TeleportClickManager or type(TeleportClickManager.resolveSpectateTargetVehicleId) ~= "function" then
        return nil
    end

    -- Fast path: streamed target vehicle handle -> SAMP vehicle id.
    local directId = TeleportClickManager.resolveSpectateTargetVehicleId(id)
    if directId and directId > 0 then
        return directId
    end

    if type(sampSendChat) ~= "function" then
        return nil
    end

    local nowMs = TeleportClickManager.getNowMs()
    local waitLimit = math.max(600, math.min(3500, tonumber(timeoutMs) or 1800))
    local deadline = nowMs + waitLimit

    TeleportClickManager.dlObservedVehicleId = nil
    TeleportClickManager.dlObservedAtMs = nowMs
    sampSendChat("/dl")

    while TeleportClickManager.getNowMs() <= deadline do
        wait(90)

        local retryId = TeleportClickManager.resolveSpectateTargetVehicleId(id)
        if retryId and retryId > 0 then
            return retryId
        end

        local observedId = tonumber(TeleportClickManager.dlObservedVehicleId)
        local observedAt = tonumber(TeleportClickManager.dlObservedAtMs) or 0
        if observedId and observedId > 0 and observedAt >= nowMs then
            return observedId
        end
    end

    return nil
end

function SpectateQuickPanel.sendTpCarRoad(mode, targetIdOverride)
    if SpectateQuickPanel.tpCarBusy then
        sampAddChatMessage("[SP] TP CAR: jarayon davom etmoqda...", 0xFF9933)
        return false
    end

    local tpMode = tostring(mode or "auto"):lower()
    if tpMode ~= "auto" and tpMode ~= "car" and tpMode ~= "here" then
        tpMode = "auto"
    end
    local forceHereMode = (tpMode == "here")

    local id = tonumber(targetIdOverride) or tonumber(SpectateQuickPanel.targetId)
    if not id then
        sampAddChatMessage("[SP] TP CAR: target ID topilmadi.", 0xFF6666)
        return false
    end

    if type(sampIsPlayerConnected) == "function" and not sampIsPlayerConnected(id) then
        sampAddChatMessage("[SP] TP CAR: target online emas.", 0xFF6666)
        return false
    end

    if type(sampSendChat) ~= "function" or not (lua_thread and type(lua_thread.create) == "function") then
        sampAddChatMessage("[SP] TP CAR: chat/thread API topilmadi.", 0xFF6666)
        return false
    end

    local tx, ty, tz, targetInVehicle = SpectateQuickPanel.getTargetCenterCoords(id)
    if not tx or not ty or not tz then
        sampAddChatMessage("[SP] TP CAR: target koordinatasi topilmadi.", 0xFF6666)
        return false
    end

    local rx, ry, rz = SpectateQuickPanel.findNearestRoadPoint(tx, ty, tz)
    if not rx or not ry or not rz then
        sampAddChatMessage("[SP] TP CAR: yaqin tekis yo'l topilmadi (xavfsizlik uchun bekor).", 0xFF6666)
        return false
    end

    local targetVehicleId = nil
    if targetInVehicle and (not forceHereMode) then
        targetVehicleId = SpectateQuickPanel.resolveTargetVehicleIdForGetcar(id, 2100)
        if not targetVehicleId then
            sampAddChatMessage("[SP] TP CAR: mashina ID topilmadi, /getcar bekor qilindi.", 0xFF6666)
            return false
        end
    end

    local hasLocalPos, oldX, oldY, oldZ = UtilityManager.getPlayerCoords()
    SpectateQuickPanel.tpCarBusy = true

    lua_thread.create(function()
        local ok, err = pcall(function()
            sampSendChat("/spoff")
            SpectateQuickPanel.stop()
            wait(160)

            -- Move local admin to computed road center only as a transport anchor.
            -- Use multiple Z offsets and looser horizontal check to avoid false failure
            -- on bridges / uneven roads (e.g. Yujniy multi-level segments).
            local moved = false
            local zOffsets = { 0.9, 2.4, 4.2, 1.1, 3.1, 5.0, 1.3, 2.8, 3.8, 1.0, 2.0, 4.8 }
            for i = 1, #zOffsets do
                TeleportClickManager.teleportLocalWithVehicle(rx, ry, rz + zOffsets[i])
                wait(150)
                if SpectateQuickPanel.isLocalNearPoint(rx, ry, rz, 14.0, 85.0) then
                    moved = true
                    break
                end
            end

            if (not moved) and SpectateQuickPanel.isLocalNearPoint(rx, ry, rz, 22.0, 140.0) then
                moved = true
            end

            if not moved then
                sampAddChatMessage("[SP] TP CAR: yo'l nuqtasiga chiqib bo'lmadi, amaliyot bekor.", 0xFF6666)
                return
            end

            -- Final snap to road center level before moving target.
            local anchorGroundZ = TeleportClickManager.getGroundZ(rx, ry, rz + 90.0) or rz
            TeleportClickManager.teleportLocalWithVehicle(rx, ry, anchorGroundZ + 0.9)
            wait(170)

            local usedCommand = "gethere"
            if targetInVehicle then
                sampSendChat(string.format("/flip %d", id))
                wait(170)
                sampSendChat(string.format("/ %d", id))
                wait(170)
                if forceHereMode then
                    sampSendChat(string.format("/gethere %d", id))
                    usedCommand = "gethere"
                    wait(240)
                else
                    sampSendChat(string.format("/getcar %d", targetVehicleId))
                    usedCommand = "getcar"
                    wait(260)
                end
                sampSendChat(string.format(" %d", id))
                wait(150)
            else
                sampSendChat(string.format("/gethere %d", id))
                wait(220)
            end

            if hasLocalPos then
                TeleportClickManager.teleportLocalWithVehicle(oldX, oldY, oldZ)
                wait(180)
            end

            sampSendChat(string.format("/sp %d", id))
            sampAddChatMessage("[SP] TP CAR: target yo'lga ko'chirildi.", 0x33FF66)
            LogManager.admin(string.format(
                "SP TP CAR: target #%d -> road (%.1f, %.1f, %.1f), mode=%s, cmd=%s, inVehicle=%s, vehicleId=%s",
                id, rx, ry, rz, tpMode, usedCommand, tostring(targetInVehicle), tostring(targetVehicleId)))
        end)

        SpectateQuickPanel.tpCarBusy = false
        if not ok then
            sampAddChatMessage("[SP] TP CAR xato: " .. tostring(err), 0xFF6666)
            LogManager.error("SP TP CAR failed: " .. tostring(err))
        end
    end)

    return true
end

function SpectateQuickPanel.sendReportDecision(decisionText, decisionTag)
    local answerId = tonumber(SpectateQuickPanel.reportAnswerId)
    if not answerId then return end
    sampSendChat(string.format("/ans %d %s", answerId, decisionText))
    SpectateQuickPanel.clearReportReviewMode()
    LogManager.report(string.format("Report review decision (%s) sent for #%d", decisionTag, answerId))
end

function SpectateQuickPanel.sendReportPlayerGuilty()
    SpectateQuickPanel.sendReportDecision("Assalomu alaykum, o'yinchi jazolanadi, maroqli o'yin", "guilty")
end

function SpectateQuickPanel.sendReportPlayerNotGuilty()
    SpectateQuickPanel.sendReportDecision("Assalomu alaykum, o'yinchi aybsiz", "not_guilty")
end

function SpectateQuickPanel.getActionButtons()
    local actions = {
        { id = "spfixcar", label = "Spoff", onClick = SpectateQuickPanel.sendSpoff },
        { id = "spflip", label = "Flip", onClick = SpectateQuickPanel.sendFlip },
        { id = "sptpcar", label = "TP CAR", onClick = SpectateQuickPanel.toggleTpCarModePicker },
        { id = "spgetcar", label = "GetCar", onClick = SpectateQuickPanel.sendGetCar },
        { id = "spspawn", label = "Spawn", onClick = SpectateQuickPanel.sendSpawn },
        { id = "spfreeze", label = "Freeze", onClick = SpectateQuickPanel.sendFreeze },
        { id = "spunfreeze", label = "Unfreeze", onClick = SpectateQuickPanel.sendUnfreeze },
        { id = "spstats", label = "Stats", onClick = SpectateQuickPanel.sendStats },
        { id = "spweap", label = "Weap", onClick = SpectateQuickPanel.sendWeap },
        { id = "spgetinfo", label = "GetInfo", onClick = SpectateQuickPanel.sendGetInfo },
        { id = "spjazolar", label = "Jazolar", onClick = SpectateQuickPanel.sendPunishments },
        { id = "spnavigator", label = "Navigator", onClick = SpectateQuickPanel.sendNavigator },
        { id = "spgoto", label = "Goto", onClick = SpectateQuickPanel.sendGoto },
        { id = "spgethere", label = "GetHere", onClick = SpectateQuickPanel.sendGetHere },
        { id = "spslap", label = "Slap", onClick = SpectateQuickPanel.sendSlap },
        { id = "spanswers", label = "Javoblar", onClick = SpectateQuickPanel.toggleTemplatePicker },
        { id = "spadmin", label = "ADMIN", onClick = SpectateQuickPanel.sendAdminHelp }
    }

    if SpectateQuickPanel.reportReviewMode and SpectateQuickPanel.reportAnswerId then
        table.insert(actions, { id = "spreportguilty", label = "Aybdor", onClick = SpectateQuickPanel.sendReportPlayerGuilty })
        table.insert(actions, { id = "spreportnotguilty", label = "Aybsiz", onClick = SpectateQuickPanel.sendReportPlayerNotGuilty })
    end

    return actions
end

function SpectateQuickPanel.renderModerationPanel()
    if not SpectateQuickPanel.active or not SpectateQuickPanel.targetId then
        return
    end

    SpectateQuickPanel.ensureFormState()

    local screenX, screenY = getScreenResolution()
    screenX = screenX or 1920
    screenY = screenY or 1080

    local mode = SpectateQuickPanel.moderationMode or "none"
    local minPanelWidth = 320
    local minPanelHeight = 142
    if mode == "jail" or mode == "ban" then
        minPanelHeight = 250
    elseif mode == "warn" then
        minPanelHeight = 214
    elseif mode == "mute" or mode == "rmute" then
        minPanelHeight = 250
    elseif mode == "runmute" or mode == "unmute" then
        minPanelHeight = 214
    end

    local uiState = SpectateQuickPanel.ui
    uiState.moderationPos = uiState.moderationPos or { x = 14, y = 0 }
    uiState.moderationSize = uiState.moderationSize or { width = 360, height = minPanelHeight }

    local panelWidth = math.max(minPanelWidth, tonumber(uiState.moderationSize.width) or minPanelWidth)
    local panelHeight = math.max(minPanelHeight, tonumber(uiState.moderationSize.height) or minPanelHeight)

    local posX = tonumber(uiState.moderationPos.x) or 14
    local posY = tonumber(uiState.moderationPos.y) or 0
    if posY <= 0 then
        posY = math.max(10, screenY - panelHeight - SpectateQuickPanel.ui.bottomOffset)
    end

    local maxX = math.max(10, screenX - panelWidth - 10)
    local maxY = math.max(10, screenY - panelHeight - 10)
    posX = UtilityManager.clamp(posX, 10, maxX)
    posY = UtilityManager.clamp(posY, 10, maxY)

    if not uiState.moderationInitialized then
        imgui.SetNextWindowPos(imgui.ImVec2(posX, posY), imgui.Cond.Always)
        imgui.SetNextWindowSize(imgui.ImVec2(panelWidth, panelHeight), imgui.Cond.Always)
        uiState.moderationInitialized = true
    end
    if imgui.SetNextWindowSizeConstraints then
        imgui.SetNextWindowSizeConstraints(
            imgui.ImVec2(minPanelWidth, minPanelHeight),
            imgui.ImVec2(math.max(minPanelWidth, screenX - 10), math.max(minPanelHeight, screenY - 10))
        )
    end

    local flags = imgui.WindowFlags.NoScrollbar +
                  imgui.WindowFlags.NoCollapse

    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.07, 0.08, 0.11, 0.88))
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.86, 0.42, 0.16, 0.95))
    local styleVarPushed = 0
    if imgui.PushStyleVar and imgui.StyleVar then
        imgui.PushStyleVar(imgui.StyleVar.WindowRounding, 10)
        styleVarPushed = 1
    end

    if imgui.Begin("SP MOD##SpectateModerationPanel", nil, flags) then
        local currentPos = imgui.GetWindowPos()
        local currentSize = imgui.GetWindowSize()
        uiState.moderationPos.x = currentPos.x
        uiState.moderationPos.y = currentPos.y
        uiState.moderationSize.width = currentSize.x
        uiState.moderationSize.height = math.max(minPanelHeight, currentSize.y)
        SpectateQuickPanel.storeUiToSettings()

        imgui.TextColored(COLORS.WARNING or imgui.ImVec4(0.95, 0.77, 0.06, 1.0),
            string.format("SPEC MOD: %s", SpectateQuickPanel.getTargetDisplay()))
        imgui.Separator()

        local contentWidth = imgui.GetContentRegionAvail().x
        local colGap = 8
        local colWidth = math.floor((contentWidth - colGap) / 2)
        colWidth = math.max(120, colWidth)

        if imgui.Button("DM##sp_mod_dm", imgui.ImVec2(colWidth, 30)) then
            SpectateQuickPanel.openModerationMode("jail")
        end
        imgui.SameLine(0, colGap)
        if imgui.Button("BAN##sp_mod_ban", imgui.ImVec2(colWidth, 30)) then
            SpectateQuickPanel.openModerationMode("ban")
        end

        if imgui.Button("WARN##sp_mod_warn", imgui.ImVec2(colWidth, 30)) then
            SpectateQuickPanel.openModerationMode("warn")
        end
        imgui.SameLine(0, colGap)
        if imgui.Button("MUTE##sp_mod_mute", imgui.ImVec2(colWidth, 30)) then
            SpectateQuickPanel.openModerationMode("mute")
        end

        if imgui.Button("RMUTE##sp_mod_rmute", imgui.ImVec2(colWidth, 30)) then
            SpectateQuickPanel.openModerationMode("rmute")
        end
        imgui.SameLine(0, colGap)
        if imgui.Button("RUNMUTE##sp_mod_runmute", imgui.ImVec2(colWidth, 30)) then
            SpectateQuickPanel.openModerationMode("runmute")
        end

        if imgui.Button("UNMUTE##sp_mod_unmute", imgui.ImVec2(colWidth, 30)) then
            SpectateQuickPanel.openModerationMode("unmute")
        end

        if imgui.Button(u8"Yopish##sp_mod_close", imgui.ImVec2(-1, 30)) then
            SpectateQuickPanel.openModerationMode("none")
        end

        imgui.Separator()

        if mode == "jail" then
            imgui.Text(u8"DM: /jail id vaqt sabab")
            imgui.InputInt(u8"Vaqt (min)##sp_jail_time", SpectateQuickPanel.form.jailMinutes)
            imgui.InputText(u8"Sabab##sp_jail_reason", SpectateQuickPanel.form.jailReason, 128)
            if imgui.Button(u8"DM Qo'llash##sp_jail_apply", imgui.ImVec2(-1, 32)) then
                SpectateQuickPanel.applyJailToTarget()
            end
        elseif mode == "ban" then
            imgui.Text(u8"BAN: /ban id kun sabab")
            imgui.InputInt(u8"Kun##sp_ban_days", SpectateQuickPanel.form.banDays)
            imgui.InputText(u8"Sabab##sp_ban_reason", SpectateQuickPanel.form.banReason, 128)
            if imgui.Button(u8"BAN Qo'llash##sp_ban_apply", imgui.ImVec2(-1, 32)) then
                SpectateQuickPanel.applyBanToTarget()
            end
        elseif mode == "warn" then
            imgui.Text(u8"WARN: /warn id sabab")
            imgui.InputText(u8"Sabab##sp_warn_reason", SpectateQuickPanel.form.warnReason, 128)
            if imgui.Button(u8"WARN Qo'llash##sp_warn_apply", imgui.ImVec2(-1, 32)) then
                SpectateQuickPanel.applyWarnToTarget()
            end
        elseif mode == "mute" then
            imgui.Text(u8"MUTE: /mute id vaqt sabab")
            imgui.InputInt(u8"Vaqt (min)##sp_mute_time", SpectateQuickPanel.form.muteMinutes)
            imgui.InputText(u8"Sabab##sp_mute_reason", SpectateQuickPanel.form.muteReason, 128)
            if imgui.Button(u8"MUTE Qo'llash##sp_mute_apply", imgui.ImVec2(-1, 32)) then
                SpectateQuickPanel.applyMuteToTarget()
            end
        elseif mode == "rmute" then
            imgui.Text(u8"RMUTE: /rmute id vaqt sabab")
            imgui.InputInt(u8"Vaqt (min)##sp_rmute_time", SpectateQuickPanel.form.rmuteMinutes)
            imgui.InputText(u8"Sabab##sp_rmute_reason", SpectateQuickPanel.form.rmuteReason, 128)
            if imgui.Button(u8"RMUTE Qo'llash##sp_rmute_apply", imgui.ImVec2(-1, 32)) then
                SpectateQuickPanel.applyRMuteToTarget()
            end
        elseif mode == "runmute" then
            imgui.Text(u8"RUNMUTE: /runmute id sabab")
            imgui.InputText(u8"Sabab##sp_runmute_reason", SpectateQuickPanel.form.runmuteReason, 128)
            if imgui.Button(u8"RUNMUTE Qo'llash##sp_runmute_apply", imgui.ImVec2(-1, 32)) then
                SpectateQuickPanel.applyRunmuteToTarget()
            end
        elseif mode == "unmute" then
            imgui.Text(u8"UNMUTE: /unmute id sabab")
            imgui.InputText(u8"Sabab##sp_unmute_reason", SpectateQuickPanel.form.unmuteReason, 128)
            if imgui.Button(u8"UNMUTE Qo'llash##sp_unmute_apply", imgui.ImVec2(-1, 32)) then
                SpectateQuickPanel.applyUnmuteToTarget()
            end
        else
            imgui.TextDisabled(u8"Chapdagi tugmalardan birini tanlang.")
        end
    end
    imgui.End()

    if styleVarPushed > 0 and imgui.PopStyleVar then
        imgui.PopStyleVar(styleVarPushed)
    end
    imgui.PopStyleColor(2)
end

function SpectateQuickPanel.render()
    if not SpectateQuickPanel.active or not SpectateQuickPanel.targetId then return end

    local actions = SpectateQuickPanel.getActionButtons()
    local totalButtons = #actions
    if totalButtons == 0 then return end
    local templates = SpectateQuickPanel.getSharedReplyTemplates()
    local templateCount = #templates

    local screenX, screenY = getScreenResolution()
    screenX = screenX or 1920
    screenY = screenY or 1080

    local maxPerRow = 10
    local baseColumns = math.min(maxPerRow, totalButtons)
    local baseRows = math.max(1, math.ceil(totalButtons / maxPerRow))
    local baseButtonWidth = 88
    local baseButtonHeight = 28
    local baseHorizontalGap = 6
    local baseVerticalGap = 6
    local sidePadding = 14
    local topPadding = 12
    local bottomPadding = 12
    local headerBlock = 24

    local baseWidth = sidePadding * 2 + (baseColumns * baseButtonWidth) + ((baseColumns - 1) * baseHorizontalGap)
    local baseTemplateColumns = 4
    local baseTemplateRows = math.max(1, math.ceil(math.max(1, templateCount) / baseTemplateColumns))
    local baseTemplateHeight = 8 + 18 + (baseTemplateRows * baseButtonHeight) + ((baseTemplateRows - 1) * baseVerticalGap) + 8
    local baseHeight = topPadding + headerBlock + (baseRows * baseButtonHeight) + ((baseRows - 1) * baseVerticalGap) + bottomPadding
    if SpectateQuickPanel.showTpCarModePicker then
        baseHeight = baseHeight + (baseButtonHeight + 40)
    end
    if SpectateQuickPanel.showTemplatePicker then
        baseHeight = baseHeight + baseTemplateHeight
    end

    local uiState = SpectateQuickPanel.ui
    uiState.quickPos = uiState.quickPos or { x = 0, y = 0 }
    uiState.quickSize = uiState.quickSize or { width = baseWidth, height = baseHeight }

    local minWidth = 420
    local minHeight = 96
    local maxWidth = math.max(minWidth, screenX - 10)
    local maxHeight = math.max(minHeight, screenY - 10)

    local defaultPosX = math.floor((screenX - baseWidth) / 2)
    local defaultPosY = math.max(10, screenY - baseHeight - uiState.bottomOffset)
    local savedW = tonumber(uiState.quickSize.width)
    local savedH = tonumber(uiState.quickSize.height)
    local defaultSizeW = UtilityManager.clamp(savedW or baseWidth, minWidth, maxWidth)
    local defaultSizeH = UtilityManager.clamp(savedH or baseHeight, minHeight, maxHeight)

    if not uiState.quickInitialized then
        local startX = tonumber(uiState.quickPos.x)
        local startY = tonumber(uiState.quickPos.y)
        if not startX or startX <= 0 then
            startX = defaultPosX
        end
        if not startY or startY <= 0 then
            startY = defaultPosY
        end
        startX = UtilityManager.clamp(startX, 10, math.max(10, screenX - defaultSizeW - 10))
        startY = UtilityManager.clamp(startY, 10, math.max(10, screenY - defaultSizeH - 10))

        imgui.SetNextWindowPos(imgui.ImVec2(startX, startY), imgui.Cond.Always)
        imgui.SetNextWindowSize(imgui.ImVec2(defaultSizeW, defaultSizeH), imgui.Cond.Always)
        uiState.quickInitialized = true
    end

    if imgui.SetNextWindowSizeConstraints then
        imgui.SetNextWindowSizeConstraints(
            imgui.ImVec2(minWidth, minHeight),
            imgui.ImVec2(maxWidth, maxHeight)
        )
    end

    local flags = imgui.WindowFlags.NoCollapse +
                  imgui.WindowFlags.NoSavedSettings

    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.06, 0.07, 0.09, 0.78))
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.23, 0.61, 0.35, 0.95))
    local styleVarPushed = 0
    if imgui.PushStyleVar and imgui.StyleVar then
        imgui.PushStyleVar(imgui.StyleVar.WindowRounding, 10)
        styleVarPushed = 1
    end

    if imgui.Begin("SP QUICK PANEL##SpectateQuickPanel", nil, flags) then
        local windowPos = imgui.GetWindowPos()
        local windowSize = imgui.GetWindowSize()
        if windowPos then
            uiState.quickPos.x = windowPos.x
            uiState.quickPos.y = windowPos.y
        end
        if windowSize then
            uiState.quickSize.width = windowSize.x
            uiState.quickSize.height = windowSize.y
            SpectateQuickPanel.ui.width = windowSize.x
            SpectateQuickPanel.ui.height = windowSize.y
        end
        SpectateQuickPanel.storeUiToSettings()

        local widthScale = (windowSize and windowSize.x and baseWidth > 0) and (windowSize.x / baseWidth) or 1.0
        local heightScale = (windowSize and windowSize.y and baseHeight > 0) and (windowSize.y / baseHeight) or 1.0
        local panelScale = UtilityManager.clamp((widthScale + heightScale) * 0.5, 0.70, 1.80)

        local buttonHeight = math.max(20, math.floor(baseButtonHeight * panelScale))
        local horizontalGap = math.max(3, math.floor(baseHorizontalGap * panelScale))
        local verticalGap = math.max(3, math.floor(baseVerticalGap * panelScale))
        local contentWidth = math.max(140, imgui.GetContentRegionAvail().x)
        local minButtonWidth = math.max(48, math.floor(58 * panelScale))
        local buttonsPerRow = math.max(1, math.floor((contentWidth + horizontalGap) / (minButtonWidth + horizontalGap)))
        buttonsPerRow = math.min(maxPerRow, buttonsPerRow, totalButtons)
        local buttonWidth = math.max(42, math.floor((contentWidth - ((buttonsPerRow - 1) * horizontalGap)) / buttonsPerRow))

        imgui.TextColored(COLORS.INFO or imgui.ImVec4(0.20, 0.60, 0.86, 1.0),
            string.format("SPEC TARGET: %s", SpectateQuickPanel.getTargetDisplay()))
        imgui.SameLine()
        imgui.TextDisabled("RMB: cursor on/off")

        for i, action in ipairs(actions) do
            if imgui.Button(string.format("%s##%s", action.label, action.id), imgui.ImVec2(buttonWidth, buttonHeight)) then
                action.onClick()
            end

            local isLastInRow = (i % buttonsPerRow == 0) or (i == totalButtons)
            if not isLastInRow then
                imgui.SameLine(0, horizontalGap)
            end
        end

        if SpectateQuickPanel.showTpCarModePicker then
            imgui.Separator()
            imgui.TextColored(COLORS.SECONDARY or imgui.ImVec4(0.20, 0.60, 0.86, 1.0), "TP CAR rejim tanlang:")
            contentWidth = math.max(140, imgui.GetContentRegionAvail().x)
            local pickerButtonWidth = math.max(70, math.floor((contentWidth - (horizontalGap * 2)) / 3))

            if imgui.Button("CAR##sptpcar_car", imgui.ImVec2(pickerButtonWidth, buttonHeight)) then
                SpectateQuickPanel.sendTpCarRoadAsCar()
            end
            imgui.SameLine(0, horizontalGap)
            if imgui.Button("HERE##sptpcar_here", imgui.ImVec2(pickerButtonWidth, buttonHeight)) then
                SpectateQuickPanel.sendTpCarRoadAsHere()
            end
            imgui.SameLine(0, horizontalGap)
            if imgui.Button("Bekor##sptpcar_cancel", imgui.ImVec2(pickerButtonWidth, buttonHeight)) then
                SpectateQuickPanel.showTpCarModePicker = false
            end
        end

        if SpectateQuickPanel.showTemplatePicker then
            imgui.Separator()

            contentWidth = math.max(140, imgui.GetContentRegionAvail().x)
            local templateColumns = math.max(1, math.floor((contentWidth + horizontalGap) / (math.max(110, math.floor(120 * panelScale)) + horizontalGap)))
            templateColumns = math.min(4, templateColumns)
            local templateButtonWidth = math.max(86, math.floor((contentWidth - ((templateColumns - 1) * horizontalGap)) / templateColumns))

            local templateTargetId = SpectateQuickPanel.resolveTemplateTargetId()
            if templateTargetId then
                imgui.TextColored(COLORS.SECONDARY or imgui.ImVec4(0.20, 0.60, 0.86, 1.0),
                    string.format("Javoblar: player #%d", templateTargetId))
            else
                imgui.TextColored(COLORS.WARNING or imgui.ImVec4(0.95, 0.77, 0.06, 1.0),
                    u8"Javoblar: player ID topilmadi")
            end

            if templateCount == 0 then
                imgui.TextDisabled(u8"Shablonlar topilmadi")
            else
                for i, template in ipairs(templates) do
                    local templateId = tonumber(template.id) or i
                    local shortcut = UtilityManager.toUtf8(template.shortcut or "")
                    if shortcut == "" then
                        local shortText = UtilityManager.toUtf8(template.text or "")
                        if #shortText > 22 then
                            shortText = shortText:sub(1, 22) .. "..."
                        end
                        shortcut = shortText
                    end

                    local btnLabel = string.format("[%d] %s##sptpl%d", templateId, shortcut, templateId)
                    if imgui.Button(btnLabel, imgui.ImVec2(templateButtonWidth, buttonHeight)) then
                        SpectateQuickPanel.sendSharedTemplateReply(templateId)
                    end

                    if imgui.IsItemHovered() then
                        imgui.BeginTooltip()
                        imgui.Text(UtilityManager.toUtf8(template.text or ""))
                        imgui.EndTooltip()
                    end

                    local isLastTemplateInRow = (i % templateColumns == 0) or (i == templateCount)
                    if not isLastTemplateInRow then
                        imgui.SameLine(0, horizontalGap)
                    end
                end
            end
        end
    end
    imgui.End()

    if styleVarPushed > 0 and imgui.PopStyleVar then
        imgui.PopStyleVar(styleVarPushed)
    end
    imgui.PopStyleColor(2)

    SpectateQuickPanel.renderModerationPanel()
end

-- ============================================
-- PLAYER MANAGER
-- ============================================
local PlayerManager = {
    players = {},
    warns = {},
    mutes = {},
    bans = {},
    onlineList = {}
}

function PlayerManager.initialize()
    LogManager.system("Player manager initialized")
end

function PlayerManager.kick(playerId, reason)
    sampSendChat(string.format("/kick %d %s", playerId, reason or "Admin tomonidan"))
    LogManager.admin(string.format("Kicked player %d: %s", playerId, reason or "No reason"))
end

function PlayerManager.ban(playerId, reason, duration)
    if duration then
        sampSendChat(string.format("/tempban %d %d %s", playerId, duration, reason or ""))
        LogManager.admin(string.format("TempBanned player %d for %d hours: %s", playerId, duration, reason or "No reason"))
    else
        sampSendChat(string.format("/ban %d %s", playerId, reason or ""))
        LogManager.admin(string.format("Banned player %d: %s", playerId, reason or "No reason"))
    end
end

function PlayerManager.mute(playerId, duration, reason)
    sampSendChat(string.format("/mute %d %d %s", playerId, duration, reason or ""))
    LogManager.admin(string.format("Muted player %d for %d min: %s", playerId, duration, reason or "No reason"))
end

function PlayerManager.unmute(playerId)
    sampSendChat(string.format("/unmute %d", playerId))
    LogManager.admin(string.format("Unmuted player %d", playerId))
end

function PlayerManager.jail(playerId, duration, reason)
    sampSendChat(string.format("/jail %d %d %s", playerId, duration, reason or ""))
    LogManager.admin(string.format("Jailed player %d for %d min: %s", playerId, duration, reason or "No reason"))
end

function PlayerManager.unjail(playerId)
    sampSendChat(string.format("/unjail %d", playerId))
    LogManager.admin(string.format("Unjailed player %d", playerId))
end

function PlayerManager.warn(playerId, reason)
    sampSendChat(string.format("/warn %d %s", playerId, reason or ""))
    LogManager.admin(string.format("Warned player %d: %s", playerId, reason or "No reason"))
end

function PlayerManager.unwarn(playerId)
    sampSendChat(string.format("/unwarn %d", playerId))
    LogManager.admin(string.format("Unwarned player %d", playerId))
end

function PlayerManager.clearWarns(playerId)
    LogManager.admin(string.format("Cleared warns for player %d", playerId))
end

function PlayerManager.setHP(playerId, hp)
    sampSendChat(string.format("/sethp %d %d", playerId, hp))
end

function PlayerManager.setArmor(playerId, armor)
    sampSendChat(string.format("/setarmor %d %d", playerId, armor))
end

function PlayerManager.giveMoney(playerId, amount)
    sampSendChat(string.format("/givemoney %d %d", playerId, amount))
    LogManager.admin(string.format("Gave $%d to player %d", amount, playerId))
end

function PlayerManager.removeMoney(playerId, amount)
    LogManager.admin(string.format("Removed $%d from player %d", amount, playerId))
end

function PlayerManager.setLevel(playerId, level)
    sampSendChat(string.format("/setlevel %d %d", playerId, level))
    LogManager.admin(string.format("Set level %d for player %d", level, playerId))
end

function PlayerManager.setSkin(playerId, skinId)
    sampSendChat(string.format("/setskin %d %d", playerId, skinId))
end

function PlayerManager.setInterior(playerId, interior)
    sampSendChat(string.format("/setint %d %d", playerId, interior))
end

function PlayerManager.setVirtualWorld(playerId, vw)
    sampSendChat(string.format("/setvw %d %d", playerId, vw))
end

function PlayerManager.teleportTo(playerId)
    sampSendChat(string.format("/goto %d", playerId))
    LogManager.admin(string.format("Teleported to player %d", playerId))
end

function PlayerManager.bring(playerId)
    sampSendChat(string.format("/gethere %d", playerId))
    LogManager.admin(string.format("Brought player %d", playerId))
end

function PlayerManager.spectate(playerId)
    sampSendChat(string.format("/sp %d", playerId))
    SpectateQuickPanel.start(playerId)
end

function PlayerManager.freeze(playerId)
    sampSendChat(string.format("/freeze %d", playerId))
    LogManager.admin(string.format("Froze player %d", playerId))
end

function PlayerManager.unfreeze(playerId)
    sampSendChat(string.format("/unfreeze %d", playerId))
    LogManager.admin(string.format("Unfroze player %d", playerId))
end

function PlayerManager.slap(playerId)
    sampSendChat(string.format("/slap %d", playerId))
end

function PlayerManager.explode(playerId)
    LogManager.admin(string.format("Exploded player %d", playerId))
end

function PlayerManager.disarm(playerId)
    sampSendChat(string.format("/disarm %d", playerId))
    LogManager.admin(string.format("Disarmed player %d", playerId))
end

function PlayerManager.heal(playerId)
    sampSendChat(string.format("/heal %d", playerId))
end

function PlayerManager.armorRefill(playerId)
    sampSendChat(string.format("/armour %d", playerId))
end

function PlayerManager.inventoryCheck(playerId)
    LogManager.admin(string.format("Checked inventory of player %d", playerId))
end

function PlayerManager.statsCheck(playerId)
    sampSendChat(string.format("/check %d", playerId))
end

function PlayerManager.getOnlineList()
    local list = {}
    for i = 0, sampGetMaxPlayerId(false) do
        if sampIsPlayerConnected(i) then
            table.insert(list, {
                id = i,
                name = sampGetPlayerNickname(i),
                score = sampGetPlayerScore(i),
                ping = sampGetPlayerPing(i)
            })
        end
    end
    return list
end

function PlayerManager.getAdminList()
    return {}
end

-- ============================================
-- HUD MANAGER (draggable on-screen overlays: real vaqt soati va
-- adminlar soni / o'ynagan vaqt paneli)
-- ============================================
local HudManager = {
    editMode = false,
    clock = {
        enabled = false,
        pos = { x = 0, y = 0 },
        initialized = false
    },
    dateBar = {
        enabled = false,
        pos = { x = 0, y = 0 },
        initialized = false
    },
    adminBar = {
        enabled = false,
        pos = { x = 0, y = 0 },
        initialized = false
    },
    capture = {
        active = false,
        startedAt = 0,
        lineCount = 0,
        directTotal = nil,
        entries = {}
    },
    adminCount = nil,
    adminList = {},
    adminCountUpdatedAt = 0,
    captureWindowSeconds = 2.5,
    autoRefreshIntervalSec = 45,
    lastAutoRefreshAt = 0,
    font = nil,
    fontReady = nil,
    fontScale = nil,
    scale = 1.0,
    opacity = 1.0,
    adminCommand = "/admin",
    weekdays = {
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
    },
    -- Bu patternlar GRAND MOBILE serverining /admins javobi matniga qarab
    -- moslashtirilishi mumkin. Agar son to'g'ri aniqlanmasa, shu yerni tahrirlang.
    directTotalPatterns = {
        "[Oo]nlayn%s*[Aa]dminlar[^%d]-(%d+)",
        "[Aa]dmin[^%d]-(%d+)%s*ta",
        "(%d+)%s*ta%s*[Aa]dmin",
        "[Aa]dmins[^%d]-(%d+)"
    },
    ignoreLinePatterns = {
        "^Online [Aa]dmin",
        "^Onlayn [Aa]dmin",
        "^===",
        "^%-%-%-"
    }
}

-- ============================================
-- TELEPORT MANAGER
-- ============================================
local TeleportManager = {
    savedLocations = {},
    lastDeathLocation = nil,
    interiors = {
        { id = 0, name = "Outside" },
        { id = 1, name = "Restaurant" },
        { id = 2, name = "Ammunation" },
        { id = 3, name = "Police HQ" },
        { id = 4, name = "Motel" },
        { id = 5, name = "Bank" },
        { id = 6, name = "Casino" },
        { id = 17, name = "24/7 Shop" }
    },
    virtualWorlds = {
        { id = 0, name = "Main World" },
        { id = 1, name = "Admin World" },
        { id = 2, name = "Event World" },
        { id = 3, name = "DM World" }
    }
}

function TeleportManager.initialize()
    TeleportManager.loadLocations()
    LogManager.system("Teleport manager initialized")
end

function TeleportManager.loadLocations()
    local path = getWorkingDirectory() .. "/config/locations.ini"
end

function TeleportManager.saveLocation()
end

function TeleportManager.teleportToCoords(x, y, z, interior)
    setCharCoordinates(PLAYER_PED, x, y, z)
    if interior then
        setCharInterior(PLAYER_PED, interior)
    end
    LogManager.admin(string.format("Teleported to %.1f, %.1f, %.1f", x, y, z))
end

function TeleportManager.teleportToLocation(name)
    for _, loc in ipairs(TeleportManager.savedLocations) do
        if loc.name == name then
            TeleportManager.teleportToCoords(loc.x, loc.y, loc.z, loc.interior)
            return true
        end
    end
    return false
end

function TeleportManager.teleportLV()
    TeleportManager.teleportToCoords(2032.9, 1343.2, 10.8)
end

function TeleportManager.teleportLS()
    TeleportManager.teleportToCoords(2493.0, -1666.1, 13.0)
end

function TeleportManager.teleportSF()
    TeleportManager.teleportToCoords(-1758.2, 958.7, 24.9)
end

function TeleportManager.teleportAdminBase()
    TeleportManager.teleportToCoords(-715.559, -2438.529, 1198.149)
    LogManager.admin("Teleported to Admin Base")
end

function TeleportManager.teleportEventZone()
    LogManager.admin("Teleported to Event Zone")
end

function TeleportManager.teleportToWaypoint()
    LogManager.admin("Teleported to waypoint")
end

function TeleportManager.teleportToPlayer(playerId)
    local result, x, y, z = UtilityManager.getPlayerCoords()
    if result then
        TeleportManager.lastPosition = { x = x, y = y, z = z }
    end
    PlayerManager.teleportTo(playerId)
end

function TeleportManager.teleportToInterior(id)
    setCharInterior(PLAYER_PED, id)
end

function TeleportManager.teleportToVirtualWorld(vw)
end

function TeleportManager.teleportToLastDeath()
    if TeleportManager.lastDeathLocation then
        TeleportManager.teleportToCoords(
            TeleportManager.lastDeathLocation.x,
            TeleportManager.lastDeathLocation.y,
            TeleportManager.lastDeathLocation.z
        )
    end
end

function TeleportManager.randomTeleport()
    local locations = {
        { 2032.9, 1343.2, 10.8 },
        { 2493.0, -1666.1, 13.0 },
        { -1758.2, 958.7, 24.9 },
        { 286.1, -159.1, 1.5 },
        { -2323.0, -172.5, 35.3 }
    }
    local randomLoc = locations[math.random(1, #locations)]
    TeleportManager.teleportToCoords(randomLoc[1], randomLoc[2], randomLoc[3])
end

function TeleportManager.teleportToVehicle(vehicleId)
end

-- ============================================
-- SERVER MANAGER
-- ============================================
local ServerManager = {
    serverTime = 12,
    weather = 0,
    eventMode = false,
    serverLocked = false,
    restartScheduled = false,
    restartTime = 0
}

function ServerManager.initialize()
    LogManager.system("Server manager initialized")
end

function ServerManager.getOnlineList()
    return PlayerManager.getOnlineList()
end

function ServerManager.getAdminList()
    return PlayerManager.getAdminList()
end

function ServerManager.getStaffActivity()
    return {}
end

function ServerManager.setServerTime(hour)
    ServerManager.serverTime = hour
    setTimeOfDay(hour, 0)
    LogManager.admin(string.format("Server time set to %d:00", hour))
end

function ServerManager.setWeather(weatherId)
    ServerManager.weather = weatherId
    forceWeatherNow(weatherId)
    LogManager.admin(string.format("Weather changed to %d", weatherId))
end

function ServerManager.scheduleRestart(minutes)
    ServerManager.restartScheduled = true
    ServerManager.restartTime = os.time() + (minutes * 60)
    LogManager.admin(string.format("Server restart scheduled in %d minutes", minutes))
end

function ServerManager.globalAnnouncement(message)
    sampSendChat(string.format("/announce %s", message))
    LogManager.admin(string.format("Global announcement: %s", message))
end

function ServerManager.privateAnnouncement(playerId, message)
    sampSendChat(string.format("/pm %d [ADMIN] %s", playerId, message))
end

function ServerManager.clearChat()
    for i = 1, 20 do
        print(" ")
    end
    LogManager.admin("Chat cleared")
end

function ServerManager.getServerFPS()
    return 60
end

function ServerManager.getPlayerPingList()
    local list = {}
    for i = 0, sampGetMaxPlayerId(false) do
        if sampIsPlayerConnected(i) then
            table.insert(list, {
                id = i,
                name = sampGetPlayerNickname(i),
                ping = sampGetPlayerPing(i)
            })
        end
    end
    return list
end

function ServerManager.getMemoryUsage()
    return collectgarbage("count")
end

function ServerManager.getEntityCount()
    return {
        vehicles = 0,
        objects = 0,
        peds = 0
    }
end

function ServerManager.getVehicleCount()
    return 0
end

function ServerManager.getObjectCount()
    return 0
end

function ServerManager.toggleEventMode()
    ServerManager.eventMode = not ServerManager.eventMode
    LogManager.admin(string.format("Event mode %s", ServerManager.eventMode and "enabled" or "disabled"))
end

function ServerManager.lockServer()
    ServerManager.serverLocked = true
    sampSendChat("/lock")
    LogManager.admin("Server qulflandi")
end

function ServerManager.unlockServer()
    ServerManager.serverLocked = false
    sampSendChat("/unlock")
    LogManager.admin("Server qulfdan chiqarildi")
end

-- ============================================
-- SECURITY MANAGER
-- ============================================
local SecurityManager = {
    blacklist = {},
    whitelist = {},
    suspiciousPlayers = {},
    commandLog = {},
    chatFilter = {
        "hack",
        "cheat",
        "mod menu",
        "aimbot",
        "wallhack"
    }
}

function SecurityManager.initialize()
    SecurityManager.loadLists()
    LogManager.system("Security manager initialized")
end

function SecurityManager.loadLists()
end

function SecurityManager.ipCheck(playerId)
    LogManager.security(string.format("IP check for player %d", playerId))
end

function SecurityManager.serialCheck(playerId)
    LogManager.security(string.format("Serial check for player %d", playerId))
end

function SecurityManager.detectMultiAccount(playerId)
    LogManager.security(string.format("Multi-account check for player %d", playerId))
end

function SecurityManager.detectSuspiciousMovement(playerId)
    if SecurityManager.suspiciousPlayers[playerId] then
        SecurityManager.suspiciousPlayers[playerId].movement = true
    end
end

function SecurityManager.detectSpeedHack(playerId)
    LogManager.security(string.format("Speed hack check for player %d", playerId))
end

function SecurityManager.detectHealthHack(playerId)
    LogManager.security(string.format("Health hack check for player %d", playerId))
end

function SecurityManager.detectTeleportHack(playerId)
    LogManager.security(string.format("Teleport hack check for player %d", playerId))
end

function SecurityManager.addToBlacklist(id, type, reason)
    table.insert(SecurityManager.blacklist, {
        id = id,
        type = type,
        reason = reason,
        timestamp = os.time()
    })
    LogManager.security(string.format("Added %s %s to blacklist: %s", type, id, reason))
end

function SecurityManager.removeFromBlacklist(id)
    for i, entry in ipairs(SecurityManager.blacklist) do
        if entry.id == id then
            table.remove(SecurityManager.blacklist, i)
            LogManager.security(string.format("Removed %s from blacklist", id))
            return true
        end
    end
    return false
end

function SecurityManager.addToWhitelist(id)
    table.insert(SecurityManager.whitelist, id)
    LogManager.security(string.format("Added %s to whitelist", id))
end

function SecurityManager.removeFromWhitelist(id)
    for i, entry in ipairs(SecurityManager.whitelist) do
        if entry == id then
            table.remove(SecurityManager.whitelist, i)
            LogManager.security(string.format("Removed %s from whitelist", id))
            return true
        end
    end
    return false
end

function SecurityManager.autoPunish(playerId, violation)
    LogManager.security(string.format("Auto-punished player %d for %s", playerId, violation))
end

function SecurityManager.antiSpam(playerId, message)
end

function SecurityManager.checkChatFilter(message)
    local lowerMessage = message:lower()
    for _, word in ipairs(SecurityManager.chatFilter) do
        if lowerMessage:find(word) then
            return true, word
        end
    end
    return false
end

function SecurityManager.logCommand(playerId, command)
    table.insert(SecurityManager.commandLog, {
        playerId = playerId,
        command = command,
        timestamp = os.time()
    })
end

function SecurityManager.exportSecurityLog(filename)
    local file = io.open(filename, "w")
    if file then
        for _, log in ipairs(SecurityManager.commandLog) do
            file:write(string.format("[%s] Player %d: %s\n",
                os.date("%Y-%m-%d %H:%M:%S", log.timestamp),
                log.playerId, log.command))
        end
        file:close()
        return true
    end
    return false
end

-- ============================================
-- REPORT CATCH MANAGER
-- ============================================
ReportCatchManager = {
    enabled = true,
    popupOpen = false,
    reportQueue = {},
    currentReport = nil,
    settings = {
        hotkey = vkeys.VK_N,
        popupPos = { x = 100, y = 200 },
        popupSize = { width = 450, height = 320 },
        autoTP = false,
        autoSP = false,
        keywordTpEnabled = false,
        keywordTpText = "tp",
        afkReportEnabled = false,
        afkReportKeywords = "help, yordam, помогите, chin, tuzat, tuzating",
        afkReportReplyText = "Assalom alekum, kuzatyapman",
        afkReportAdminHelpText = "help {id}",
        afkReportCooldown = 8,
        soundEnabled = true,
        animationEnabled = true,
        queueLimit = 20,
        dedupeInterval = 1
    },
    templates = {
        { id = 1, text = "Assalomu alaykum, kuzatyapman", shortcut = "SALOM", autoSpReporter = true },
        { id = 2, text = "Assalomu alaykum, rp nik", shortcut = "RP NIK" },
        { id = 3, text = "Assalomu alaykum, iltimos kuting", shortcut = "KUTING" },
        { id = 4, text = "Assalomu alaykum, yoqimli o'yin tilayman ", shortcut = "TILAK" },
        { id = 5, text = "Assalomu alaykum, teleport qilmaymiz", shortcut = "TAQIQ" },
        { id = 6, text = "Assalomu alaykum, jazoga rozi emasmisiz? Adminga shikoyat yozing", shortcut = "ADM SHIKOYAT" },
        { id = 7, text = "Assalomu alaykum, admin rp jarayonlarga aralashmayadi", shortcut = "RP JARAYON" },
        { id = 8, text = "Assalomu alaykum, isbot bilan, shikoyat yuboring", shortcut = "SHIKOYAT" },
        { id = 9, text = "Assalomu alaykum, nikingizni almashtirish uchun ariza yuboring", shortcut = "NIK ALMASHTIRISH" },
        { id = 10, text = "Assalomu alaykum, teleport yopiq.", shortcut = "mp yopiq" },
        { id = 11, text = "Assalomu alaykum, keyingi off-top uchun jazo qo'llaniladi!", shortcut = "OFF-TOP" },
        { id = 12, text = "Assalomu alaykum, iltimos savolingizni tushunarlik qilib yozing", shortcut = "TUSHUNTIRISH" },
        { id = 13, text = "Assalomu alaykum, nrp nik", shortcut = "NRP NIK" },
        { id = 14, text = "Assalomu alaykum, ha", shortcut = "ha" },
        { id = 15, text = "Salom, Ma'muriyat transport vositalariga yonilg'i quymaydi va tuzatmaydi", shortcut = "rem" },
        { id = 16, text = "Assalomu alaykum, yoq", shortcut = "yoq" }
    },
    recentReports = {},
    dragOffset = { x = 0, y = 0 },
    isDragging = false,
    animationProgress = 0,
    tooltipText = nil,
    tooltipTime = 0,
    pendingPunishmentCheck = nil,
    waitingForReply = false,
    waitingReportId = nil,
    waitingReportNick = "",
    keywordTpQueue = {},
    keywordTpQueuedPlayers = {},
    keywordTpLastByPlayer = {},
    keywordTpLastProcessAt = 0,
    afkReportLastByPlayer = {},
    kerakliUnlocked = false
}

ReportCatchManager.reportPatterns = {
    "Report #(%d+)%s+(%S+)%s+(.+)",
    "%[(%d+)%]%s*(%S+):%s*(.+)",
    "REPORT%s+#?(%d+)%s+(%S+)%s*%-%s*(.+)",
    "[Rr]eport%s+from%s+(%S+)%s*:%s*(.+)",
    "[Жж]алоба%s+от%s+(%S+)%s*:%s*(.+)"
}

-- ============================================
-- ADMIN COMMAND RELAY MANAGER
-- ============================================
local AdminRelayManager = {
    enabled = true,
    popupOpen = false,
    current = nil,
    queue = {},
    recent = {},
    settings = {
        popupPos = { x = 420, y = 180 },
        popupSize = { width = 640, height = 360 },
        queueLimit = 20,
        dedupeMs = 1200
    },
    reasonCommands = {
        kick = true,
        ban = true,
        tempban = true,
        mute = true,
        jail = true,
        warn = true,
        ans = true
    },
    timedReasonCommands = {
        ban = true,
        tempban = true,
        mute = true,
        jail = true
    },
    playerIdCommands = {
        kick = true,
        ban = true,
        tempban = true,
        mute = true,
        unmute = true,
        jail = true,
        unjail = true,
        warn = true,
        unwarn = true,
        ["goto"] = true,
        gethere = true,
        sp = true,
        freeze = true,
        unfreeze = true,
        slap = true,
        fixcar = true,
        flip = true,
        sethp = true,
        setarmor = true,
        setlevel = true,
        setskin = true,
        setint = true,
        setvw = true,
        heal = true,
        armour = true,
        disarm = true,
        check = true
    },
    punishmentState = {
        mute = {},
        ban = {}
    }
}

function AdminRelayManager.initialize()
    AdminRelayManager.popupOpen = false
    AdminRelayManager.current = nil
    AdminRelayManager.queue = {}
    AdminRelayManager.recent = {}
    AdminRelayManager.punishmentState = {
        mute = {},
        ban = {}
    }
    LogManager.system("Admin Relay Manager initialized")
end

function AdminRelayManager.getNowMs()
    if type(getTickCount) == "function" then
        local ok, value = pcall(getTickCount)
        if ok and type(value) == "number" then
            return value
        end
    end
    return math.floor(os.clock() * 1000)
end

function AdminRelayManager.foldText(text)
    local value = tostring(text or "")
    value = UtilityManager.casefoldUtf8Cyrillic(value)
    value = UtilityManager.casefoldCp1251Cyrillic(value)
    return value
end

function AdminRelayManager.cleanupRecent(nowMs)
    local threshold = math.max(250, tonumber(AdminRelayManager.settings.dedupeMs) or 1200)
    for key, storedAt in pairs(AdminRelayManager.recent) do
        if (nowMs - storedAt) > threshold then
            AdminRelayManager.recent[key] = nil
        end
    end
end

function AdminRelayManager.isDuplicate(senderNick, commandText)
    local nowMs = AdminRelayManager.getNowMs()
    AdminRelayManager.cleanupRecent(nowMs)
    local key = AdminRelayManager.foldText(tostring(senderNick or "") .. "|" .. tostring(commandText or ""))
    if key == "" then
        return false
    end
    if AdminRelayManager.recent[key] then
        return true
    end
    AdminRelayManager.recent[key] = nowMs
    return false
end

function AdminRelayManager.getLocalNick()
    if not sampGetPlayerIdByCharHandle or not sampGetPlayerNickname or not PLAYER_PED then
        return ""
    end

    local okId, success, playerId = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
    if (not okId) or (not success) or (not playerId) then
        return ""
    end

    local okNick, nick = pcall(sampGetPlayerNickname, playerId)
    if not okNick then
        return ""
    end

    return tostring(nick or "")
end

function AdminRelayManager.isLocalSender(senderNick)
    local localNick = AdminRelayManager.getLocalNick()
    if localNick == "" then
        return false
    end

    return AdminRelayManager.foldText(localNick) == AdminRelayManager.foldText(senderNick)
end

function AdminRelayManager.isAdminChatPrefix(prefixText)
    local raw = tostring(prefixText or "")
    if raw == "" then
        return false
    end

    if raw:find("<ADM>", 1, true) or raw:find("<adm>", 1, true) then
        return true
    end

    local folded = AdminRelayManager.foldText(raw)
    if folded:find("administrator", 1, true) then
        return true
    end
    if folded:find("admin", 1, true) or folded:find("админ", 1, true) then
        return true
    end

    return false
end

function AdminRelayManager.extractSenderNick(prefixText)
    local prefix = tostring(prefixText or "")
    prefix = prefix:gsub("{%x%x%x%x%x%x}", "")
    prefix = prefix:gsub("%)%s*$", "")
    prefix = UtilityManager.trim(prefix)

    local nick = prefix:match("([%w_]+)%[%d+%]%s*$")
    if nick and nick ~= "" then
        return nick
    end

    nick = prefix:match("([%w_]+)%s*$")
    if nick and nick ~= "" then
        return nick
    end

    return ""
end

function AdminRelayManager.buildSenderSignature(senderNick)
    local nick = UtilityManager.trim(tostring(senderNick or ""))
    if nick == "" then
        return ""
    end

    local first, second = nick:match("^([^_]+)_([^_]+)$")
    if first and second and first ~= "" and second ~= "" then
        return string.format("%s.%s", first:sub(1, 1), second)
    end

    return nick:gsub("_", ".")
end

function AdminRelayManager.hasTailSignature(commandText, signatureText)
    local cmd = UtilityManager.trim(tostring(commandText or ""))
    local signature = UtilityManager.trim(tostring(signatureText or ""))
    if cmd == "" or signature == "" then
        return false
    end

    local cmdFolded = AdminRelayManager.foldText(cmd)
    local sigFolded = AdminRelayManager.foldText(signature)
    local sigLength = #sigFolded
    local cmdLength = #cmdFolded
    local startPos = cmdLength - sigLength + 1
    if startPos < 1 then
        return false
    end

    if cmdFolded:sub(startPos) ~= sigFolded then
        return false
    end

    if startPos == 1 then
        return true
    end

    local prev = cmdFolded:sub(startPos - 1, startPos - 1)
    return prev:match("[%s%p]") ~= nil
end

function AdminRelayManager.extractReasonTailSignature(commandText)
    local cmd = UtilityManager.trim(tostring(commandText or ""))
    if cmd == "" then
        return nil, nil
    end

    local reasonPart, nickPart = cmd:match("^(.-)%s+|%s+([%w_%.]+)%s*$")
    if not reasonPart or not nickPart then
        return nil, nil
    end

    reasonPart = UtilityManager.trim(reasonPart)
    nickPart = UtilityManager.trim(nickPart)
    if reasonPart == "" or nickPart == "" then
        return nil, nil
    end

    return reasonPart, nickPart
end

function AdminRelayManager.hasAnyTailSignature(commandText)
    local _, nickPart = AdminRelayManager.extractReasonTailSignature(commandText)
    return nickPart ~= nil
end

function AdminRelayManager.shouldAppendSignature(commandText)
    local command = UtilityManager.trim(tostring(commandText or ""))
    if command == "" then
        return false
    end

    local commandName = command:match("^/([%w_]+)")
    if not commandName then
        return false
    end

    commandName = AdminRelayManager.foldText(commandName)
    return AdminRelayManager.reasonCommands[commandName] == true
end

function AdminRelayManager.sendAdminFeedback(message)
    local text = UtilityManager.trim(tostring(message or ""))
    if text == "" then
        return
    end
    sampSendChat("/a " .. text)
end

function AdminRelayManager.parseCommandParts(commandText)
    local command = UtilityManager.trim(tostring(commandText or ""))
    if command == "" or command:sub(1, 1) ~= "/" then
        return nil
    end

    local parts = {}
    for token in command:gmatch("%S+") do
        table.insert(parts, token)
    end
    if #parts == 0 then
        return nil
    end

    local commandName = tostring(parts[1] or ""):gsub("^/", "")
    commandName = AdminRelayManager.foldText(commandName)
    return {
        name = commandName,
        parts = parts,
        raw = command
    }
end

function AdminRelayManager.extractTargetId(commandInfo)
    if not commandInfo or not commandInfo.parts then
        return nil
    end
    return tonumber(commandInfo.parts[2])
end

function AdminRelayManager.validateTimedReasonFormat(commandInfo)
    if not commandInfo or not commandInfo.name then
        return false, "format xato"
    end

    if not AdminRelayManager.timedReasonCommands[commandInfo.name] then
        return true, nil
    end

    local parts = commandInfo.parts or {}
    local targetId = tonumber(parts[2])
    local duration = tonumber(parts[3])
    local reason = UtilityManager.trim(table.concat(parts, " ", 4))

    if not targetId then
        return false, "bunday id mavjud emas"
    end
    if not duration or duration <= 0 then
        return false, string.format("format: /%s id vaqt prichina", commandInfo.name)
    end
    if reason == "" then
        return false, string.format("format: /%s id vaqt prichina", commandInfo.name)
    end

    -- Accept and validate explicit signature style:
    -- /jail id vaqt prichina | Nick
    if reason:find("|", 1, true) then
        local reasonBody, reasonNick = AdminRelayManager.extractReasonTailSignature(reason)
        if not reasonBody or not reasonNick then
            return false, string.format("format: /%s id vaqt prichina | Nick", commandInfo.name)
        end
    end

    return true, nil
end

function AdminRelayManager.isValidPlayerId(playerId)
    if not playerId then
        return false
    end
    if not sampIsPlayerConnected then
        return true
    end
    local ok, connected = pcall(sampIsPlayerConnected, playerId)
    if not ok then
        return true
    end
    return connected == true
end

function AdminRelayManager.getPunishmentType(commandName)
    local name = AdminRelayManager.foldText(commandName or "")
    if name == "mute" then
        return "mute"
    end
    if name == "ban" or name == "tempban" then
        return "ban"
    end
    return nil
end

function AdminRelayManager.hasExistingPunishment(punishmentType, playerId)
    local byType = AdminRelayManager.punishmentState[punishmentType]
    if not byType or not playerId then
        return false
    end
    return byType[playerId] == true
end

function AdminRelayManager.updatePunishmentState(commandName, playerId)
    if not playerId then
        return
    end

    local name = AdminRelayManager.foldText(commandName or "")
    if name == "mute" then
        AdminRelayManager.punishmentState.mute[playerId] = true
        return
    end
    if name == "unmute" then
        AdminRelayManager.punishmentState.mute[playerId] = nil
        return
    end
    if name == "ban" or name == "tempban" then
        AdminRelayManager.punishmentState.ban[playerId] = true
        return
    end
    if name == "unban" then
        AdminRelayManager.punishmentState.ban[playerId] = nil
        return
    end
end

function AdminRelayManager.buildExecutableCommand(commandText, senderNick)
    local command = UtilityManager.trim(tostring(commandText or ""))
    if command == "" then
        return "", ""
    end

    -- Normalize provided suffix style to: " ... | Nick "
    local prefixPart, providedNick = AdminRelayManager.extractReasonTailSignature(command)
    if prefixPart and providedNick then
        command = string.format("%s | %s", prefixPart, providedNick)
    end

    local signature = AdminRelayManager.buildSenderSignature(senderNick)
    if signature ~= "" and AdminRelayManager.shouldAppendSignature(command) and
       (not AdminRelayManager.hasTailSignature(command, signature)) and
       (not AdminRelayManager.hasAnyTailSignature(command)) then
        command = command .. " | " .. signature
    end

    return command, signature
end

function AdminRelayManager.parseIncomingCommandMessage(text)
    local cleanText = tostring(text or ""):gsub("{%x%x%x%x%x%x}", "")
    cleanText = cleanText:gsub("[\r\n]+", " ")
    cleanText = UtilityManager.trim(cleanText)
    if cleanText == "" then
        return nil
    end

    local prefix, rawCommand = cleanText:match("^(.-):%s*(/.+)$")
    if not prefix or not rawCommand then
        return nil
    end

    rawCommand = UtilityManager.trim(rawCommand)
    if rawCommand == "" or rawCommand:sub(1, 1) ~= "/" then
        return nil
    end

    if not AdminRelayManager.isAdminChatPrefix(prefix) then
        return nil
    end

    local senderNick = AdminRelayManager.extractSenderNick(prefix)
    if senderNick == "" then
        return nil
    end

    if AdminRelayManager.isLocalSender(senderNick) then
        return nil
    end

    local executableCommand, signature = AdminRelayManager.buildExecutableCommand(rawCommand, senderNick)
    if executableCommand == "" then
        return nil
    end

    return {
        senderNick = senderNick,
        rawCommand = rawCommand,
        executableCommand = executableCommand,
        signature = signature,
        sourceText = cleanText,
        createdAt = os.date("%H:%M:%S")
    }
end

function AdminRelayManager.openRequest(request)
    if not request then
        return
    end

    if AdminRelayManager.popupOpen and AdminRelayManager.current then
        if #AdminRelayManager.queue >= (AdminRelayManager.settings.queueLimit or 20) then
            table.remove(AdminRelayManager.queue, 1)
        end
        table.insert(AdminRelayManager.queue, request)
        return
    end

    AdminRelayManager.current = request
    AdminRelayManager.popupOpen = true
end

function AdminRelayManager.advanceQueue()
    if #AdminRelayManager.queue > 0 then
        AdminRelayManager.current = table.remove(AdminRelayManager.queue, 1)
        AdminRelayManager.popupOpen = true
        return
    end

    AdminRelayManager.current = nil
    AdminRelayManager.popupOpen = false
end

function AdminRelayManager.confirmCurrent()
    local current = AdminRelayManager.current
    if not current then
        return
    end

    local executable = UtilityManager.trim(tostring(current.executableCommand or ""))
    local commandInfo = AdminRelayManager.parseCommandParts(executable)

    if commandInfo and AdminRelayManager.playerIdCommands[commandInfo.name] then
        local formatOk, formatError = AdminRelayManager.validateTimedReasonFormat(commandInfo)
        if not formatOk then
            AdminRelayManager.sendAdminFeedback(formatError or "format xato")
            LogManager.admin(string.format(
                "Relay blocked (bad format): %s (from %s)",
                executable,
                current.senderNick or "unknown"))
            sampAddChatMessage("[Harvey] Relay blocked: noto'g'ri format", 0xFF6666)
            AdminRelayManager.advanceQueue()
            return
        end

        local targetId = AdminRelayManager.extractTargetId(commandInfo)
        if not AdminRelayManager.isValidPlayerId(targetId) then
            AdminRelayManager.sendAdminFeedback("bunday id mavjud emas")
            LogManager.admin(string.format(
                "Relay blocked (invalid id): %s (from %s)",
                executable,
                current.senderNick or "unknown"))
            sampAddChatMessage("[Harvey] Relay blocked: bunday id mavjud emas", 0xFF6666)
            AdminRelayManager.advanceQueue()
            return
        end

        local punishmentType = AdminRelayManager.getPunishmentType(commandInfo.name)
        if punishmentType and AdminRelayManager.hasExistingPunishment(punishmentType, targetId) then
            AdminRelayManager.sendAdminFeedback("igrokda ushbi jazo turi mavjud")
            LogManager.admin(string.format(
                "Relay blocked (duplicate punishment): %s (from %s)",
                executable,
                current.senderNick or "unknown"))
            sampAddChatMessage("[Harvey] Relay blocked: igrokda ushbi jazo turi mavjud", 0xFF9933)
            AdminRelayManager.advanceQueue()
            return
        end

        if executable ~= "" then
            sampSendChat(executable)
            AdminRelayManager.updatePunishmentState(commandInfo.name, targetId)
            AdminRelayManager.sendAdminFeedback("+")
            LogManager.admin(string.format("Relay confirm: %s (from %s)", executable, current.senderNick or "unknown"))
            sampAddChatMessage(string.format("[Harvey] Relay Confirm: %s", executable), 0x33FF66)
        end
    elseif executable ~= "" then
        sampSendChat(executable)
        AdminRelayManager.sendAdminFeedback("+")
        LogManager.admin(string.format("Relay confirm: %s (from %s)", executable, current.senderNick or "unknown"))
        sampAddChatMessage(string.format("[Harvey] Relay Confirm: %s", executable), 0x33FF66)
    end

    AdminRelayManager.advanceQueue()
end

function AdminRelayManager.cancelCurrent()
    local current = AdminRelayManager.current
    if current then
        LogManager.admin(string.format("Relay canceled: %s (from %s)", current.rawCommand or "", current.senderNick or "unknown"))
        sampAddChatMessage(string.format("[Harvey] Relay Cancel: %s", tostring(current.rawCommand or "")), 0xFF9933)
    end

    AdminRelayManager.advanceQueue()
end

function AdminRelayManager.processIncomingMessage(text)
    if not AdminRelayManager.enabled then
        return
    end

    local request = AdminRelayManager.parseIncomingCommandMessage(text)
    if not request then
        return
    end

    if AdminRelayManager.isDuplicate(request.senderNick, request.rawCommand) then
        return
    end

    AdminRelayManager.openRequest(request)
    LogManager.admin(string.format("Relay request queued from %s: %s", request.senderNick, request.rawCommand))
end

function AdminRelayManager.renderPopup()
    if not AdminRelayManager.popupOpen or not AdminRelayManager.current then
        return
    end

    local current = AdminRelayManager.current
    local settings = AdminRelayManager.settings

    local defaultWidth = settings.popupSize.width or 640
    local defaultHeight = settings.popupSize.height or 360
    local minWidth = 520
    local minHeight = 290

    if defaultWidth < minWidth then
        defaultWidth = minWidth
        settings.popupSize.width = minWidth
    end
    if defaultHeight < minHeight then
        defaultHeight = minHeight
        settings.popupSize.height = minHeight
    end

    if settings.popupPos and settings.popupPos.x and settings.popupPos.y then
        imgui.SetNextWindowPos(
            imgui.ImVec2(settings.popupPos.x, settings.popupPos.y),
            imgui.Cond.FirstUseEver
        )
    end
    imgui.SetNextWindowSize(imgui.ImVec2(defaultWidth, defaultHeight), imgui.Cond.FirstUseEver)
    if imgui.SetNextWindowSizeConstraints then
        local screenX, screenY = getScreenResolution()
        screenX = screenX or 1920
        screenY = screenY or 1080
        imgui.SetNextWindowSizeConstraints(
            imgui.ImVec2(minWidth, minHeight),
            imgui.ImVec2(math.max(minWidth, screenX - 10), math.max(minHeight, screenY - 10))
        )
    end

    local flags = imgui.WindowFlags.NoCollapse
    if imgui.Begin("Admin Command Confirm##AdminRelayPopup", nil, flags) then
        local windowSize = imgui.GetWindowSize()
        local widthScale = (windowSize and windowSize.x) and (windowSize.x / 640) or 1.0
        local heightScale = (windowSize and windowSize.y) and (windowSize.y / 360) or 1.0
        local uiScale = UtilityManager.clamp((widthScale + heightScale) * 0.5, 0.75, 1.80)
        if imgui.SetWindowFontScale then
            imgui.SetWindowFontScale(uiScale)
        end

        local buttonHeight = math.max(28, math.floor(34 * uiScale))
        local buttonWidth = math.max(110, math.floor(150 * uiScale))
        local footerReserve = buttonHeight + math.max(16, math.floor(22 * uiScale))

        imgui.BeginChild("##RelayBody", imgui.ImVec2(0, -footerReserve), false)
        imgui.TextColored(COLORS.WARNING or imgui.ImVec4(0.95, 0.77, 0.06, 1.0), "Admin command request")
        imgui.Text(string.format("From: %s", UtilityManager.toUtf8(current.senderNick or "Unknown")))
        imgui.TextDisabled(string.format("Time: %s", tostring(current.createdAt or "--:--:--")))
        imgui.Separator()

        local boxHeight = math.max(82, math.floor(98 * uiScale))

        imgui.TextDisabled("Received:")
        imgui.BeginChild("##RelayRawCmd", imgui.ImVec2(0, boxHeight), true)
        imgui.TextWrapped(UtilityManager.toUtf8(current.rawCommand or ""))
        imgui.EndChild()

        imgui.TextDisabled("Will execute:")
        imgui.BeginChild("##RelayExecCmd", imgui.ImVec2(0, boxHeight), true)
        imgui.TextWrapped(UtilityManager.toUtf8(current.executableCommand or ""))
        imgui.EndChild()
        imgui.EndChild()

        imgui.Separator()

        if imgui.Button("Confirm##RelayConfirm", imgui.ImVec2(buttonWidth, buttonHeight)) then
            AdminRelayManager.confirmCurrent()
        end
        imgui.SameLine(0, math.max(8, math.floor(10 * uiScale)))
        if imgui.Button("Cancel##RelayCancel", imgui.ImVec2(buttonWidth, buttonHeight)) then
            AdminRelayManager.cancelCurrent()
        end
        imgui.SameLine(0, math.max(8, math.floor(10 * uiScale)))
        imgui.TextDisabled(string.format("Queue: %d", #AdminRelayManager.queue))

        if imgui.SetWindowFontScale then
            imgui.SetWindowFontScale(1.0)
        end
    end

    local windowPos = imgui.GetWindowPos()
    local windowSize = imgui.GetWindowSize()
    settings.popupPos.x = windowPos.x
    settings.popupPos.y = windowPos.y
    settings.popupSize.width = windowSize.x
    settings.popupSize.height = windowSize.y
    imgui.End()
end

function ReportCatchManager.initialize()
    ReportCatchManager.loadSettings()
    -- Force reliable defaults on each start
    ReportCatchManager.enabled = true
    ReportCatchManager.settings.hotkey = vkeys.VK_N
    ReportCatchManager.kerakliUnlocked = false
    LogManager.system("Report Catch Manager initialized")
end

function ReportCatchManager.loadSettings()
    local path = UtilityManager.getConfigPath("reportcatch.ini")
    local saved = inicfg.load(nil, path)
    if saved then
        ReportCatchManager.enabled = (saved.enabled ~= nil and saved.enabled) or
                                     (saved.settings and saved.settings.enabled) or true
        ReportCatchManager.settings.hotkey = saved.settings and saved.settings.hotkey or vkeys.VK_N
        ReportCatchManager.settings.autoTP = saved.settings and saved.settings.autoTP or false
        ReportCatchManager.settings.autoSP = saved.settings and saved.settings.autoSP or false
        ReportCatchManager.settings.keywordTpEnabled = saved.settings and saved.settings.keywordTpEnabled or false
        ReportCatchManager.settings.keywordTpText = saved.settings and tostring(saved.settings.keywordTpText or "tp") or "tp"
        ReportCatchManager.settings.afkReportEnabled = saved.settings and saved.settings.afkReportEnabled or false
        ReportCatchManager.settings.afkReportKeywords = saved.settings and tostring(saved.settings.afkReportKeywords or "help, yordam, помогите, chin, tuzat, tuzating") or "help, yordam, помогите, chin, tuzat, tuzating"
        ReportCatchManager.settings.afkReportReplyText = saved.settings and tostring(saved.settings.afkReportReplyText or "Assalom alekum, kuzatyapman") or "Assalom alekum, kuzatyapman"
        ReportCatchManager.settings.afkReportAdminHelpText = saved.settings and tostring(saved.settings.afkReportAdminHelpText or "help {id}") or "help {id}"
        ReportCatchManager.settings.afkReportCooldown = saved.settings and tonumber(saved.settings.afkReportCooldown) or 8
        ReportCatchManager.settings.soundEnabled = saved.settings and saved.settings.soundEnabled or true
        ReportCatchManager.settings.animationEnabled = saved.settings and saved.settings.animationEnabled or true
        ReportCatchManager.settings.queueLimit = saved.settings and saved.settings.queueLimit or 20
        ReportCatchManager.settings.dedupeInterval = saved.settings and saved.settings.dedupeInterval or 1
    end

    ReportCatchManager.settings.keywordTpText =
        UtilityManager.trim(tostring(ReportCatchManager.settings.keywordTpText or "tp"))
    if ReportCatchManager.settings.keywordTpText == "" then
        ReportCatchManager.settings.keywordTpText = "tp"
    end

    ReportCatchManager.settings.afkReportKeywords =
        UtilityManager.trim(tostring(ReportCatchManager.settings.afkReportKeywords or ""))
    if ReportCatchManager.settings.afkReportKeywords == "" then
        ReportCatchManager.settings.afkReportKeywords = "help, yordam, помогите, chin, tuzat, tuzating"
    end

    ReportCatchManager.settings.afkReportReplyText =
        UtilityManager.trim(tostring(ReportCatchManager.settings.afkReportReplyText or ""))
    if ReportCatchManager.settings.afkReportReplyText == "" then
        ReportCatchManager.settings.afkReportReplyText = "Assalom alekum, kuzatyapman"
    end

    ReportCatchManager.settings.afkReportAdminHelpText =
        UtilityManager.trim(tostring(ReportCatchManager.settings.afkReportAdminHelpText or ""))
    if ReportCatchManager.settings.afkReportAdminHelpText == "" then
        ReportCatchManager.settings.afkReportAdminHelpText = "help {id}"
    end

    ReportCatchManager.settings.afkReportCooldown =
        math.max(0, math.min(300, tonumber(ReportCatchManager.settings.afkReportCooldown) or 8))
end

function ReportCatchManager.saveSettings()
    local path = UtilityManager.getConfigPath("reportcatch.ini")
    local data = {
        settings = ReportCatchManager.settings,
        enabled = ReportCatchManager.enabled
    }
    UtilityManager.safeIniSave(data, path)
end

function ReportCatchManager.toggle()
    ReportCatchManager.enabled = not ReportCatchManager.enabled
    if ReportCatchManager.enabled then
        imgui.Process = true
        imgui.ShowCursor = true
    end
    LogManager.system(string.format("Report Catch %s", ReportCatchManager.enabled and "enabled" or "disabled"))
    return ReportCatchManager.enabled
end

function ReportCatchManager.isDuplicate(reportId, nick)
    local key = tostring(reportId) .. "_" .. nick
    local now = os.time()

    for k, time in pairs(ReportCatchManager.recentReports) do
        if now - time > ReportCatchManager.settings.dedupeInterval then
            ReportCatchManager.recentReports[k] = nil
        end
    end

    if ReportCatchManager.recentReports[key] then
        return true
    end

    ReportCatchManager.recentReports[key] = now
    return false
end

function ReportCatchManager.setWaitingReport(report)
    ReportCatchManager.waitingForReply = true
    ReportCatchManager.waitingReportId = report and tonumber(report.id) or nil
    ReportCatchManager.waitingReportNick = report and (report.nick or "") or ""
    -- Strict mode: while waiting for reply, queued reports are dropped.
    ReportCatchManager.reportQueue = {}
end

function ReportCatchManager.clearWaitingReport()
    ReportCatchManager.waitingForReply = false
    ReportCatchManager.waitingReportId = nil
    ReportCatchManager.waitingReportNick = ""
end

function ReportCatchManager.markAnswered(reportId)
    local answeredId = tonumber(reportId)
    local pending = ReportCatchManager.pendingPunishmentCheck
    if pending and answeredId then
        local pendingReportId = tonumber(pending.reportId)
        local pendingAnswerTarget = tonumber(pending.answerTargetId)
        local pendingPlayerId = tonumber(pending.playerId)
        if answeredId == pendingReportId or answeredId == pendingAnswerTarget or answeredId == pendingPlayerId then
            ReportCatchManager.pendingPunishmentCheck = nil
            LogManager.report(string.format("Punishment check canceled: report answered (%d)", answeredId))
        end
    end

    if not ReportCatchManager.waitingForReply then
        return false
    end

    local expectedId = tonumber(ReportCatchManager.waitingReportId)
    answeredId = tonumber(reportId)

    if expectedId and answeredId and expectedId ~= answeredId then
        return false
    end

    local resolvedId = expectedId or answeredId or 0
    ReportCatchManager.clearWaitingReport()
    LogManager.report(string.format("Report #%d marked as answered", resolvedId))
    return true
end

function ReportCatchManager.shouldIgnoreIncoming(report)
    if not ReportCatchManager.waitingForReply then
        return false
    end

    local incomingId = tonumber(report and report.id or 0) or 0
    local incomingNick = (report and report.nick) or "Unknown"
    local waitingId = tonumber(ReportCatchManager.waitingReportId or 0) or 0
    LogManager.report(string.format(
        "Incoming report #%d from %s ignored (waiting answer for #%d)",
        incomingId, incomingNick, waitingId))
    return true
end

function ReportCatchManager.getKeywordTpTrigger()
    local trigger = UtilityManager.trim(tostring(ReportCatchManager.settings.keywordTpText or ""))
    if trigger == "" then
        return ""
    end
    return trigger:lower()
end

function ReportCatchManager.markKeywordTp(playerId)
    local id = tonumber(playerId)
    if not id then
        return
    end
    ReportCatchManager.keywordTpLastByPlayer[id] = os.time()
end

function ReportCatchManager.resolveAutoActionPlayerId(report)
    if not report then
        return nil
    end

    local playerId = tonumber(report.playerId)
    if playerId then
        if not sampIsPlayerConnected or sampIsPlayerConnected(playerId) then
            return playerId
        end
    end

    local nick = tostring(report.nick or "")
    if nick ~= "" then
        return ReportCatchManager.getPlayerIdByNick(nick)
    end

    return nil
end

function ReportCatchManager.isKerakliUnlocked()
    return ReportCatchManager.kerakliUnlocked == true and
           MainUI and MainUI.kerakliAccess and MainUI.kerakliAccess.unlocked == true
end

function ReportCatchManager.isMpUnlocked()
    return MainUI and MainUI.mpAccess and MainUI.mpAccess.unlocked == true
end

function ReportCatchManager.shouldRunAutoActions()
    local kerakliUnlocked = ReportCatchManager.isKerakliUnlocked()
    local afkReportActive = (ReportCatchManager.settings.afkReportEnabled or false) and kerakliUnlocked
    local keywordTpActive = (ReportCatchManager.settings.keywordTpEnabled or false) and ReportCatchManager.isMpUnlocked()
    return afkReportActive or
           keywordTpActive or
           (ReportCatchManager.settings.autoTP or false) or
           (ReportCatchManager.settings.autoSP or false)
end

function SpectateQuickPanel.resolveTemplateTargetId()
    local targetId = tonumber(SpectateQuickPanel.targetId)
    if targetId and targetId > 0 then
        return targetId
    end
    return nil
end

function ReportCatchManager.getAfkReportKeywordList()
    local raw = tostring(ReportCatchManager.settings.afkReportKeywords or "")
    local keywords = {}
    local seen = {}

    for token in raw:gmatch("[^,;\r\n]+") do
        local trimmed = UtilityManager.trim(token or "")
        if trimmed ~= "" then
            local key = trimmed:lower()
            if not seen[key] then
                table.insert(keywords, trimmed)
                seen[key] = true
            end
        end
    end

    return keywords
end

function ReportCatchManager.matchAfkReportKeyword(reportText)
    local source = tostring(reportText or ""):gsub("{%x%x%x%x%x%x}", "")
    source = UtilityManager.trim(source)
    if source == "" then
        return nil
    end

    local sourceVariants = UtilityManager.getMatchVariants(source)
    if #sourceVariants == 0 then
        return nil
    end

    local keywords = ReportCatchManager.getAfkReportKeywordList()
    for _, keyword in ipairs(keywords) do
        local keywordVariants = UtilityManager.getMatchVariants(keyword)
        for _, srcVariant in ipairs(sourceVariants) do
            local srcCompact = srcVariant:gsub("%s+", "")
            for _, keywordVariant in ipairs(keywordVariants) do
                if srcVariant:find(keywordVariant, 1, true) then
                    return keyword
                end

                local kwCompact = keywordVariant:gsub("%s+", "")
                if kwCompact ~= "" and srcCompact:find(kwCompact, 1, true) then
                    return keyword
                end
            end
        end
    end

    return nil
end

function ReportCatchManager.getAfkReportCooldown()
    return math.max(0, math.min(300, tonumber(ReportCatchManager.settings.afkReportCooldown) or 8))
end

function ReportCatchManager.shouldForceAfkRecovery(reportText)
    local source = tostring(reportText or ""):gsub("{%x%x%x%x%x%x}", "")
    source = UtilityManager.trim(source):lower()
    if source == "" then
        return false
    end

    local hints = {
        "tuzat",
        "tuzating",
        "fix",
        "fixcar",
        "repair",
        "agdar",
        "ag'dar",
        "agdarilib",
        "ag'darilib",
        "flip",
        "buzilgan",
        "buzildi"
    }

    for _, hint in ipairs(hints) do
        if source:find(hint, 1, true) then
            return true
        end
    end

    return false
end

function ReportCatchManager.buildAfkAdminHelpCommand(playerId)
    local template = UtilityManager.trim(tostring(ReportCatchManager.settings.afkReportAdminHelpText or ""))
    if template == "" then
        template = "help {id}"
    end

    local idText = tostring(playerId)
    local payload
    if template:find("{id}", 1, true) then
        payload = template:gsub("{id}", idText)
    else
        payload = string.format("%s %s", template, idText)
    end

    payload = UtilityManager.trim(payload:gsub("%s%s+", " "))
    return "/a " .. payload
end

function ReportCatchManager.getPlayerPedHandle(playerId)
    if type(sampGetCharHandleBySampPlayerId) ~= "function" then
        return nil
    end

    local ok, a, b = pcall(sampGetCharHandleBySampPlayerId, playerId)
    if not ok then
        return nil
    end

    local handle = nil
    if type(a) == "boolean" then
        if not a then
            return nil
        end
        handle = tonumber(b)
    else
        handle = tonumber(a)
    end

    if not handle then
        return nil
    end

    if type(doesCharExist) == "function" then
        local okExists, exists = pcall(doesCharExist, handle)
        if okExists and not exists then
            return nil
        end
    end

    return handle
end

function ReportCatchManager.getPlayerVehicleState(playerId)
    local state = {
        known = false,
        inCar = false,
        inWater = false,
        isFlipped = false,
        isBroken = false
    }

    local ped = ReportCatchManager.getPlayerPedHandle(playerId)
    if not ped then
        return state
    end

    state.known = true

    if type(isCharInAnyCar) == "function" then
        local okInCar, inCar = pcall(isCharInAnyCar, ped)
        state.inCar = okInCar and inCar or false
    end

    if not state.inCar then
        return state
    end

    local vehicle = nil
    if type(storeCarCharIsInNoSave) == "function" then
        local okCar, car = pcall(storeCarCharIsInNoSave, ped)
        if okCar then
            vehicle = tonumber(car)
        end
    elseif type(storeCarCharIsIn) == "function" then
        local okCar, car = pcall(storeCarCharIsIn, ped)
        if okCar then
            vehicle = tonumber(car)
        end
    end

    if not vehicle then
        return state
    end

    if type(doesVehicleExist) == "function" then
        local okVehicle, exists = pcall(doesVehicleExist, vehicle)
        if okVehicle and not exists then
            return state
        end
    end

    if type(isCarInWater) == "function" then
        local okWater, inWater = pcall(isCarInWater, vehicle)
        state.inWater = okWater and inWater or false
    end

    if type(isCarUpsideDown) == "function" then
        local okUpside, upside = pcall(isCarUpsideDown, vehicle)
        state.isFlipped = okUpside and upside or false
    end

    if type(getCarHealth) == "function" then
        local okHealth, health = pcall(getCarHealth, vehicle)
        local hp = okHealth and tonumber(health) or nil
        if hp and hp > 0 and hp < 650 then
            state.isBroken = true
        end
    end

    return state
end

function ReportCatchManager.sendAfkRecoveryCommands(playerId, attempts, delayMs)
    if not ReportCatchManager.isKerakliUnlocked() then
        return false
    end

    local id = tonumber(playerId)
    if not id then
        return false
    end

    local total = math.max(1, math.min(3, tonumber(attempts) or 1))
    local gap = math.max(250, math.min(1200, tonumber(delayMs) or 550))

    for index = 1, total do
        if not ReportCatchManager.isKerakliUnlocked() then
            return false
        end
        sampSendChat(string.format("/flip %d", id))
        wait(gap)
        if not ReportCatchManager.isKerakliUnlocked() then
            return false
        end
        sampSendChat(string.format(" %d", id))
        if index < total then
            wait(gap)
        end
    end

    return true
end

function ReportCatchManager.runAfkVehicleAutoActions(playerId, reportText)
    if not ReportCatchManager.isKerakliUnlocked() then
        return
    end

    local id = tonumber(playerId)
    if not id then
        return
    end

    local forceRecoveryByText = ReportCatchManager.shouldForceAfkRecovery(reportText)
    local localAfk = AFKManager and AFKManager.isAFK == true
    local recoveryAlreadySent = false
    local preState = ReportCatchManager.getPlayerVehicleState(id)
    local preWaterInCar = preState and preState.inCar and preState.inWater or false

    if localAfk and not preWaterInCar then
        -- AFK paytida stream holati kechikishi mumkin, bir marta darhol yuboramiz.
        sampSendChat(string.format("/flip %d", id))
        sampSendChat(string.format(" %d", id))
        recoveryAlreadySent = true
        LogManager.report(string.format(
            "AFK report: immediate recovery fallback sent for #%d (localAfk=%s)",
            id,
            tostring(localAfk)))
    elseif localAfk and preWaterInCar then
        LogManager.report(string.format(
            "AFK report: immediate flip/fix skipped for #%d (water detected pre-check)",
            id))
    end

    lua_thread.create(function()
        if not ReportCatchManager.isKerakliUnlocked() then
            return
        end

        local state = nil
        local seenKnown = false
        local seenInCar = false

        wait(350)
        for _ = 1, 24 do
            state = ReportCatchManager.getPlayerVehicleState(id)
            if state and state.known then
                seenKnown = true
            end
            if state and state.inCar then
                seenInCar = true
                if state.inWater or state.isFlipped or state.isBroken then
                    break
                end
            end
            wait(250)
        end

        local detectedWaterInCar = (state and state.inCar and state.inWater) or preWaterInCar
        local usedTpCarForWater = false

        if detectedWaterInCar and ReportCatchManager.isKerakliUnlocked() then
            local helpCmd = ReportCatchManager.buildAfkAdminHelpCommand(id)
            sampSendChat(helpCmd)
            LogManager.report(string.format("AFK report: water detected for #%d -> %s", id, helpCmd))

            local tpMode = "car"
            local tpStarted = false
            if SpectateQuickPanel and type(SpectateQuickPanel.sendTpCarRoad) == "function" then
                tpStarted = (SpectateQuickPanel.sendTpCarRoad(tpMode, id) == true)
            end

            if tpStarted then
                usedTpCarForWater = true
                recoveryAlreadySent = true
                LogManager.report(string.format(
                    "AFK report: TP CAR (%s) started for #%d after water detection",
                    tpMode, id))
                -- Allow TP CAR thread to run before any extra fallback.
                wait(850)
            else
                LogManager.report(string.format(
                    "AFK report: TP CAR start failed for #%d, fallback recovery will be used",
                    id))
                wait(500)
            end
        end

        local detectedFlip = state and state.inCar and state.isFlipped or false
        local detectedBroken = state and state.inCar and state.isBroken or false
        local needRecovery = detectedFlip or detectedBroken or (detectedWaterInCar and (not usedTpCarForWater))

        -- Oddiy holatda (AFK emas) text trigger recovery'ni kuchaytiradi.
        if not needRecovery and forceRecoveryByText and not localAfk then
            needRecovery = true
        end

        if not needRecovery and (not seenKnown or (localAfk and not seenInCar)) then
            needRecovery = true
            LogManager.report(string.format(
                "AFK report: vehicle state unavailable for #%d (known=%s inCar=%s localAfk=%s), recovery fallback enabled",
                id,
                tostring(seenKnown),
                tostring(seenInCar),
                tostring(localAfk)))
        end

        if needRecovery then
            if recoveryAlreadySent then
                LogManager.report(string.format(
                    "AFK report: recovery already sent for #%d, duplicate prevented",
                    id))
            else
                local attempts = 1
                ReportCatchManager.sendAfkRecoveryCommands(id, attempts, 550)
                recoveryAlreadySent = true
                LogManager.report(string.format(
                    "AFK report: recovery commands sent for #%d (flip=%s broken=%s forceByText=%s localAfk=%s)",
                    id,
                    tostring(detectedFlip),
                    tostring(detectedBroken),
                    tostring(forceRecoveryByText),
                    tostring(localAfk)))
            end
        else
            LogManager.report(string.format(
                "AFK report: no recovery needed for #%d (known=%s inCar=%s)",
                id,
                tostring(seenKnown),
                tostring(seenInCar)))
        end
    end)
end

function ReportCatchManager.handleAfkReportAuto(report, playerId)
    if not ReportCatchManager.isKerakliUnlocked() then
        return false
    end
    if not ReportCatchManager.settings.afkReportEnabled then
        return false
    end
    if not report or not playerId then
        return false
    end

    local matchedKeyword = ReportCatchManager.matchAfkReportKeyword(report.text or "")
    if not matchedKeyword then
        return false
    end

    local now = os.time()
    local cooldown = ReportCatchManager.getAfkReportCooldown()
    local last = tonumber(ReportCatchManager.afkReportLastByPlayer[playerId]) or 0
    if now - last < cooldown then
        LogManager.report(string.format(
            "AFK report skipped by cooldown for #%d (remaining %ds)",
            playerId,
            math.max(0, cooldown - (now - last))))
        return true
    end
    ReportCatchManager.afkReportLastByPlayer[playerId] = now

    local answerId = tonumber(report.id)
    local replyText = UtilityManager.trim(tostring(ReportCatchManager.settings.afkReportReplyText or ""))
    if replyText == "" then
        replyText = "Assalom alekum, kuzatyapman"
    end

    if answerId then
        sampSendChat(string.format("/ans %d %s", answerId, replyText))
        ReportCatchManager.markAnswered(answerId)
    end

    PlayerManager.spectate(playerId)
    ReportCatchManager.runAfkVehicleAutoActions(playerId, report.text or "")

    if answerId and ReportCatchManager.popupOpen and ReportCatchManager.currentReport and
       tonumber(ReportCatchManager.currentReport.id) == answerId then
        ReportCatchManager.closePopup()
    end

    LogManager.report(string.format(
        "AFK report auto handled: report #%s keyword '%s' -> player #%d",
        tostring(report.id),
        matchedKeyword,
        playerId))
    return true
end

function UtilityManager.hashSecret(text)
    local input = tostring(text or "")
    local h = 0x45D9F3B
    for i = 1, #input do
        local byte = string.byte(input, i) or 0
        h = (h * 131 + byte + i * 17) % 4294967296
    end
    h = (h + #input * 97) % 4294967296
    return string.format("%08x", h)
end

function ReportCatchManager.queueKeywordTp(report)
    if not ReportCatchManager.isMpUnlocked() then
        return
    end
    if not ReportCatchManager.settings.keywordTpEnabled then
        return
    end

    if not report then
        return
    end

    local trigger = ReportCatchManager.getKeywordTpTrigger()
    if trigger == "" then
        return
    end

    local reportText = tostring(report.text or ""):gsub("{%x%x%x%x%x%x}", "")
    reportText = UtilityManager.trim(reportText):lower()
    if reportText == "" then
        return
    end

    if not reportText:find(trigger, 1, true) then
        return
    end

    local targetId = tonumber(ReportCatchManager.resolveAutoActionPlayerId(report))
    if not targetId then
        return
    end

    local now = os.time()
    local cooldown = 10
    local lastTp = tonumber(ReportCatchManager.keywordTpLastByPlayer[targetId]) or 0
    if now - lastTp < cooldown then
        return
    end

    if ReportCatchManager.keywordTpQueuedPlayers[targetId] then
        return
    end

    table.insert(ReportCatchManager.keywordTpQueue, {
        playerId = targetId,
        reportId = tonumber(report.id) or 0,
        nick = tostring(report.nick or "Unknown")
    })
    ReportCatchManager.keywordTpQueuedPlayers[targetId] = true
    LogManager.report(string.format(
        "Keyword TP queued: report #%d from %s -> player #%d",
        tonumber(report.id) or 0,
        tostring(report.nick or "Unknown"),
        targetId))

    -- Run immediately to avoid delayed gethere after keyword match.
    ReportCatchManager.processKeywordTpQueue(true)
end

function ReportCatchManager.processKeywordTpQueue(forceImmediate)
    if (not ReportCatchManager.settings.keywordTpEnabled) or (not ReportCatchManager.isMpUnlocked()) then
        if #ReportCatchManager.keywordTpQueue > 0 or next(ReportCatchManager.keywordTpQueuedPlayers) ~= nil then
            ReportCatchManager.keywordTpQueue = {}
            ReportCatchManager.keywordTpQueuedPlayers = {}
        end
        return
    end

    if #ReportCatchManager.keywordTpQueue == 0 then
        return
    end

    local nowClock = os.clock()
    if not forceImmediate and nowClock - ReportCatchManager.keywordTpLastProcessAt < 0.6 then
        return
    end

    local nextTp = table.remove(ReportCatchManager.keywordTpQueue, 1)
    if not nextTp then
        return
    end
    ReportCatchManager.keywordTpQueuedPlayers[nextTp.playerId] = nil

    local now = os.time()
    local cooldown = 10
    local lastTp = tonumber(ReportCatchManager.keywordTpLastByPlayer[nextTp.playerId]) or 0
    if now - lastTp < cooldown then
        return
    end

    if sampIsPlayerConnected and not sampIsPlayerConnected(nextTp.playerId) then
        LogManager.report(string.format(
            "Keyword TP skipped: player #%d is offline",
            nextTp.playerId))
        return
    end

    local answerId = tonumber(nextTp.reportId) or 0
    if answerId > 0 then
        sampSendChat(string.format("/ans %d Assalom alekum, hozir tp bo'lasiz", answerId))
        ReportCatchManager.markAnswered(answerId)
    end

    -- Immediate order required: first /ans, then /gethere without extra delay.
    PlayerManager.bring(nextTp.playerId)
    ReportCatchManager.markKeywordTp(nextTp.playerId)
    ReportCatchManager.keywordTpLastProcessAt = nowClock
    LogManager.report(string.format(
        "Keyword gethere executed: report #%d (%s) -> player #%d (preAns=%s)",
        answerId,
        tostring(nextTp.nick or "Unknown"),
        nextTp.playerId,
        answerId > 0 and "yes" or "no"))
end

function ReportCatchManager.applyAutoActions(report)
    if not report then
        return
    end

    local targetId = tonumber(ReportCatchManager.resolveAutoActionPlayerId(report))
    if targetId and ReportCatchManager.handleAfkReportAuto(report, targetId) then
        return
    end

    ReportCatchManager.queueKeywordTp(report)

    if not targetId then
        return
    end

    if ReportCatchManager.settings.autoTP then
        PlayerManager.teleportTo(targetId)
        ReportCatchManager.markKeywordTp(targetId)
    end
    if ReportCatchManager.settings.autoSP then
        PlayerManager.spectate(targetId)
    end
end

function ReportCatchManager.processReport(text)
    local popupEnabled = ReportCatchManager.enabled
    local autoEnabled = ReportCatchManager.shouldRunAutoActions()
    if not popupEnabled and not autoEnabled then
        return false
    end
    local cleanText = text:gsub("{%x%x%x%x%x%x}", ""):gsub("^%s+", "")

    -- Grand Mobile report format:
    -- Nick[ID]: message [Hisobotlar soni: N]
    local gmNick, gmPlayerId, gmText, gmCount =
        cleanText:match("^([%w_]+)%[(%d+)%]:%s*(.-)%s*%[[Hh]isobotlar%s+soni:%s*(%d+)%]$")
    if gmNick and gmPlayerId then
        local reportId = tonumber(gmPlayerId) or tonumber(os.time() % 100000)
        if ReportCatchManager.isDuplicate(reportId, gmNick) then
            LogManager.security(string.format("Duplicate report ignored: #%d from %s", reportId, gmNick))
            return true
        end

        local report = {
            id = reportId,
            nick = gmNick,
            text = gmText or "",
            time = os.time(),
            formattedTime = os.date("%H:%M:%S"),
            playerId = tonumber(gmPlayerId),
            reportCount = tonumber(gmCount) or 0
        }

        if popupEnabled and ReportCatchManager.shouldIgnoreIncoming(report) then
            return true
        end

        LogManager.report(string.format("Caught GM report from %s[%d]: %s",
            gmNick, reportId, report.text:sub(1, 40)))

        if popupEnabled then
            ReportCatchManager.showReport(report)
        end
        if autoEnabled then
            ReportCatchManager.applyAutoActions(report)
        end

        return true
    end

    for _, pattern in ipairs(ReportCatchManager.reportPatterns) do
        local c1, c2, c3 = cleanText:match(pattern)
        if c1 then
            local id, nick, reportText
            if c3 then
                id = tonumber(c1)
                nick = c2
                reportText = c3
            else
                nick = c1
                reportText = c2 or ""
            end
            if not id then
                id = tonumber(os.time() % 100000)
            end

            if ReportCatchManager.isDuplicate(id, nick) then
                LogManager.security(string.format("Duplicate report ignored: #%d from %s", id, nick))
                return true
            end

            local report = {
                id = id,
                nick = nick,
                text = reportText or "",
                time = os.time(),
                formattedTime = os.date("%H:%M:%S"),
                playerId = ReportCatchManager.getPlayerIdByNick(nick)
            }

            if popupEnabled and ReportCatchManager.shouldIgnoreIncoming(report) then
                return true
            end

            LogManager.report(string.format("Caught report #%d from %s: %s", id, nick, report.text:sub(1, 30)))

            if popupEnabled then
                ReportCatchManager.showReport(report)
            end
            if autoEnabled then
                ReportCatchManager.applyAutoActions(report)
            end

            return true
        end
    end

    -- Generic fallback for many server formats: "#123 Nick: message"
    local id, nick, reportText = cleanText:match("#(%d+)%s+(%S+)%s*:%s*(.+)")
    if id and nick then
        local report = {
            id = tonumber(id) or tonumber(os.time() % 100000),
            nick = nick,
            text = reportText or "",
            time = os.time(),
            formattedTime = os.date("%H:%M:%S"),
            playerId = ReportCatchManager.getPlayerIdByNick(nick)
        }
        if popupEnabled and ReportCatchManager.shouldIgnoreIncoming(report) then
            return true
        end
        if popupEnabled then
            ReportCatchManager.showReport(report)
        end
        if autoEnabled then
            ReportCatchManager.applyAutoActions(report)
        end
        return true
    end

    return false
end

function ReportCatchManager.getPlayerIdByNick(nick)
    for i = 0, sampGetMaxPlayerId(false) do
        if sampIsPlayerConnected(i) then
            if sampGetPlayerNickname(i) == nick then
                return i
            end
        end
    end
    return nil
end

function ReportCatchManager.resolveReporterPlayerId(report)
    if not report then return nil end

    local playerId = tonumber(report.playerId)
    if playerId and sampIsPlayerConnected(playerId) then
        return playerId
    end

    local nick = report.nick or ""
    if nick ~= "" then
        local byNick = ReportCatchManager.getPlayerIdByNick(nick)
        if byNick then
            return byNick
        end
    end

    if playerId then
        return playerId
    end

    local fallbackId = tonumber(report.id)
    if fallbackId then
        return fallbackId
    end

    return nil
end

function ReportCatchManager.extractMentionedPlayerIdFromText(report)
    if not report then
        return nil
    end

    local text = (report.text or ""):gsub("{%x%x%x%x%x%x}", "")
    text = UtilityManager.trim(text)
    if text == "" then
        return nil
    end

    local reporterId = tonumber(ReportCatchManager.resolveReporterPlayerId(report))
    local maxPlayerId = 1000
    if sampGetMaxPlayerId then
        local ok, value = pcall(sampGetMaxPlayerId, false)
        if ok and tonumber(value) then
            maxPlayerId = tonumber(value)
        end
    end

    local seen = {}
    local function pickIfValid(rawId)
        local id = tonumber(rawId)
        if not id then
            return nil
        end
        if id < 0 or id > maxPlayerId then
            return nil
        end
        if reporterId and id == reporterId then
            return nil
        end
        if seen[id] then
            return nil
        end
        seen[id] = true

        if sampIsPlayerConnected and sampIsPlayerConnected(id) then
            return id
        end
        return nil
    end

    for raw in text:gmatch("[Ii][Dd]%s*[:=#%-]?%s*(%d+)") do
        local id = pickIfValid(raw)
        if id then return id end
    end

    for raw in text:gmatch("%[(%d+)%]") do
        local id = pickIfValid(raw)
        if id then return id end
    end

    for raw in text:gmatch("#(%d+)") do
        local id = pickIfValid(raw)
        if id then return id end
    end

    for raw in text:gmatch("%d+") do
        local id = pickIfValid(raw)
        if id then return id end
    end

    return nil
end

function ReportCatchManager.resolveMentionedPlayer(report)
    if not report then
        return nil
    end

    local cachedId = tonumber(report.mentionedPlayerId)
    if cachedId and sampIsPlayerConnected and sampIsPlayerConnected(cachedId) then
        report.mentionedPlayerNick = sampGetPlayerNickname(cachedId) or ""
        return cachedId
    end

    local extractedId = ReportCatchManager.extractMentionedPlayerIdFromText(report)
    if extractedId then
        report.mentionedPlayerId = extractedId
        report.mentionedPlayerNick = sampGetPlayerNickname(extractedId) or ""
        return extractedId
    end

    report.mentionedPlayerId = nil
    report.mentionedPlayerNick = ""
    return nil
end

function ReportCatchManager.spectateMentionedPlayerFromReport()
    local report = ReportCatchManager.currentReport
    if not report then return end

    local mentionedId = ReportCatchManager.resolveMentionedPlayer(report)
    if not mentionedId then
        sampAddChatMessage("[Report Catch] Reportdagi ID topilmadi yoki player online emas.", 0xFF6666)
        return
    end

    local answerId = tonumber(report.id)
    if answerId then
        sampSendChat(string.format("/ans %d Assalomu alaykum, o'yinchini kuzatyapman", answerId))
        ReportCatchManager.markAnswered(answerId)
    else
        sampAddChatMessage("[Report Catch] /ans uchun report ID topilmadi.", 0xFF6666)
    end

    PlayerManager.spectate(mentionedId)
    if answerId then
        SpectateQuickPanel.enableReportReviewMode(answerId)
    end

    LogManager.report(string.format("Report mention spectate started: report #%s -> player #%d", tostring(report.id), mentionedId))
    ReportCatchManager.closePopup()
end

function ReportCatchManager.showReport(report)
    local screenX = select(1, getScreenResolution()) or 1920
    local defaultX = math.max(10, screenX - (ReportCatchManager.settings.popupSize.width + 30))
    ReportCatchManager.settings.popupPos.x = defaultX
    ReportCatchManager.settings.popupPos.y = 120

    report.mentionedPlayerId = ReportCatchManager.extractMentionedPlayerIdFromText(report)
    if report.mentionedPlayerId then
        report.mentionedPlayerNick = sampGetPlayerNickname(report.mentionedPlayerId) or ""
    else
        report.mentionedPlayerNick = ""
    end

    ReportCatchManager.currentReport = report
    ReportCatchManager.popupOpen = true
    ReportCatchManager.setWaitingReport(report)
    ReportCatchManager.animationProgress = 0
    imgui.Process = true
    imgui.ShowCursor = true

    if SettingsManager.get("soundEnabled") and ReportCatchManager.settings.soundEnabled then
        print("\a[Report Catch] NEW REPORT!")
    end

    LogManager.report(string.format("Popup shown for report #%d", report.id))
end

function ReportCatchManager.closePopup()
    -- Closing popup means current report is skipped/finished for strict lock mode.
    ReportCatchManager.clearWaitingReport()
    ReportCatchManager.reportQueue = {}
    ReportCatchManager.popupOpen = false
    ReportCatchManager.currentReport = nil
    ReportCatchManager.animationProgress = 0
    local uiOpen = MainUI and MainUI.window and MainUI.window.open or false
    imgui.Process = uiOpen
    imgui.ShowCursor = uiOpen
end

function ReportCatchManager.clearQueue()
    ReportCatchManager.reportQueue = {}
    LogManager.system("Report queue cleared")
end

function ReportCatchManager.getQueueCount()
    return #ReportCatchManager.reportQueue
end

function ReportCatchManager.sendReply(templateId)
    local report = ReportCatchManager.currentReport
    if not report then return end

    local template = nil
    for _, t in ipairs(ReportCatchManager.templates) do
        if t.id == templateId then
            template = t
            break
        end
    end

    if template then
        local answeredReportId = report.id
        local cmd = string.format("/ans %d %s", answeredReportId, template.text)
        sampSendChat(cmd)
        LogManager.report(string.format("Reply sent to report #%d: %s", answeredReportId, template.text))

        if template.id == 1 or template.autoSpReporter then
            local targetId = ReportCatchManager.resolveReporterPlayerId(report)
            if targetId then
                PlayerManager.spectate(targetId)
                LogManager.report(string.format("Auto spectate (/sp) for reporter #%d via template #%d", targetId, template.id))
            else
                sampAddChatMessage("[Report Catch] /sp uchun reporter ID topilmadi.", 0xFF6666)
            end
        end

        -- Close popup right after handling a template reply.
        ReportCatchManager.markAnswered(answeredReportId)
        if ReportCatchManager.popupOpen and ReportCatchManager.currentReport and
           tonumber(ReportCatchManager.currentReport.id) == tonumber(answeredReportId) then
            ReportCatchManager.closePopup()
        end
    end
end

function ReportCatchManager.teleportToReporter()
    if not ReportCatchManager.currentReport then return end
    local playerId = ReportCatchManager.currentReport.playerId
    if playerId then
        PlayerManager.teleportTo(playerId)
        LogManager.report(string.format("Teleported to reporter #%d", playerId))
    end
end

function ReportCatchManager.spectateReporter()
    if not ReportCatchManager.currentReport then return end
    local playerId = ReportCatchManager.currentReport.playerId
    if playerId then
        PlayerManager.spectate(playerId)
        LogManager.report(string.format("Spectating reporter #%d", playerId))
    end
end

function ReportCatchManager.getInfoReporter()
    if not ReportCatchManager.currentReport then return end
    local playerId = ReportCatchManager.resolveReporterPlayerId(ReportCatchManager.currentReport)
    if playerId then
        sampSendChat(string.format("/getinfo %d", playerId))
        LogManager.report(string.format("Requested getinfo for player #%d", playerId))
    end
end

function ReportCatchManager.requestPunishmentsFor(reportId, playerId, nick, sourceTag)
    local resolvedPlayerId = tonumber(playerId)
    local resolvedReportId = tonumber(reportId)
    local resolvedNick = tostring(nick or "")
    local startedAtMs = ReportCatchManager.getNowMs()
    local source = tostring(sourceTag or "unknown")

    if not resolvedPlayerId then
        sampAddChatMessage("[Report Catch] Jazolar: o'yinchi ID topilmadi.", 0xFF6666)
        return false
    end

    ReportCatchManager.pendingPunishmentCheck = {
        reportId = resolvedReportId,
        playerId = resolvedPlayerId,
        answerTargetId = resolvedReportId or resolvedPlayerId,
        nick = resolvedNick,
        startedAtMs = startedAtMs,
        lastRelatedAtMs = 0,
        relatedSeen = false,
        hasPunishment = false,
        details = {},
        contextExpireAtMs = startedAtMs + 3000
    }

    sampSendChat(string.format("/getinfo %d", resolvedPlayerId))
    sampAddChatMessage(string.format("[Report Catch] Jazolar tekshiruvi boshlandi: player #%d, report #%s",
        resolvedPlayerId, tostring(resolvedReportId or 0)), 0x33CCFF)
    LogManager.report(string.format(
        "Punishment check started (%s) for player #%d (report #%s)",
        source, resolvedPlayerId, tostring(resolvedReportId or 0)))
    return true
end

function ReportCatchManager.requestPunishmentsReporter()
    if not ReportCatchManager.currentReport then return end

    local report = ReportCatchManager.currentReport
    local reportId = report.id
    local playerId = ReportCatchManager.resolveReporterPlayerId(report)
    local nick = report.nick or ""
    ReportCatchManager.requestPunishmentsFor(reportId, playerId, nick, "report_popup")
end

function ReportCatchManager.getNowMs()
    if type(getTickCount) == "function" then
        local ok, value = pcall(getTickCount)
        if ok and type(value) == "number" then
            return value
        end
    end
    return math.floor(os.clock() * 1000)
end

function ReportCatchManager.sendHelpRequest()
    local report = ReportCatchManager.currentReport
    if not report then return end

    local playerId = ReportCatchManager.resolveReporterPlayerId(report)
    local answerId = tonumber(report.id)
    if not playerId then
        sampAddChatMessage("[Report Catch] HELP: o'yinchi ID topilmadi.", 0xFF6666)
        return
    end
    if not answerId then
        sampAddChatMessage("[Report Catch] HELP: report ID topilmadi.", 0xFF6666)
        return
    end

    local reportText = (report.text or ""):gsub("{%x%x%x%x%x%x}", "")
    reportText = reportText:gsub("[\r\n]+", " "):gsub("%s%s+", " ")
    reportText = UtilityManager.trim(reportText)
    if reportText == "" then
        reportText = "(report matni yo'q)"
    end

    local helpPayload = string.format("help(%d) %s", playerId, reportText)

    if type(setClipboardText) == "function" then
        pcall(setClipboardText, helpPayload)
    end

    sampSendChat("/a " .. helpPayload)
    sampSendChat(string.format("/ans %d Assalom alekum, kuting", answerId))
    LogManager.report(string.format("Help request sent to admin chat for player #%d", playerId))
end

function ReportCatchManager.sendNavigatorPoint()
    local report = ReportCatchManager.currentReport
    if not report then
        sampAddChatMessage("[Report Catch] NAVIGATOR: report topilmadi.", 0xFF6666)
        return
    end

    local answerId = tonumber(report.id)
    if not answerId then
        sampAddChatMessage("[Report Catch] NAVIGATOR: report ID topilmadi.", 0xFF6666)
        return
    end

    if NavigatorManager.startForTarget(answerId, "report_popup") then
        LogManager.report(string.format("Navigator requested from report popup for answer #%d", answerId))
    end
end

function ReportCatchManager.normalizeServerText(text)
    local cleaned = (text or ""):gsub("{%x%x%x%x%x%x}", "")
    return UtilityManager.trim(cleaned)
end

function ReportCatchManager.stripTimestampPrefix(text)
    local value = tostring(text or "")
    value = value:gsub("^%s*%[%d%d:%d%d:%d%d%]%s*", "")
    return UtilityManager.trim(value)
end

function ReportCatchManager.getPunishmentLineVariants(text)
    local variants = UtilityManager.getMatchVariants(text or "")
    if #variants == 0 then
        table.insert(variants, tostring(text or ""))
    end
    return variants
end

function ReportCatchManager.isAdminNoisePunishmentLine(cleanText)
    local line = ReportCatchManager.stripTimestampPrefix(cleanText)
    if line == "" then
        return false
    end

    local textVariants = ReportCatchManager.getPunishmentLineVariants(line)
    local noiseKeywords = {
        "<adm>", "ga javob berdi", "ga javob berdi:", "ответил", "ответила", "ответил:",
        "administrator", "администратор", "administratori"
    }
    if ReportCatchManager.containsKeywordInVariants(textVariants, noiseKeywords) then
        return true
    end

    for _, value in ipairs(textVariants) do
        local source = tostring(value or "")
        if source:match("^%s*%[a%]") or source:match("^%s*%<adm%>") then
            return true
        end
        if source:match("^[%w_]+%[%d+%]%s*:") then
            return true
        end
    end

    return false
end

function ReportCatchManager.isGetinfoContextLine(cleanText, pending)
    local line = ReportCatchManager.stripTimestampPrefix(cleanText)
    if line == "" then
        return false
    end

    local variants = ReportCatchManager.getPunishmentLineVariants(line)
    local contextKeywords = {
        "hisob qaytnomasi", "hisob qaydnomasi", "tahallus",
        "faol o'yinchi penaltilari", "faol oyinchi penaltilari",
        "penalti", "account", "akkaunt", "id:"
    }

    if ReportCatchManager.containsKeywordInVariants(variants, contextKeywords) then
        return true
    end

    if pending then
        local playerId = tostring(pending.playerId or "")
        if playerId ~= "" then
            for _, value in ipairs(variants) do
                local source = tostring(value or "")
                if source:find("[" .. playerId .. "]", 1, true) then
                    return true
                end
                if source:match("[Ii][Dd]%s*[:=]?%s*" .. playerId) then
                    return true
                end
            end
        end

        local nick = UtilityManager.trim(tostring(pending.nick or ""))
        if nick ~= "" then
            local nickVariants = ReportCatchManager.getPunishmentLineVariants(nick)
            for _, value in ipairs(variants) do
                local source = tostring(value or "")
                for _, nickValue in ipairs(nickVariants) do
                    local nickSource = tostring(nickValue or "")
                    if nickSource ~= "" and source:find(nickSource, 1, true) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

function ReportCatchManager.expandKeywordVariants(keywords)
    local expanded = {}
    local seen = {}

    for _, rawKeyword in ipairs(keywords or {}) do
        local keyword = UtilityManager.trim(tostring(rawKeyword or ""))
        if keyword ~= "" then
            local keywordVariants = ReportCatchManager.getPunishmentLineVariants(keyword)
            for _, value in ipairs(keywordVariants) do
                local source = UtilityManager.trim(tostring(value or ""))
                if source ~= "" then
                    local candidates = {
                        source,
                        source:lower(),
                        UtilityManager.casefoldUtf8Cyrillic(source),
                        UtilityManager.casefoldCp1251Cyrillic(source)
                    }
                    for _, candidate in ipairs(candidates) do
                        local prepared = UtilityManager.trim(tostring(candidate or ""))
                        if prepared ~= "" and not seen[prepared] then
                            seen[prepared] = true
                            table.insert(expanded, prepared)
                        end
                    end
                end
            end
        end
    end

    return expanded
end

function ReportCatchManager.containsKeywordInVariants(variants, keywords)
    local preparedKeywords = ReportCatchManager.expandKeywordVariants(keywords)
    if #preparedKeywords == 0 then
        return false
    end

    for _, value in ipairs(variants or {}) do
        local source = tostring(value or "")
        local candidates = {
            source:lower(),
            UtilityManager.casefoldUtf8Cyrillic(source),
            UtilityManager.casefoldCp1251Cyrillic(source)
        }
        for _, candidate in ipairs(candidates) do
            for _, keyword in ipairs(preparedKeywords) do
                if candidate:find(keyword, 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

function ReportCatchManager.extractNumberNearKeyword(line, keyword)
    local source = tostring(line or "")
    local key = tostring(keyword or "")
    if source == "" or key == "" then
        return nil
    end

    local keyVariants = ReportCatchManager.expandKeywordVariants({ key })
    if #keyVariants == 0 then
        keyVariants = { key }
    end

    for _, keyVariant in ipairs(keyVariants) do
        local escapedKey = tostring(keyVariant):gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
        local patterns = {
            escapedKey .. "%s*[:=|%-]*%s*(-?%d+)",
            escapedKey .. "[^%d%-]+(-?%d+)",
            "(-?%d+)%s*[/|,%-]%s*" .. escapedKey,
            "(-?%d+)%s+" .. escapedKey
        }

        for _, pattern in ipairs(patterns) do
            for raw in source:gmatch(pattern) do
                local value = tonumber(raw)
                if value ~= nil then
                    return value
                end
            end
        end
    end

    return nil
end

function ReportCatchManager.isRelatedPunishmentLine(cleanText, pending)
    local line = ReportCatchManager.stripTimestampPrefix(cleanText)
    if line == "" then
        return false
    end

    if ReportCatchManager.isAdminNoisePunishmentLine(line) then
        return false
    end

    local textVariants = ReportCatchManager.getPunishmentLineVariants(line)
    local relatedKeywords = {
        "hisob qaytnomasi", "hisob qaydnomasi", "akk raqam", "akkaunt", "account", "getinfo",
        "jazo", "jazo", "naqaz", "nakaz", "наказ", "огранич",
        "demorgan", "ban", "tempban", "бан",
        "warn", "varn", "варн", "ogohl", "предупрежд",
        "jail", "qamoq", "qamok", "тюр", "prison",
        "mute", "мут", "rmute", "runmute", "chatban", "voiceban",
        "yo'q", "yoq", "mavjud emas", "none", "нет", "нету", "отсутств", "не имеется"
    }

    return ReportCatchManager.containsKeywordInVariants(textVariants, relatedKeywords)
end

function ReportCatchManager.sanitizePunishmentDetail(detail, pending)
    local text = detail or ""
    text = text:gsub("{%x%x%x%x%x%x}", "")

    if pending.nick and pending.nick ~= "" then
        text = text:gsub(pending.nick, "")
    end

    local playerId = tostring(pending.playerId or "")
    if playerId ~= "" then
        text = text:gsub("%[" .. playerId .. "%]", "")
        text = text:gsub("[Ii][Dd]%s*[:=]?%s*" .. playerId, "")
    end

    text = text:gsub("[Hh][Ii][Ss][Oo][Bb]%s+[Qq][Aa][Yy][Tt][Nn][Oo][Mm][Aa][Ss][Ii]", "")
    text = text:gsub("[Hh][Ii][Ss][Oo][Bb]%s+[Qq][Aa][Yy][Dd][Nn][Oo][Mm][Aa][Ss][Ii]", "")
    text = text:gsub("[Aa][Kk][Kk][Aa]?[Uu]?[Nn]?[Tt]?%s*[Rr]?[Aa]?[Qq]?[Aa]?[Mm]?[Ii]?%s*[:=]?%s*[%w_%-]+", "")
    text = text:gsub("[Aa][Cc][Cc][Oo][Uu][Nn][Tt]%s*[:=]?%s*[%w_%-]+", "")
    text = text:gsub("^%s*[-,:;|]+", "")
    text = text:gsub("[-,:;|]+%s*$", "")
    text = text:gsub("%s%s+", " ")

    return UtilityManager.trim(text)
end

function ReportCatchManager.extractPunishmentFromLine(cleanText, pending)
    local line = ReportCatchManager.stripTimestampPrefix(cleanText)
    local variants = ReportCatchManager.getPunishmentLineVariants(line)
    local directLineKeywords = {
        "jail", "warn", "mute", "rmute", "runmute",
        "qamoq", "qamok", "ogohl",
        "тюр", "варн", "мут", "предупрежд"
    }
    local punishmentKeywords = {
        "jazo", "naqaz", "nakaz", "наказ", "огранич",
        "ban", "tempban", "бан", "demorgan",
        "warn", "varn", "варн", "ogohl", "предупрежд",
        "jail", "qamoq", "qamok", "тюр", "prison",
        "mute", "mut", "мут", "rmute", "runmute", "chatban", "voiceban"
    }
    local noPunishmentKeywords = {
        "yo'q", "yoq", "mavjud emas", "none", "нет", "нету", "отсутств", "не имеется"
    }

    -- User requirement: if /getinfo line contains jail/warn/mute anywhere, send that full line.
    if ReportCatchManager.containsKeywordInVariants(variants, directLineKeywords) then
        local fullLine = UtilityManager.trim(line)
        if fullLine ~= "" then
            return fullLine, true
        end
    end

    local hasKeyword = ReportCatchManager.containsKeywordInVariants(variants, punishmentKeywords)
    if not hasKeyword then
        return nil, false
    end

    local numericKeywordTokens = {
        "jazo", "nakaz", "наказ", "огранич",
        "ban", "tempban", "бан", "demorgan",
        "warn", "varn", "варн", "ogohl", "предупрежд",
        "jail", "qamoq", "qamok", "тюр", "prison",
        "mute", "мут", "rmute", "runmute", "chatban", "voiceban"
    }

    local foundNumber = false
    local hasNonZero = false
    for _, source in ipairs(variants) do
        local sourceText = tostring(source or "")
        local scanCandidates = {
            sourceText,
            UtilityManager.casefoldUtf8Cyrillic(sourceText),
            UtilityManager.casefoldCp1251Cyrillic(sourceText)
        }

        for _, line in ipairs(scanCandidates) do
            for _, token in ipairs(numericKeywordTokens) do
                local value = ReportCatchManager.extractNumberNearKeyword(line, token)
                if value ~= nil then
                    foundNumber = true
                    if value > 0 then
                        hasNonZero = true
                        break
                    end
                end
            end
            if hasNonZero then
                break
            end
        end
        if hasNonZero then
            break
        end
    end

    if not hasNonZero then
        local hasNoPunishmentText = ReportCatchManager.containsKeywordInVariants(variants, noPunishmentKeywords)
        if foundNumber or hasNoPunishmentText then
            return nil, false
        end
    end

    -- User requirement: if warn/jail exists, send that line text (cleaned from nick/id/account).
    local detailText = ReportCatchManager.sanitizePunishmentDetail(line, pending)
    if detailText == "" then
        detailText = UtilityManager.trim(line)
    end

    if detailText == "" then
        return nil, false
    end

    return detailText, true
end

function ReportCatchManager.addPunishmentDetail(pending, detailText)
    local text = UtilityManager.trim(detailText or "")
    if text == "" then return end

    for _, existing in ipairs(pending.details) do
        if existing == text then
            return
        end
    end

    table.insert(pending.details, text)
end

function ReportCatchManager.processPunishmentInfoMessage(text)
    local pending = ReportCatchManager.pendingPunishmentCheck
    if not pending then
        return false
    end

    local cleanText = ReportCatchManager.normalizeServerText(text)
    if cleanText == "" then
        return false
    end

    if ReportCatchManager.isAdminNoisePunishmentLine(cleanText) then
        return false
    end

    local nowMs = ReportCatchManager.getNowMs()
    if ReportCatchManager.isGetinfoContextLine(cleanText, pending) then
        pending.relatedSeen = true
        pending.lastRelatedAtMs = nowMs
        pending.contextExpireAtMs = math.max(tonumber(pending.contextExpireAtMs) or 0, nowMs + 3500)
    end

    local contextExpireAtMs = tonumber(pending.contextExpireAtMs) or 0
    if nowMs > contextExpireAtMs then
        return false
    end

    if not ReportCatchManager.isRelatedPunishmentLine(cleanText, pending) then
        return false
    end

    pending.relatedSeen = true
    pending.lastRelatedAtMs = nowMs

    local detailText, isNonZero = ReportCatchManager.extractPunishmentFromLine(cleanText, pending)
    if detailText and isNonZero then
        ReportCatchManager.addPunishmentDetail(pending, detailText)
    end
    if isNonZero then
        pending.hasPunishment = true
    end

    return true
end

function ReportCatchManager.processPunishmentDialogTextBlock(rawText)
    local pending = ReportCatchManager.pendingPunishmentCheck
    if not pending then
        return false
    end

    local text = tostring(rawText or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    if UtilityManager.trim(text) == "" then
        return false
    end

    local nowMs = ReportCatchManager.getNowMs()
    local lines = UtilityManager.splitString(text, "\n")
    local processedAny = false

    for _, rawLine in ipairs(lines) do
        local cleanLine = ReportCatchManager.normalizeServerText(rawLine)
        if cleanLine ~= "" then
            if not ReportCatchManager.isAdminNoisePunishmentLine(cleanLine) then
                if ReportCatchManager.isGetinfoContextLine(cleanLine, pending) then
                    pending.relatedSeen = true
                    pending.lastRelatedAtMs = nowMs
                    pending.contextExpireAtMs = math.max(tonumber(pending.contextExpireAtMs) or 0, nowMs + 3500)
                    processedAny = true
                end

                if ReportCatchManager.isRelatedPunishmentLine(cleanLine, pending) then
                    pending.relatedSeen = true
                    pending.lastRelatedAtMs = nowMs
                    processedAny = true

                    local detailText, isNonZero = ReportCatchManager.extractPunishmentFromLine(cleanLine, pending)
                    if detailText and isNonZero then
                        ReportCatchManager.addPunishmentDetail(pending, detailText)
                    end
                    if isNonZero then
                        pending.hasPunishment = true
                    end
                end
            end
        end
    end

    return processedAny
end

function ReportCatchManager.processPunishmentInfoDialog(dialogId, style, title, button1, button2, text)
    local pending = ReportCatchManager.pendingPunishmentCheck
    if not pending then
        return false
    end

    local titleText = ReportCatchManager.normalizeServerText(title or "")
    local bodyText = tostring(text or "")
    if titleText == "" and UtilityManager.trim(bodyText) == "" then
        return false
    end

    local processedFromTitle = ReportCatchManager.processPunishmentDialogTextBlock(titleText)
    local processedFromBody = ReportCatchManager.processPunishmentDialogTextBlock(bodyText)

    if processedFromTitle or processedFromBody then
        -- Dialog carries full /getinfo snapshot; finalize immediately to avoid fallback "no punishments".
        ReportCatchManager.finalizePunishmentCheck(true)
        return true
    end

    return false
end

function ReportCatchManager.finalizePunishmentCheck(force)
    local pending = ReportCatchManager.pendingPunishmentCheck
    if not pending then
        return
    end

    local nowMs = ReportCatchManager.getNowMs()

    if not force then
        if not pending.relatedSeen then
            return
        end
        local startedAtMs = tonumber(pending.startedAtMs) or nowMs
        local lastRelatedAtMs = tonumber(pending.lastRelatedAtMs) or 0
        if (nowMs - lastRelatedAtMs) < 1200 and (nowMs - startedAtMs) < 8000 then
            return
        end
    end

    if force and not pending.relatedSeen then
        LogManager.report("Punishment check timeout: no getinfo lines detected, sending no-punishment fallback")
    end

    local replyText
    if #pending.details > 0 then
        replyText = "Assalomu alaykum, " .. table.concat(pending.details, "; ")
    else
        replyText = "Assalomu alaykum, sizda jazolar yo'q"
    end

    local answerCommandTargetId = tonumber(pending.answerTargetId) or tonumber(pending.reportId) or tonumber(pending.playerId)
    local resolvedReportId = tonumber(pending.reportId) or answerCommandTargetId
    if not answerCommandTargetId then
        LogManager.security("Punishment reply aborted: invalid report/player ID")
        ReportCatchManager.pendingPunishmentCheck = nil
        return
    end
    sampSendChat(string.format("/ans %d %s", answerCommandTargetId, replyText))
    LogManager.report(string.format(
        "Punishment reply sent: /ans %d (report #%s): %s",
        answerCommandTargetId,
        tostring(resolvedReportId or 0),
        replyText))
    ReportCatchManager.pendingPunishmentCheck = nil
    ReportCatchManager.markAnswered(resolvedReportId)
    if ReportCatchManager.popupOpen and ReportCatchManager.currentReport and
       tonumber(ReportCatchManager.currentReport.id) == tonumber(resolvedReportId) then
        ReportCatchManager.closePopup()
    end
end

function ReportCatchManager.updatePendingPunishmentCheck()
    local pending = ReportCatchManager.pendingPunishmentCheck
    if not pending then
        return
    end

    local nowMs = ReportCatchManager.getNowMs()
    local startedAtMs = tonumber(pending.startedAtMs) or nowMs
    if (nowMs - startedAtMs) >= 8000 then
        ReportCatchManager.finalizePunishmentCheck(true)
        return
    end

    ReportCatchManager.finalizePunishmentCheck(false)
end

function ReportCatchManager.addTemplate(text, shortcut)
    table.insert(ReportCatchManager.templates, {
        id = #ReportCatchManager.templates + 1,
        text = text,
        shortcut = shortcut or ""
    })
end

function ReportCatchManager.removeTemplate(id)
    for i, template in ipairs(ReportCatchManager.templates) do
        if template.id == id then
            table.remove(ReportCatchManager.templates, i)
            for j = i, #ReportCatchManager.templates do
                ReportCatchManager.templates[j].id = j
            end
            return true
        end
    end
    return false
end

function ReportCatchManager.renderPopup()
    if not ReportCatchManager.popupOpen or not ReportCatchManager.currentReport then
        return
    end

    local report = ReportCatchManager.currentReport
    local settings = ReportCatchManager.settings

    -- Keep enough height so Quick Actions (including JAZOLAR/HELP) remain visible on scaled UI.
    local templateRows = math.max(1, math.ceil(#ReportCatchManager.templates / 4))
    local minPopupHeight = 360 + math.max(0, templateRows - 2) * 34
    if (settings.popupSize.height or 0) < minPopupHeight then
        settings.popupSize.height = minPopupHeight
    end

    if settings.animationEnabled then
        ReportCatchManager.animationProgress = math.min(1, ReportCatchManager.animationProgress + 0.1)
    else
        ReportCatchManager.animationProgress = 1
    end

    local screenX, screenY = getScreenResolution()
    screenX = screenX or 1920
    screenY = screenY or 1080
    local maxX = math.max(0, screenX - settings.popupSize.width - 10)
    local maxY = math.max(0, screenY - settings.popupSize.height - 10)
    settings.popupPos.x = UtilityManager.clamp(settings.popupPos.x or 100, 10, maxX)
    settings.popupPos.y = UtilityManager.clamp(settings.popupPos.y or 100, 10, maxY)

    local startX = screenX
    local targetX = settings.popupPos.x
    local currentX = targetX + (startX - targetX) * (1 - ReportCatchManager.animationProgress)

    imgui.SetNextWindowPos(imgui.ImVec2(currentX, settings.popupPos.y), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(settings.popupSize.width, settings.popupSize.height), imgui.Cond.Always)

    local flags = imgui.WindowFlags.NoCollapse +
                  imgui.WindowFlags.NoResize +
                  imgui.WindowFlags.NoScrollbar +
                  imgui.WindowFlags.AlwaysAutoResize

    if ReportCatchManager.isDragging then
        flags = flags + imgui.WindowFlags.NoMove
    end

    local windowTitle = string.format("##ReportCatch_%d", report.id)

    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.12, 0.12, 0.15, 0.98))
    imgui.PushStyleColor(imgui.Col.Border, COLORS.PRIMARY or imgui.ImVec4(0.15, 0.68, 0.38, 1.0))
    local styleVarPushed = 0
    if imgui.PushStyleVar and imgui.StyleVar then
        imgui.PushStyleVar(imgui.StyleVar.WindowRounding, 12)
        imgui.PushStyleVar(imgui.StyleVar.WindowBorderSize, 2)
        styleVarPushed = 2
    end

    if imgui.Begin(windowTitle, nil, flags) then
        local headerText = string.format("REPORT #%d", report.id)
        imgui.TextColored(COLORS.DANGER or imgui.ImVec4(0.90, 0.30, 0.30, 1.0), headerText)

        imgui.SameLine(imgui.GetWindowWidth() - 40)
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
        if imgui.Button("X##close", imgui.ImVec2(25, 25)) then
            ReportCatchManager.closePopup()
        end
        imgui.PopStyleColor()

        imgui.Separator()

        local reportNickUtf8 = UtilityManager.toUtf8(report.nick)
        local reportTextUtf8 = UtilityManager.toUtf8(report.text)
        imgui.TextColored(COLORS.WARNING or imgui.ImVec4(0.95, 0.77, 0.06, 1.0), string.format("Player: %s", reportNickUtf8))
        imgui.TextDisabled(string.format("Time: %s", report.formattedTime))
        imgui.TextDisabled(string.format("Queue: %d pending", ReportCatchManager.getQueueCount()))

        imgui.Spacing()

        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.08, 0.08, 0.1, 1.0))
        imgui.BeginChild("##ReportText", imgui.ImVec2(0, 60), true)
        imgui.TextWrapped(reportTextUtf8)
        imgui.EndChild()
        imgui.PopStyleColor()

        local mentionedId = ReportCatchManager.resolveMentionedPlayer(report)
        if mentionedId then
            local mentionedNick = UtilityManager.toUtf8(report.mentionedPlayerNick or "")
            local mentionLabel = mentionedNick ~= "" and
                string.format("ID: [%d] %s", mentionedId, mentionedNick) or
                string.format("ID: [%d]", mentionedId)

            imgui.Spacing()
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.25, 0.47, 0.78, 1.0))
            if imgui.Button(mentionLabel .. "##reportMentionedSpec", imgui.ImVec2(0, 30)) then
                ReportCatchManager.spectateMentionedPlayerFromReport()
            end
            imgui.PopStyleColor()

            if imgui.IsItemHovered() then
                imgui.BeginTooltip()
                imgui.Text(u8"Bosilsa: /ans + /sp va tekshiruv tugmalari ochiladi")
                imgui.EndTooltip()
            end
        end

        imgui.Spacing()

        imgui.TextColored(COLORS.INFO or imgui.ImVec4(0.20, 0.60, 0.86, 1.0), u8"Reply Templates:")

        for _, template in ipairs(ReportCatchManager.templates) do
            local btnLabel = string.format("[%d] %s##tpl%d", template.id, template.shortcut, template.id)

            if imgui.Button(btnLabel, imgui.ImVec2(100, 28)) then
                ReportCatchManager.sendReply(template.id)
            end

            if imgui.IsItemHovered() then
                imgui.BeginTooltip()
                imgui.Text(template.text)
                imgui.EndTooltip()
            end

            if template.id % 4 ~= 0 then
                imgui.SameLine()
            end
        end

        imgui.Spacing()
        imgui.Separator()

        imgui.TextColored(COLORS.INFO or imgui.ImVec4(0.20, 0.60, 0.86, 1.0), u8"Quick Actions:")

        local btnSize = imgui.ImVec2(50, 35)

        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.2, 0.6, 0.4, 1.0))
        if imgui.Button(u8"GOTO\n\xf0\x9f\x91\xa4##goto", btnSize) then
            ReportCatchManager.teleportToReporter()
        end
        imgui.PopStyleColor()

        if imgui.IsItemHovered() then
            imgui.BeginTooltip()
            imgui.Text(u8"Teleport to reporter (/goto)")
            imgui.EndTooltip()
        end

        imgui.SameLine()

        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.2, 0.5, 0.7, 1.0))
        if imgui.Button(u8"SPEC\n\xf0\x9f\x91\x81##spec", btnSize) then
            ReportCatchManager.spectateReporter()
        end
        imgui.PopStyleColor()

        if imgui.IsItemHovered() then
            imgui.BeginTooltip()
            imgui.Text(u8"Spectate reporter (/sp)")
            imgui.EndTooltip()
        end

        imgui.SameLine()

        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.7, 0.6, 0.2, 1.0))
        if imgui.Button(u8"INFO\n\xf0\x9f\x93\x92##info", btnSize) then
            ReportCatchManager.getInfoReporter()
        end
        imgui.PopStyleColor()

        if imgui.IsItemHovered() then
            imgui.BeginTooltip()
            imgui.Text(u8"Get player info (/getinfo)")
            imgui.EndTooltip()
        end

        imgui.Spacing()

        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.78, 0.42, 0.18, 1.0))
        if imgui.Button("JAZOLAR##jazo", imgui.ImVec2(95, 32)) then
            ReportCatchManager.requestPunishmentsReporter()
        end
        imgui.PopStyleColor()

        if imgui.IsItemHovered() then
            imgui.BeginTooltip()
            imgui.Text(u8"Getinfo -> warn/jail ni topib /ans yuborish")
            imgui.EndTooltip()
        end

        imgui.SameLine()

        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.45, 0.35, 0.78, 1.0))
        if imgui.Button("HELP##help", imgui.ImVec2(85, 32)) then
            ReportCatchManager.sendHelpRequest()
        end
        imgui.PopStyleColor()

        if imgui.IsItemHovered() then
            imgui.BeginTooltip()
            imgui.Text(u8"/a help(id) + report matnini yuboradi")
            imgui.EndTooltip()
        end

        imgui.SameLine()

        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18, 0.58, 0.74, 1.0))
        if imgui.Button("NAVIGATOR##report_nav", imgui.ImVec2(120, 32)) then
            ReportCatchManager.sendNavigatorPoint()
        end
        imgui.PopStyleColor()

        if imgui.IsItemHovered() then
            imgui.BeginTooltip()
            imgui.Text(u8"/gps ochiladi, tanlangan metka /ans orqali yuboriladi")
            imgui.EndTooltip()
        end

        local queueCount = ReportCatchManager.getQueueCount()
        if queueCount > 0 then
            imgui.TextColored(COLORS.WARNING or imgui.ImVec4(0.95, 0.77, 0.06, 1.0), string.format("Queue: %d", queueCount))
        else
            imgui.TextDisabled("No queue")
        end

        local windowPos = imgui.GetWindowPos()
        if not ReportCatchManager.isDragging then
            settings.popupPos.x = windowPos.x
            settings.popupPos.y = windowPos.y
        end

        imgui.End()
    end

    if styleVarPushed > 0 and imgui.PopStyleVar then
        imgui.PopStyleVar(styleVarPushed)
    end
    imgui.PopStyleColor(2)
end

-- ============================================
-- FURA KILL MANAGER
-- ============================================
local FuraKillManager = {
    enabled = false,
    kills = {},
    killerStats = {},
    groupKillStats = {},
    teamKillStats = {},
    pendingChecks = {},
    activeCheck = nil,
    firstKill = nil,
    lastKill = nil,
    keyword = "jinoiy guruh",
    maxKillLog = 1000,
    maxQueue = 250,
    statsCommandCooldown = 0.55,
    phaseTimeout = 6.0,
    phaseIdleTimeout = 1.6,
    lastStatsCommandAt = 0,
    lastDeathSignature = "",
    lastDeathAt = 0,
    lastExportPath = "",
    criminalGroups = {
        {
            label = "Kurgan uyushgan jinoiy guruh",
            aliases = { "kurgan", "курган", "курганская", "курганская опг", "курганская группировк" }
        },
        {
            label = "Tambov uyushgan jinoiy guruh",
            aliases = { "tambov", "тамбов", "тамбовская", "тамбовская опг", "тамбовская группировк" }
        },
        {
            label = "Kavkaz uyushgan jinoiy guruh",
            aliases = { "kavkaz", "кавказ", "кавказская", "кавказская опг", "кавказская группировк" }
        },
        {
            label = "Orexovskaya uyushgan jinoiy guruh",
            aliases = {
                "orexovskaya", "orekhovskaya", "orexov", "orekhov",
                "орехов", "ореховская", "ореховская опг", "ореховская группировк"
            }
        }
    }
}

function FuraKillManager.initialize()
    FuraKillManager.enabled = SettingsManager.get("furaKillEnabled") == true
    LogManager.system(string.format("Fura Kill manager initialized (%s)",
        FuraKillManager.enabled and "enabled" or "disabled"))
end

function FuraKillManager.setEnabled(state)
    FuraKillManager.enabled = state == true
    SettingsManager.set("furaKillEnabled", FuraKillManager.enabled)

    if not FuraKillManager.enabled then
        FuraKillManager.pendingChecks = {}
        FuraKillManager.activeCheck = nil
    end
end

function FuraKillManager.clearData()
    FuraKillManager.kills = {}
    FuraKillManager.killerStats = {}
    FuraKillManager.groupKillStats = {}
    FuraKillManager.teamKillStats = {}
    FuraKillManager.firstKill = nil
    FuraKillManager.lastKill = nil
    FuraKillManager.pendingChecks = {}
    FuraKillManager.activeCheck = nil
end

function FuraKillManager.normalizeLine(text)
    local clean = tostring(text or ""):gsub("{%x%x%x%x%x%x}", "")
    clean = clean:gsub("[\r\n]+", " "):gsub("%s%s+", " ")
    return UtilityManager.trim(clean)
end

function FuraKillManager.playerLabel(id, nick)
    local pid = tonumber(id) or -1
    local name = UtilityManager.trim(tostring(nick or "Unknown"))
    if name == "" then
        name = "Unknown"
    end
    return string.format("[%d] %s", pid, name)
end

function FuraKillManager.resolveNickById(id)
    local pid = tonumber(id)
    if not pid then
        return "Unknown"
    end

    local okConnected, connected = pcall(sampIsPlayerConnected, pid)
    if okConnected and connected then
        local okNick, nick = pcall(sampGetPlayerNickname, pid)
        if okNick and nick and nick ~= "" then
            return nick
        end
    end

    return string.format("ID_%d", pid)
end

function FuraKillManager.queueKillCheck(killerId, victimId)
    if not FuraKillManager.enabled then
        return
    end

    local kid = tonumber(killerId)
    local vid = tonumber(victimId)
    if not kid or not vid then
        return
    end
    if kid == 65535 or vid == 65535 or kid == vid then
        return
    end

    local now = os.clock()
    local signature = string.format("%d>%d", kid, vid)
    if FuraKillManager.lastDeathSignature == signature and (now - FuraKillManager.lastDeathAt) < 0.4 then
        return
    end
    FuraKillManager.lastDeathSignature = signature
    FuraKillManager.lastDeathAt = now

    local check = {
        killer = {
            id = kid,
            nick = FuraKillManager.resolveNickById(kid),
            isCriminal = false,
            groupName = ""
        },
        victim = {
            id = vid,
            nick = FuraKillManager.resolveNickById(vid),
            isCriminal = false,
            groupName = ""
        },
        createdAt = now,
        phase = nil,
        phaseStartedAt = 0,
        phaseLastRelatedAt = 0,
        phaseRelatedSeen = false,
        phaseDetectedCriminal = false,
        phaseDetectedGroup = "",
        phaseGroupHits = {},
        phaseCapturedLines = {}
    }

    table.insert(FuraKillManager.pendingChecks, check)
    if #FuraKillManager.pendingChecks > FuraKillManager.maxQueue then
        table.remove(FuraKillManager.pendingChecks, 1)
    end
end

function FuraKillManager.onPlayerDeathNotification(killerId, killedId, reason)
    FuraKillManager.queueKillCheck(killerId, killedId)
end

function FuraKillManager.beginPhase(phaseName)
    local active = FuraKillManager.activeCheck
    if not active then
        return
    end

    local side = active[phaseName]
    if not side or not side.id then
        return
    end

    active.phase = phaseName
    active.phaseStartedAt = os.clock()
    active.phaseLastRelatedAt = active.phaseStartedAt
    active.phaseRelatedSeen = false
    active.phaseDetectedCriminal = false
    active.phaseDetectedGroup = ""
    active.phaseGroupHits = {}
    active.phaseCapturedLines = {}

    sampSendChat(string.format(" %d", side.is))
    FuraKillManager.lastStatsCommandAt = os.clock()
end

function FuraKillManager.foldText(text)
    local value = UtilityManager.trim(tostring(text or ""))
    if value == "" then
        return ""
    end
    value = UtilityManager.casefoldUtf8Cyrillic(value)
    value = UtilityManager.casefoldCp1251Cyrillic(value)
    return value:lower()
end

function FuraKillManager.stripTimestampPrefix(text)
    local value = tostring(text or "")
    value = value:gsub("^%s*%[%d%d:%d%d:%d%d%]%s*", "")
    return UtilityManager.trim(value)
end

function FuraKillManager.isNoiseLine(line, foldedLine)
    local source = tostring(line or "")
    local lowered = foldedLine or FuraKillManager.foldText(source)
    if lowered == "" then
        return true
    end

    if lowered:find("<adm>", 1, true) or lowered:find("[a]", 1, true) then
        return true
    end
    if lowered:find("ga javob berdi", 1, true) or lowered:find("ответил", 1, true) then
        return true
    end
    if lowered:find("uchun administrator", 1, true) or lowered:find("administrator", 1, true) then
        return true
    end
    if lowered:find("машинасини таъмирлади", 1, true) or lowered:find("машинасини тамирлади", 1, true) then
        return true
    end
    if source:match("^%s*%[A%]") or source:match("^%s*<ADM>") then
        return true
    end
    if source:match("^[%w_]+%[%d+%]%s*:") then
        return true
    end

    return false
end

function FuraKillManager.detectCriminalMarker(foldedLine)
    local text = FuraKillManager.foldText(foldedLine)
    if text == "" then
        return false
    end
    if text:find("uyushgan jinoiy guruh", 1, true) then
        return true
    end
    if text:find("jinoiy guruh", 1, true) then
        return true
    end
    if text:find("jinoiy", 1, true) and text:find("guruh", 1, true) then
        return true
    end
    if text:find("опг", 1, true) then
        return true
    end
    if text:find("организован", 1, true) and (text:find("преступ", 1, true) or text:find("групп", 1, true)) then
        return true
    end
    if text:find("преступ", 1, true) and text:find("групп", 1, true) then
        return true
    end
    return false
end

function FuraKillManager.detectKnownGroupLabel(foldedLine)
    local text = FuraKillManager.foldText(foldedLine)
    if text == "" then
        return nil
    end

    for _, group in ipairs(FuraKillManager.criminalGroups or {}) do
        local tokens = { group.label }
        for _, alias in ipairs(group.aliases or {}) do
            table.insert(tokens, alias)
        end

        for _, token in ipairs(tokens) do
            local foldedToken = FuraKillManager.foldText(token)
            if foldedToken ~= "" and text:find(foldedToken, 1, true) then
                return group.label
            end
        end
    end

    return nil
end

function FuraKillManager.pickTopGroupFromHits(groupHits)
    local picked = nil
    local pickedCount = -1
    for groupName, count in pairs(groupHits or {}) do
        local total = tonumber(count) or 0
        if total > pickedCount then
            picked = tostring(groupName)
            pickedCount = total
        end
    end
    return picked
end

function FuraKillManager.normalizeGroupLabel(groupName)
    local source = UtilityManager.trim(tostring(groupName or ""))
    if source == "" then
        return ""
    end

    local folded = FuraKillManager.foldText(source)
    local detected = FuraKillManager.detectKnownGroupLabel(folded)
    if detected and detected ~= "" then
        return detected
    end

    return source
end

function FuraKillManager.detectCriminalGroupName(line)
    local folded = FuraKillManager.foldText(line or "")
    if folded == "" then
        return nil
    end

    local known = FuraKillManager.detectKnownGroupLabel(folded)
    local marker = FuraKillManager.detectCriminalMarker(folded)
    if known then
        return known
    end
    if marker then
        return "Uyushgan jinoiy guruh"
    end
    return nil
end

function FuraKillManager.isCriminalGroupLine(line)
    return FuraKillManager.detectCriminalGroupName(line) ~= nil
end

function FuraKillManager.isPhaseLineRelated(active, line, foldedLine)
    local phase = active and active.phase
    local side = phase and active[phase] or nil
    if not side then
        return false
    end

    local idText = tostring(side.id)
    if line:find("[" .. idText .. "]", 1, true) then
        return true
    end

    if foldedLine:match("id%s*[:=]?%s*" .. idText) then
        return true
    end

    local nickFolded = FuraKillManager.foldText(side.nick or "")
    if nickFolded ~= "" and foldedLine:find(nickFolded, 1, true) then
        return true
    end

    if foldedLine:find("hisob qaydnomasi", 1, true) and (foldedLine:find(idText, 1, true) or nickFolded ~= "") then
        return true
    end

    return false
end

function FuraKillManager.capturePhaseLine(active, line)
    local source = UtilityManager.trim(tostring(line or ""))
    if source == "" then
        return
    end

    active.phaseCapturedLines = active.phaseCapturedLines or {}
    for _, existing in ipairs(active.phaseCapturedLines) do
        if existing == source then
            return
        end
    end

    table.insert(active.phaseCapturedLines, source)
    if #active.phaseCapturedLines > 50 then
        table.remove(active.phaseCapturedLines, 1)
    end
end

function FuraKillManager.updatePhaseFromLine(active, line)
    if not active then
        return false
    end

    local cleanLine = FuraKillManager.stripTimestampPrefix(FuraKillManager.normalizeLine(line))
    if cleanLine == "" then
        return false
    end

    local folded = FuraKillManager.foldText(cleanLine)
    if FuraKillManager.isNoiseLine(cleanLine, folded) then
        return false
    end

    local related = FuraKillManager.isPhaseLineRelated(active, cleanLine, folded)
    local hasMarker = FuraKillManager.detectCriminalMarker(folded)
    local knownGroup = FuraKillManager.detectKnownGroupLabel(folded)

    if related or hasMarker or knownGroup then
        active.phaseRelatedSeen = true
        active.phaseLastRelatedAt = os.clock()
        FuraKillManager.capturePhaseLine(active, cleanLine)
    end

    if hasMarker then
        active.phaseDetectedCriminal = true
    end

    if knownGroup then
        active.phaseDetectedCriminal = true
        active.phaseDetectedGroup = knownGroup
        active.phaseGroupHits = active.phaseGroupHits or {}
        active.phaseGroupHits[knownGroup] = (active.phaseGroupHits[knownGroup] or 0) + 1
    end

    return related or hasMarker or knownGroup
end

function FuraKillManager.processStatsTextBlock(rawText)
    if not FuraKillManager.enabled then
        return false
    end

    local active = FuraKillManager.activeCheck
    if not active then
        return false
    end

    local text = tostring(rawText or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    if UtilityManager.trim(text) == "" then
        return false
    end

    local processedAny = false
    local lines = UtilityManager.splitString(text, "\n")
    for _, rawLine in ipairs(lines) do
        if FuraKillManager.updatePhaseFromLine(active, rawLine) then
            processedAny = true
        end
    end

    return processedAny
end

function FuraKillManager.processStatsMessage(text)
    return FuraKillManager.processStatsTextBlock(text)
end

function FuraKillManager.processStatsDialog(dialogId, style, title, button1, button2, text)
    if not FuraKillManager.enabled or not FuraKillManager.activeCheck then
        return false
    end

    local processed = false
    if title and UtilityManager.trim(tostring(title)) ~= "" then
        processed = FuraKillManager.processStatsTextBlock(tostring(title)) or processed
    end
    processed = FuraKillManager.processStatsTextBlock(tostring(text or "")) or processed

    if processed and FuraKillManager.activeCheck then
        -- /stats dialog usually contains the full text block for current phase.
        FuraKillManager.finalizeActiveCheck()
    end

    return processed
end

function FuraKillManager.getTopKiller()
    local top = nil
    for _, entry in pairs(FuraKillManager.killerStats) do
        if entry.kills and entry.kills > 0 then
            if not top or entry.kills > top.kills then
                top = entry
            end
        end
    end
    return top
end

function FuraKillManager.getSortedKillerStats()
    local result = {}
    for _, entry in pairs(FuraKillManager.killerStats) do
        if entry.kills and entry.kills > 0 then
            table.insert(result, entry)
        end
    end

    table.sort(result, function(a, b)
        if a.kills == b.kills then
            return tostring(a.nick) < tostring(b.nick)
        end
        return a.kills > b.kills
    end)

    return result
end

function FuraKillManager.areSameGroup(groupA, groupB)
    local a = FuraKillManager.foldText(FuraKillManager.normalizeGroupLabel(groupA))
    local b = FuraKillManager.foldText(FuraKillManager.normalizeGroupLabel(groupB))
    return a ~= "" and b ~= "" and a == b
end

function FuraKillManager.getSortedGroupStats(sourceStats)
    local result = {}
    for groupName, count in pairs(sourceStats or {}) do
        local total = tonumber(count) or 0
        if total > 0 then
            table.insert(result, {
                group = tostring(groupName),
                count = total
            })
        end
    end

    table.sort(result, function(a, b)
        if a.count == b.count then
            return tostring(a.group) < tostring(b.group)
        end
        return a.count > b.count
    end)

    return result
end

function FuraKillManager.getTeamKillCount()
    local count = 0
    for _, record in ipairs(FuraKillManager.kills) do
        if record.isTeamKill then
            count = count + 1
        end
    end
    return count
end

function FuraKillManager.addKillRecord(killer, victim)
    local killerGroup = UtilityManager.trim(tostring((killer and killer.groupName) or ""))
    local victimGroup = UtilityManager.trim(tostring((victim and victim.groupName) or ""))
    killerGroup = FuraKillManager.normalizeGroupLabel(killerGroup)
    victimGroup = FuraKillManager.normalizeGroupLabel(victimGroup)
    if killerGroup == "" and killer and killer.isCriminal then
        killerGroup = "Uyushgan jinoiy guruh"
    end
    if victimGroup == "" and victim and victim.isCriminal then
        victimGroup = "Uyushgan jinoiy guruh"
    end

    local record = {
        killerId = killer.id,
        killerNick = killer.nick,
        killerGroup = killerGroup,
        victimId = victim.id,
        victimNick = victim.nick,
        victimGroup = victimGroup,
        isTeamKill = FuraKillManager.areSameGroup(killerGroup, victimGroup),
        time = os.time(),
        formattedTime = os.date("%Y-%m-%d %H:%M:%S")
    }

    table.insert(FuraKillManager.kills, record)
    if #FuraKillManager.kills > FuraKillManager.maxKillLog then
        table.remove(FuraKillManager.kills, 1)
    end

    local key = tostring(record.killerId)
    if not FuraKillManager.killerStats[key] then
        FuraKillManager.killerStats[key] = {
            id = record.killerId,
            nick = record.killerNick,
            kills = 0
        }
    end

    local entry = FuraKillManager.killerStats[key]
    entry.nick = record.killerNick
    entry.kills = (entry.kills or 0) + 1

    if record.killerGroup ~= "" then
        FuraKillManager.groupKillStats[record.killerGroup] = (FuraKillManager.groupKillStats[record.killerGroup] or 0) + 1
    end
    if record.isTeamKill and record.killerGroup ~= "" then
        FuraKillManager.teamKillStats[record.killerGroup] = (FuraKillManager.teamKillStats[record.killerGroup] or 0) + 1
    end

    if not FuraKillManager.firstKill then
        FuraKillManager.firstKill = record
    end
    FuraKillManager.lastKill = record
end

function FuraKillManager.finalizeActiveCheck()
    local active = FuraKillManager.activeCheck
    if not active then
        return
    end

    local phase = active.phase
    if not phase or not active[phase] then
        FuraKillManager.activeCheck = nil
        return
    end

    local topGroup = FuraKillManager.pickTopGroupFromHits(active.phaseGroupHits)
    if (not topGroup or topGroup == "") and active.phaseDetectedGroup and active.phaseDetectedGroup ~= "" then
        topGroup = FuraKillManager.normalizeGroupLabel(active.phaseDetectedGroup)
    end

    active[phase].isCriminal = active.phaseDetectedCriminal == true or (topGroup ~= nil and topGroup ~= "")
    if active[phase].isCriminal then
        active[phase].groupName = UtilityManager.trim(tostring(topGroup or ""))
        if active[phase].groupName == "" then
            active[phase].groupName = "Uyushgan jinoiy guruh"
        end
    else
        active[phase].groupName = ""
    end

    if phase == "killer" then
        FuraKillManager.beginPhase("victim")
        return
    end

    if active.killer.isCriminal and active.victim.isCriminal then
        FuraKillManager.addKillRecord(active.killer, active.victim)
    end

    FuraKillManager.activeCheck = nil
end

function FuraKillManager.update()
    if not FuraKillManager.enabled then
        return
    end

    local now = os.clock()

    if FuraKillManager.activeCheck then
        local active = FuraKillManager.activeCheck
        local phaseElapsed = now - (active.phaseStartedAt or now)
        local idleElapsed = now - (active.phaseLastRelatedAt or now)
        local shouldFinalize = phaseElapsed >= FuraKillManager.phaseTimeout or
                              (active.phaseRelatedSeen and idleElapsed >= FuraKillManager.phaseIdleTimeout)
        if shouldFinalize then
            FuraKillManager.finalizeActiveCheck()
        end
        return
    end

    if #FuraKillManager.pendingChecks == 0 then
        return
    end

    if (now - FuraKillManager.lastStatsCommandAt) < FuraKillManager.statsCommandCooldown then
        return
    end

    FuraKillManager.activeCheck = table.remove(FuraKillManager.pendingChecks, 1)
    FuraKillManager.beginPhase("killer")
end

function FuraKillManager.exportToTxt(filename)
    local file = io.open(filename, "w")
    if not file then
        return false
    end

    local function writeLine(s)
        file:write((s or "") .. "\n")
    end

    writeLine("=== FURA KILL MONITOR ===")
    writeLine("Generated: " .. os.date("%Y-%m-%d %H:%M:%S"))
    writeLine("Total tracked kills: " .. tostring(#FuraKillManager.kills))
    writeLine("TK (bir xil guruh): " .. tostring(FuraKillManager.getTeamKillCount()))
    writeLine("")

    local top = FuraKillManager.getTopKiller()
    if top then
        writeLine(string.format("Eng kop kill qilgan: %s - %d",
            FuraKillManager.playerLabel(top.id, top.nick), top.kills))
    else
        writeLine("Eng kop kill qilgan: N/A")
    end

    if FuraKillManager.firstKill then
        writeLine(string.format("Eng birinchi kill qilgan: %s (%s)",
            FuraKillManager.playerLabel(FuraKillManager.firstKill.killerId, FuraKillManager.firstKill.killerNick),
            FuraKillManager.firstKill.formattedTime or ""))
    else
        writeLine("Eng birinchi kill qilgan: N/A")
    end

    if FuraKillManager.lastKill then
        writeLine(string.format("Eng oxirgi kill qilgan: %s (%s)",
            FuraKillManager.playerLabel(FuraKillManager.lastKill.killerId, FuraKillManager.lastKill.killerNick),
            FuraKillManager.lastKill.formattedTime or ""))
    else
        writeLine("Eng oxirgi kill qilgan: N/A")
    end

    writeLine("")
    writeLine("=== KILLERLAR RO'YXATI ===")
    local killers = FuraKillManager.getSortedKillerStats()
    if #killers == 0 then
        writeLine("No data")
    else
        for _, entry in ipairs(killers) do
            writeLine(string.format("%s - %d",
                FuraKillManager.playerLabel(entry.id, entry.nick), entry.kills))
        end
    end

    writeLine("")
    writeLine("=== GURUH BO'YICHA KILL ===")
    local groupKills = FuraKillManager.getSortedGroupStats(FuraKillManager.groupKillStats)
    if #groupKills == 0 then
        writeLine("No data")
    else
        for _, entry in ipairs(groupKills) do
            writeLine(string.format("%s - %d", tostring(entry.group), tonumber(entry.count) or 0))
        end
    end

    writeLine("")
    writeLine("=== TK (BIR XIL GURUH) ===")
    local tkGroups = FuraKillManager.getSortedGroupStats(FuraKillManager.teamKillStats)
    if #tkGroups == 0 then
        writeLine("No data")
    else
        for _, entry in ipairs(tkGroups) do
            writeLine(string.format("%s - %d", tostring(entry.group), tonumber(entry.count) or 0))
        end
    end

    writeLine("")
    writeLine("=== KILL LOG ===")
    if #FuraKillManager.kills == 0 then
        writeLine("No tracked kills")
    else
        for i, record in ipairs(FuraKillManager.kills) do
            local killerGroup = UtilityManager.trim(tostring(record.killerGroup or ""))
            local victimGroup = UtilityManager.trim(tostring(record.victimGroup or ""))
            if killerGroup == "" then
                killerGroup = "Noma'lum guruh"
            end
            if victimGroup == "" then
                victimGroup = "Noma'lum guruh"
            end
            local tkText = record.isTeamKill and " | TK" or ""
            writeLine(string.format("%d. %s -> %s",
                i,
                killerGroup,
                victimGroup))
            writeLine(string.format("   %s oldirdi %s%s | %s",
                FuraKillManager.playerLabel(record.killerId, record.killerNick),
                FuraKillManager.playerLabel(record.victimId, record.victimNick),
                tkText,
                record.formattedTime or ""))
        end
    end

    file:close()
    FuraKillManager.lastExportPath = filename
    return true
end

-- ============================================
-- ANALYTICS MANAGER
-- ============================================
local AnalyticsManager = {
    data = {
        daily = {},
        weekly = {},
        monthly = {}
    },
    performanceAlerts = {},
    trends = {}
}

function AnalyticsManager.initialize()
    AnalyticsManager.loadData()
    LogManager.system("Analytics manager initialized")
end

function AnalyticsManager.loadData()
end

function AnalyticsManager.saveData()
end

function AnalyticsManager.recordDailyStat(key, value)
    local date = UtilityManager.getDateString()
    if not AnalyticsManager.data.daily[date] then
        AnalyticsManager.data.daily[date] = {}
    end
    AnalyticsManager.data.daily[date][key] = value
end

function AnalyticsManager.getDailyGraph()
    return AnalyticsManager.data.daily
end

function AnalyticsManager.getWeeklyGraph()
    return AnalyticsManager.data.weekly
end

function AnalyticsManager.getMonthlyGraph()
    return AnalyticsManager.data.monthly
end

function AnalyticsManager.getEfficiencyChart()
    local chart = {
        labels = {},
        data = {},
        colors = {}
    }
    return chart
end

function AnalyticsManager.getActivityHeatmap()
    return {}
end

function AnalyticsManager.getPeakHours()
    return {}
end

function AnalyticsManager.getReportResolutionTime()
    return 0
end

function AnalyticsManager.getAverageAnswerSpeed()
    return 0
end

function AnalyticsManager.getAdminRanking()
    return {}
end

function AnalyticsManager.calculateScore()
    local score = StatsManager.getPerformanceScore()
    return score
end

function AnalyticsManager.exportToTxt(filename)
    local file = io.open(filename, "w")
    if file then
        file:write("=== Grand Mobile Analytics Report ===\n\n")
        file:write(string.format("Daily Answers: %d\n", StatsManager.data.daily.answers))
        file:write(string.format("Weekly Answers: %d\n", StatsManager.data.weekly.answers))
        file:write(string.format("Monthly Answers: %d\n", StatsManager.data.monthly.answers))
        file:write(string.format("Session Duration: %s\n",
            UtilityManager.formatTime(StatsManager.data.session.playtime or 0)))
        file:write(string.format("Efficiency: %.1f%%\n", StatsManager.data.efficiency))
        file:write(string.format("Rank: %s\n", StatsManager.data.rank))
        file:close()
        return true
    end
    return false
end

function AnalyticsManager.exportToJson(filename)
    local file = io.open(filename, "w")
    if file then
        local json = {
            daily = StatsManager.data.daily,
            weekly = StatsManager.data.weekly,
            monthly = StatsManager.data.monthly,
            session = {
                answers = StatsManager.data.session.answers,
                duration = UtilityManager.formatTime(StatsManager.data.session.playtime or 0)
            },
            efficiency = StatsManager.data.efficiency,
            rank = StatsManager.data.rank,
            timestamp = os.time()
        }
        file:write("JSON data exported")
        file:close()
        return true
    end
    return false
end

function AnalyticsManager.comparePreviousWeek()
    return { difference = 0, percentage = 0 }
end

function AnalyticsManager.checkPerformanceAlert()
    return nil
end

function AnalyticsManager.analyzeTrend()
    return {}
end

-- ============================================
-- MAIN UI SYSTEM
-- ============================================
MainUI = {
    window = {
        open = false,
        pos = nil,
        size = nil
    },
    currentTab = 0,
    tabNames = {
        "Dashboard",
        "Report Center",
        "Report Catch",
        "Kerakli",
        "Player Management",
        "Teleport System",
        "Server Control",
        "Security Center",
        "Analytics",
        "Utilities",
        "Settings",
        "Fura Monitor",
        "MP"
    },
    mpBroadcasts = {
        mpReklama = {
            "Assalomu alaykum, aziz o'yinchilar!",
            "\"Go'sht maydalagich\" tadbiri boshlanish arafasida.",
            "Ishtirok etish uchun hisobotingizga \"+\" belgisini yozing.",
            "Teleportatsiyadan so'ng siz qochishingiz kerak!",
            "Sovrin jamg'armasi: 50 000 rubl."
        },
        adminReklama = {
            "Hurmatli o'yinchilar, Nomzodlar xonasida - https://discord.gg/6vB4SrNeaz",
            "Administrator lavozimiga arizalar ochiq, shoshiling.",
            "Arizani qanday topshirish mumkin? 38-server Nomzodlar Discordiga kiring.",
            "Keyin \"Boshlanish\" > \"Administrator uchun arizalar\" bo'limiga o'ting.",
            "Kriteriyalarni o'qib chiqqaningizdan so'ng, anketani topshiring va yangiliklarni kuting.",
            "Loyiha ma'muriyati sizga Grand Mobile'da maroqli o'yin tilaydi!"
        }
    },
    animations = {
        fade = 0,
        tabTransition = 0
    },
    buffers = {},
    theme = {
        dark = true,
        accentColor = nil
    },
    kerakliAccess = {
        unlocked = false,
        passwordHash = ("f3c7" .. "3bf6"),
        lastError = ""
    },
    mpAccess = {
        unlocked = false,
        passwordHash = ("b0a6" .. "dfee"),
        lastError = ""
    },
    initialized = false
}

function MainUI.initialize()
    -- Initialize buffers
    MainUI.buffers = {
        playerId = imgui.ImInt(0),
        reason = imgui.new.char[256](),
        amount = imgui.ImInt(100),
        duration = imgui.ImInt(60),
        search = imgui.new.char[64](),
        mpEventName = imgui.new.char[96](),
        mpGunRadius = imgui.ImInt(30),
        mpGunId = imgui.ImInt(24),
        mpGunAmmo = imgui.ImInt(150),
        mpRgunRadius = imgui.ImInt(30),
        mpHpRadius = imgui.ImInt(30),
        mpHpValue = imgui.ImInt(100),
        mpSkinRadius = imgui.ImInt(30),
        mpSkinId = imgui.ImInt(1),
        kerakliPassword = imgui.new.char[64](),
        mpPassword = imgui.new.char[64](),
        keywordTpText = imgui.new.char[64](),
        afkReportKeywords = imgui.new.char[256](),
        afkReportReplyText = imgui.new.char[256](),
        afkReportAdminHelpText = imgui.new.char[128](),
        afkReportCooldown = imgui.ImInt(8),
        coordX = imgui.ImFloat(0),
        coordY = imgui.ImFloat(0),
        coordZ = imgui.ImFloat(0)
    }

    SpectateQuickPanel.loadUiFromSettings()

    UtilityManager.setBufferString(
        MainUI.buffers.keywordTpText,
        ReportCatchManager.settings.keywordTpText or "tp"
    )
    UtilityManager.setBufferString(MainUI.buffers.kerakliPassword, "")
    MainUI.kerakliAccess.unlocked = false
    MainUI.kerakliAccess.lastError = ""
    ReportCatchManager.kerakliUnlocked = false
    UtilityManager.setBufferString(MainUI.buffers.mpPassword, "")
    MainUI.mpAccess.unlocked = false
    MainUI.mpAccess.lastError = ""
    UtilityManager.setBufferString(
        MainUI.buffers.afkReportKeywords,
        ReportCatchManager.settings.afkReportKeywords or "help, yordam, помогите, chin, tuzat, tuzating"
    )
    UtilityManager.setBufferString(
        MainUI.buffers.afkReportReplyText,
        ReportCatchManager.settings.afkReportReplyText or "Assalom alekum, kuzatyapman"
    )
    UtilityManager.setBufferString(
        MainUI.buffers.afkReportAdminHelpText,
        ReportCatchManager.settings.afkReportAdminHelpText or "help {id}"
    )
    MainUI.buffers.afkReportCooldown[0] = tonumber(ReportCatchManager.settings.afkReportCooldown) or 8
    UtilityManager.setBufferString(MainUI.buffers.mpEventName, "Go'sht maydalagich")

    -- Initialize colors
    COLORS.PRIMARY = imgui.ImVec4(0.15, 0.68, 0.38, 1.0)
    COLORS.SECONDARY = imgui.ImVec4(0.20, 0.60, 0.86, 1.0)
    COLORS.DANGER = imgui.ImVec4(0.90, 0.30, 0.30, 1.0)
    COLORS.WARNING = imgui.ImVec4(0.95, 0.77, 0.06, 1.0)
    COLORS.INFO = imgui.ImVec4(0.20, 0.60, 0.86, 1.0)
    COLORS.LIGHT = imgui.ImVec4(0.93, 0.94, 0.95, 1.0)
    COLORS.DARK = imgui.ImVec4(0.17, 0.24, 0.31, 1.0)
    COLORS.BACKGROUND = imgui.ImVec4(0.10, 0.10, 0.12, 1.0)
    COLORS.SURFACE = imgui.ImVec4(0.15, 0.15, 0.18, 1.0)
    COLORS.TEXT = imgui.ImVec4(0.95, 0.95, 0.95, 1.0)
    COLORS.TEXT_DIM = imgui.ImVec4(0.60, 0.60, 0.60, 1.0)

    MainUI.theme.accentColor = COLORS.PRIMARY

    imgui.OnInitialize(function()
        -- Load a font with Cyrillic glyphs so RU text is rendered correctly.
        local io = imgui.GetIO and imgui.GetIO()
        if io and io.Fonts and io.Fonts.AddFontFromFileTTF then
            local glyphRanges = nil
            if io.Fonts.GetGlyphRangesCyrillic then
                local okRanges, ranges = pcall(function()
                    return io.Fonts:GetGlyphRangesCyrillic()
                end)
                if okRanges then
                    glyphRanges = ranges
                end
            end

            local okFont, font = pcall(function()
                return io.Fonts:AddFontFromFileTTF("C:\\Windows\\Fonts\\arial.ttf", 14.0, nil, glyphRanges)
            end)
            if okFont and font then
                io.FontDefault = font
            end
        end

        local style = imgui.GetStyle()
        style.WindowRounding = CONFIG.UI.ROUNDING
        style.FrameRounding = 8
        style.PopupRounding = 8
        style.ScrollbarRounding = 8
        style.GrabRounding = 8
        style.TabRounding = 8
        style.ChildRounding = 8

        style.WindowPadding = imgui.ImVec2(12, 12)
        style.FramePadding = imgui.ImVec2(8, 6)
        style.ItemSpacing = imgui.ImVec2(8, 8)
        style.ItemInnerSpacing = imgui.ImVec2(6, 6)

        local colors = style.Colors
        colors[imgui.Col.WindowBg] = COLORS.BACKGROUND
        colors[imgui.Col.ChildBg] = COLORS.SURFACE
        colors[imgui.Col.PopupBg] = COLORS.SURFACE
        colors[imgui.Col.Border] = imgui.ImVec4(0.2, 0.2, 0.25, 1.0)
        colors[imgui.Col.FrameBg] = imgui.ImVec4(0.2, 0.2, 0.25, 1.0)
        colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.25, 0.25, 0.3, 1.0)
        colors[imgui.Col.FrameBgActive] = imgui.ImVec4(0.3, 0.3, 0.35, 1.0)
        colors[imgui.Col.TitleBg] = COLORS.DARK
        colors[imgui.Col.TitleBgActive] = COLORS.PRIMARY
        colors[imgui.Col.CheckMark] = COLORS.PRIMARY
        colors[imgui.Col.SliderGrab] = COLORS.PRIMARY
        colors[imgui.Col.SliderGrabActive] = COLORS.SECONDARY
        colors[imgui.Col.Button] = COLORS.PRIMARY
        colors[imgui.Col.ButtonHovered] = imgui.ImVec4(0.2, 0.75, 0.45, 1.0)
        colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.1, 0.6, 0.3, 1.0)
        colors[imgui.Col.Header] = COLORS.PRIMARY
        colors[imgui.Col.HeaderHovered] = imgui.ImVec4(0.2, 0.75, 0.45, 1.0)
        colors[imgui.Col.HeaderActive] = imgui.ImVec4(0.1, 0.6, 0.3, 1.0)
        colors[imgui.Col.Separator] = imgui.ImVec4(0.2, 0.2, 0.25, 1.0)
        colors[imgui.Col.Text] = COLORS.TEXT
        colors[imgui.Col.TextDisabled] = COLORS.TEXT_DIM
        colors[imgui.Col.PlotHistogram] = COLORS.PRIMARY
        colors[imgui.Col.PlotHistogramHovered] = COLORS.SECONDARY
        colors[imgui.Col.Tab] = imgui.ImVec4(0.15, 0.15, 0.18, 1.0)
        colors[imgui.Col.TabHovered] = imgui.ImVec4(0.2, 0.75, 0.45, 1.0)
        colors[imgui.Col.TabActive] = COLORS.PRIMARY
    end)

    imgui.OnFrame(function()
        local spectatePanelVisible = SpectateQuickPanel.active and SpectateQuickPanel.cursorVisible
        local clickTpVisible = TeleportClickManager and TeleportClickManager.enabled or false
        local hudEditVisible = HudManager and HudManager.editMode or false
        return MainUI.window.open or ReportCatchManager.popupOpen or AdminRelayManager.popupOpen or
               spectatePanelVisible or clickTpVisible or hudEditVisible
    end, function()
        if MainUI.window.open then
            MainUI.render()
        end
        if ReportCatchManager.popupOpen then
            ReportCatchManager.renderPopup()
        end
        if AdminRelayManager.popupOpen then
            AdminRelayManager.renderPopup()
        end
        if SpectateQuickPanel.active and SpectateQuickPanel.cursorVisible then
            SpectateQuickPanel.render()
        end
        if TeleportClickManager and TeleportClickManager.renderCursorOverlay then
            TeleportClickManager.renderCursorOverlay()
        end
        if HudManager and HudManager.renderEditOverlay then
            HudManager.renderEditOverlay()
        end
    end)

    MainUI.initialized = true
    LogManager.system("MainUI initialized")
end

function MainUI.toggle()
    MainUI.window.open = not MainUI.window.open

    -- CRITICAL: Handle cursor and process properly
    if MainUI.window.open then
        imgui.ShowCursor = true
        imgui.Process = true
    else
        imgui.ShowCursor = false
        imgui.Process = false
        if HudManager and HudManager.editMode then
            HudManager.setEditMode(false)
        end
    end

    LogManager.system(string.format("Panel %s", MainUI.window.open and "opened" or "closed"))
end

function MainUI.render()
    if not MainUI.window.open then return end

    local minWidth, minHeight = 620, 420
    local defaultPos = imgui.ImVec2(100, 100)
    local condAppearing = (imgui.Cond and imgui.Cond.Appearing) or imgui.Cond.FirstUseEver

    if MainUI.window.pos and MainUI.window.pos.x and MainUI.window.pos.y then
        imgui.SetNextWindowPos(
            imgui.ImVec2(MainUI.window.pos.x, MainUI.window.pos.y),
            condAppearing
        )
    else
        imgui.SetNextWindowPos(defaultPos, imgui.Cond.FirstUseEver)
    end

    local io = imgui.GetIO and imgui.GetIO()
    if io and io.DisplaySize then
        local maxWidth = math.max(minWidth, io.DisplaySize.x - 20)
        local maxHeight = math.max(minHeight, io.DisplaySize.y - 20)

        if imgui.SetNextWindowSizeConstraints then
            imgui.SetNextWindowSizeConstraints(
                imgui.ImVec2(minWidth, minHeight),
                imgui.ImVec2(maxWidth, maxHeight)
            )
        end

        if MainUI.window.size and MainUI.window.size.x and MainUI.window.size.y then
            imgui.SetNextWindowSize(
                imgui.ImVec2(MainUI.window.size.x, MainUI.window.size.y),
                condAppearing
            )
        else
            local autoWidth = math.max(minWidth, math.min(maxWidth, io.DisplaySize.x * 0.88))
            local autoHeight = math.max(minHeight, math.min(maxHeight, io.DisplaySize.y * 0.88))
            imgui.SetNextWindowSize(
                imgui.ImVec2(autoWidth, autoHeight),
                imgui.Cond.FirstUseEver
            )
        end
    else
        if MainUI.window.size and MainUI.window.size.x and MainUI.window.size.y then
            imgui.SetNextWindowSize(
                imgui.ImVec2(MainUI.window.size.x, MainUI.window.size.y),
                condAppearing
            )
        else
            imgui.SetNextWindowSize(imgui.ImVec2(minWidth, minHeight), imgui.Cond.FirstUseEver)
        end
    end

    local flags = imgui.WindowFlags.NoCollapse +
                  imgui.WindowFlags.MenuBar

    local shouldDraw = imgui.Begin(u8"Grand Mobile Tools by Harvey v" .. CONFIG.VERSION,
                   nil, flags)

    if shouldDraw then
        if imgui.GetWindowPos then
            local pos = imgui.GetWindowPos()
            if pos then
                MainUI.window.pos = { x = pos.x, y = pos.y }
            end
        end
        if imgui.GetWindowSize then
            local size = imgui.GetWindowSize()
            if size then
                MainUI.window.size = { x = size.x, y = size.y }
            end
        end
        MainUI.renderMenuBar()
        MainUI.renderTabs()
    end

    imgui.End()
end

function MainUI.renderMenuBar()
    if imgui.BeginMenuBar() then
        if imgui.BeginMenu(u8"File") then
            if imgui.MenuItem(u8"Save Settings") then
                SettingsManager.save()
            end
            if imgui.MenuItem(u8"Export Logs") then
                LogManager.exportToFile(getWorkingDirectory() .. "/logs/export_" .. os.time() .. ".txt")
            end
            imgui.Separator()
            if imgui.MenuItem(u8"Yopish") then
                MainUI.window.open = false
                imgui.ShowCursor = false
                imgui.Process = false
            end
            imgui.EndMenu()
        end

        if imgui.BeginMenu(u8"View") then
            if imgui.MenuItem(u8"Dashboard", nil, MainUI.currentTab == 0) then
                MainUI.currentTab = 0
            end
            if imgui.MenuItem(u8"Report Center", nil, MainUI.currentTab == 1) then
                MainUI.currentTab = 1
            end
            if imgui.MenuItem(u8"Report Catch", nil, MainUI.currentTab == 2) then
                MainUI.currentTab = 2
            end
            if imgui.MenuItem(u8"Kerakli", nil, MainUI.currentTab == 3) then
                MainUI.currentTab = 3
            end
            if imgui.MenuItem(u8"Player Management", nil, MainUI.currentTab == 4) then
                MainUI.currentTab = 4
            end
            if imgui.MenuItem(u8"MP", nil, MainUI.currentTab == 12) then
                MainUI.currentTab = 12
            end
            imgui.EndMenu()
        end

        if imgui.BeginMenu(u8"Help") then
            if imgui.MenuItem(u8"Documentation") then
            end
            if imgui.MenuItem(u8"About") then
            end
            imgui.EndMenu()
        end

        imgui.SameLine(imgui.GetWindowWidth() - 200)
        imgui.TextDisabled(string.format("Session: %s",
            UtilityManager.formatTime(StatsManager.data.session.playtime or 0)))

        imgui.EndMenuBar()
    end
end

function MainUI.renderTabs()
    local tabBar = imgui.TabBarFlags or {}
    local tabItem = imgui.TabItemFlags or {}
    local tabBarFlags = (tabBar.Reorderable or 0) +
                       (tabBar.AutoSelectNewTabs or 0) +
                       (tabBar.NoCloseWithMiddleMouseButton or 0) +
                       (tabBar.FittingPolicyScroll or 0)

    if imgui.BeginTabBar("##MainTabs", tabBarFlags) then
        for i, tabName in ipairs(MainUI.tabNames) do
            local tabFlags = 0
            if i - 1 == MainUI.currentTab then
                tabFlags = tabItem.SetSelected or 0
            end

            if imgui.BeginTabItem(u8(tabName), nil, tabFlags) then
                MainUI.currentTab = i - 1
                MainUI.renderTabContent(i - 1)
                imgui.EndTabItem()
            end
        end
        imgui.EndTabBar()
    end
end

function MainUI.renderTabContent(tabIndex)
    imgui.BeginChild("##TabContent", imgui.ImVec2(0, -30), true)

    if tabIndex == 0 then
        MainUI.renderDashboard()
    elseif tabIndex == 1 then
        MainUI.renderReportCenter()
    elseif tabIndex == 2 then
        MainUI.renderReportCatch()
    elseif tabIndex == 3 then
        MainUI.renderKerakli()
    elseif tabIndex == 4 then
        MainUI.renderPlayerManagement()
    elseif tabIndex == 5 then
        MainUI.renderTeleportSystem()
    elseif tabIndex == 6 then
        MainUI.renderServerControl()
    elseif tabIndex == 7 then
        MainUI.renderSecurityCenter()
    elseif tabIndex == 8 then
        MainUI.renderAnalytics()
    elseif tabIndex == 9 then
        MainUI.renderUtilities()
    elseif tabIndex == 10 then
        MainUI.renderSettings()
    elseif tabIndex == 11 then
        MainUI.renderFuraMonitor()
    elseif tabIndex == 12 then
        MainUI.renderMP()
    end

    imgui.EndChild()

    imgui.Separator()
    imgui.TextDisabled(string.format("Rank: %s | Efficiency: %.1f%% | Answers: %d",
        StatsManager.data.rank,
        StatsManager.data.efficiency,
        StatsManager.data.session.answers))
    imgui.SameLine(imgui.GetWindowWidth() - 150)
    if AFKManager.isAFK then
        imgui.TextColored(COLORS.WARNING, u8"AFK")
    else
        imgui.TextColored(COLORS.PRIMARY, u8"Active")
    end
end

function MainUI.renderDashboard()
    imgui.Columns(3, "##DashboardCols1", false)

    imgui.TextColored(COLORS.PRIMARY, u8"REPORTLAR")
    imgui.Text(string.format("Hozir: %d", StatsManager.data.session.answers))
    for i = 1, 7 do
        local day = StatsManager.getWeekdayData(i)
        imgui.Text(string.format("%s: %d", StatsManager.getWeekdayLabel(i), day.answers or 0))
    end
    imgui.Text(string.format("Shu oy: %d", StatsManager.data.monthly.answers))

    imgui.NextColumn()

    imgui.TextColored(COLORS.SECONDARY, u8"O'YNALGAN VAQT")
    imgui.Text(string.format("Hozir: %s", UtilityManager.formatTime(StatsManager.data.session.playtime or 0)))
    for i = 1, 7 do
        local day = StatsManager.getWeekdayData(i)
        imgui.Text(string.format("%s: %s", StatsManager.getWeekdayLabel(i),
            UtilityManager.formatTime(day.playtime or 0)))
    end
    imgui.Text(string.format("Shu oy: %s", UtilityManager.formatTime(StatsManager.data.monthly.playtime)))

    imgui.NextColumn()

    imgui.TextColored(COLORS.INFO, u8"PERFORMANCE")
    imgui.Text(string.format("Efficiency: %.1f%%", StatsManager.data.efficiency))
    imgui.Text(string.format("Score: %d", StatsManager.getPerformanceScore()))
    imgui.Text(string.format("Uptime: %d%%", StatsManager.getUptime()))
    imgui.Text(string.format("Weekly Trend: %d%%", StatsManager.getWeeklyTrend()))

    imgui.Columns(1)
    imgui.Separator()

    if imgui.CollapsingHeader(u8"Activity Indicators") then
        imgui.Columns(3, "##DashboardCols2", false)

        imgui.Text(u8"AFK Status:")
        if AFKManager.isAFK then
            imgui.TextColored(COLORS.DANGER,
                string.format("AFK for %s", UtilityManager.formatTime(AFKManager.getCurrentAFKTime())))
        else
            imgui.TextColored(COLORS.PRIMARY, u8"Active")
        end

        imgui.NextColumn()

        imgui.Text(u8"Session ID:")
        imgui.TextDisabled(UtilityManager.data.sessionId or "N/A")

        imgui.NextColumn()

        imgui.Text(u8"Last Answer ID:")
        imgui.TextDisabled(tostring(StatsManager.data.lastAnswerId))

        imgui.Columns(1)

        imgui.Spacing()
        imgui.Text(u8"Daily Answers Norm Progress")
        local dailyProgress = math.min(100, (StatsManager.data.daily.answers / 100) * 100)
        imgui.ProgressBar(dailyProgress / 100, imgui.ImVec2(-1, 20),
            string.format("%d/100 (%.0f%%)", StatsManager.data.daily.answers, dailyProgress))

        imgui.Text(u8"Daily Time Norm Progress")
        local timeProgress = math.min(100, (StatsManager.data.daily.playtime / 7200) * 100)
        imgui.ProgressBar(timeProgress / 100, imgui.ImVec2(-1, 20),
            string.format("%s/2h (%.0f%%)", UtilityManager.formatTime(StatsManager.data.daily.playtime), timeProgress))
    end

    if imgui.CollapsingHeader(u8"Rank & Trends") then
        imgui.Columns(2, "##DashboardCols3", false)

        imgui.Text(u8"Current Rank:")
        local rankColors = {
            ["Bronze"] = imgui.ImVec4(0.8, 0.5, 0.2, 1.0),
            ["Silver"] = imgui.ImVec4(0.75, 0.75, 0.75, 1.0),
            ["Gold"] = imgui.ImVec4(1.0, 0.84, 0.0, 1.0),
            ["Platinum"] = imgui.ImVec4(0.9, 0.9, 0.95, 1.0),
            ["Diamond"] = imgui.ImVec4(0.0, 0.8, 1.0, 1.0)
        }
        imgui.TextColored(rankColors[StatsManager.data.rank] or COLORS.TEXT,
            StatsManager.data.rank)

        imgui.NextColumn()

        imgui.Text(u8"Activity Level:")
        local activity = StatsManager.data.session.answers / math.max(1, StatsManager.getSessionDuration() / 3600)
        local heatText = activity < 10 and "Low" or activity < 30 and "Medium" or activity < 60 and "High" or "Extreme"
        local heatColor = activity < 10 and COLORS.INFO or
                         activity < 30 and COLORS.PRIMARY or
                         activity < 60 and COLORS.WARNING or COLORS.DANGER
        imgui.TextColored(heatColor, heatText)

        imgui.Columns(1)
    end

    imgui.Separator()
    imgui.Text(u8"Quick Actions:")
    if imgui.Button(u8"Reset Daily Stats", imgui.ImVec2(150, 30)) then
        StatsManager.resetDaily()
        StatsManager.save()
    end
    imgui.SameLine()
    if imgui.Button(u8"Export Analytics", imgui.ImVec2(150, 30)) then
        AnalyticsManager.exportToTxt(getWorkingDirectory() .. "/analytics_" .. os.time() .. ".txt")
    end
end

function MainUI.renderReportCenter()
    local autoAccept = imgui.ImBool(ReportManager.autoAccept)
    if imgui.Checkbox(u8"Auto Accept Reports", autoAccept) then
        ReportManager.autoAccept = autoAccept[0]
    end
    imgui.SameLine()

    local stats = ReportManager.getStatistics()
    imgui.TextDisabled(string.format("Pending: %d | Accepted: %d | Closed: %d",
        stats.pending, stats.accepted, stats.closed))

    imgui.Separator()

    if imgui.CollapsingHeader(u8"Active Reports") then
        imgui.BeginChild("##ReportList", imgui.ImVec2(0, 200), true)

        for _, report in ipairs(ReportManager.reports) do
            local label = string.format("[%s] #%d: %s -> %s | %s",
                report.status:upper(), report.id, report.reporter, report.suspect, report.reason)

            if report.priority == "spam" then
                imgui.PushStyleColor(imgui.Col.Text, COLORS.DANGER)
            elseif report.priority == "high" then
                imgui.PushStyleColor(imgui.Col.Text, COLORS.WARNING)
            end

            if imgui.Selectable(label, false) then
            end

            if report.priority == "spam" or report.priority == "high" then
                imgui.PopStyleColor()
            end

            if imgui.BeginPopupContextItem() then
                if imgui.MenuItem(u8"Qabul") then
                    ReportManager.acceptReport(report.id)
                end
                if imgui.MenuItem(u8"Yopish") then
                    ReportManager.closeReport(report.id, "Closed by admin")
                end
                if imgui.MenuItem(u8"Teleport to Reporter") then
                    ReportManager.teleportToReporter(report.id)
                end
                if imgui.MenuItem(u8"Teleport to Suspect") then
                    ReportManager.teleportToSuspect(report.id)
                end
                imgui.EndPopup()
            end
        end

        if #ReportManager.reports == 0 then
            imgui.TextDisabled(u8"No active reports")
        end

        imgui.EndChild()
    end

    if imgui.CollapsingHeader(u8"Auto Reply Templates") then
        for _, template in ipairs(ReportManager.templates) do
            if imgui.Button(string.format("%s##template%d", template.name, template.id),
                           imgui.ImVec2(120, 25)) then
            end
            imgui.SameLine()
            imgui.TextDisabled(template.text:sub(1, 40) .. "...")
        end
    end

    imgui.Separator()
    imgui.Text(u8"Report Actions:")

    imgui.InputInt(u8"Report ID", MainUI.buffers.playerId)

    if imgui.Button(u8"Accept Report", imgui.ImVec2(120, 25)) then
        ReportManager.acceptReport(MainUI.buffers.playerId[0])
    end
    imgui.SameLine()
    if imgui.Button(u8"Close Report", imgui.ImVec2(120, 25)) then
        ReportManager.closeReport(MainUI.buffers.playerId[0], "Manual close")
    end
    imgui.SameLine()
    if imgui.Button(u8"Freeze Suspect", imgui.ImVec2(120, 25)) then
    end
    imgui.SameLine()
    if imgui.Button(u8"Kuzatish", imgui.ImVec2(120, 25)) then
    end

    if imgui.CollapsingHeader(u8"Spam Detection Settings") then
        local spamDetect = imgui.ImBool(true)
        imgui.Checkbox(u8"Enable Spam Detection", spamDetect)
        imgui.Checkbox(u8"Enable Duplicate Detection", spamDetect)
        imgui.Checkbox(u8"Auto Cooldown", spamDetect)

        local cooldown = imgui.ImInt(ReportManager.cooldown)
        imgui.InputInt(u8"Cooldown (seconds)", cooldown)
    end
end

function MainUI.renderKerakliControls(options)
    local opts = options or {}
    local scopeSuffix = tostring(opts.scopeSuffix or "main")
    local hideKeywordTp = opts.hideKeywordTp == true
    local onlyKeywordTp = opts.onlyKeywordTp == true and not hideKeywordTp

    if not hideKeywordTp then
        local keywordTpEnabled = imgui.ImBool(ReportCatchManager.settings.keywordTpEnabled)
        if imgui.Checkbox(u8"O'ziga TP qilish (kalit so'z bo'yicha)##kerakli_kwtp_" .. scopeSuffix, keywordTpEnabled) then
            ReportCatchManager.settings.keywordTpEnabled = keywordTpEnabled[0]
            ReportCatchManager.saveSettings()
        end

        imgui.InputText(u8"Kalit so'z##kerakli_kwtext_" .. scopeSuffix, MainUI.buffers.keywordTpText, 64)
        if imgui.Button(u8"Kalit so'zni saqlash##kerakli_kwsave_" .. scopeSuffix, imgui.ImVec2(150, 25)) then
            local triggerText = UtilityManager.trim(
                UtilityManager.bufferToString(MainUI.buffers.keywordTpText) or ""
            )
            if triggerText == "" then
                triggerText = "tp"
            end
            ReportCatchManager.settings.keywordTpText = triggerText
            UtilityManager.setBufferString(MainUI.buffers.keywordTpText, triggerText)
            ReportCatchManager.saveSettings()
        end

        imgui.TextDisabled(
            string.format("Hozirgi matn: %s", tostring(ReportCatchManager.settings.keywordTpText or "tp"))
        )
        imgui.TextDisabled(u8"Qoidasi: reportda shu matn bo'lsa, darhol /gethere qiladi.")
        imgui.TextDisabled(u8"Bitta o'yinchiga qayta TP: 10 soniya cooldown.")
        imgui.TextDisabled(string.format("TP navbat: %d", #ReportCatchManager.keywordTpQueue))

        if onlyKeywordTp then
            return
        end
    end

    imgui.Separator()
    imgui.TextColored(COLORS.INFO or imgui.ImVec4(0.20, 0.60, 0.86, 1.0), u8"AFK Report")

    local afkEnabled = imgui.ImBool(ReportCatchManager.settings.afkReportEnabled)
    if imgui.Checkbox(u8"AFK Report Auto", afkEnabled) then
        ReportCatchManager.settings.afkReportEnabled = afkEnabled[0]
        ReportCatchManager.saveSettings()
    end

    imgui.InputText(u8"Kalit so'zlar (, bilan)", MainUI.buffers.afkReportKeywords, 256)
    imgui.InputText(u8"Auto /ans matni", MainUI.buffers.afkReportReplyText, 256)
    imgui.InputText(u8"/a xabar shabloni ({id})", MainUI.buffers.afkReportAdminHelpText, 128)
    if imgui.InputInt(u8"AFK cooldown (sec)", MainUI.buffers.afkReportCooldown) then
        MainUI.buffers.afkReportCooldown[0] =
            math.max(0, math.min(300, tonumber(MainUI.buffers.afkReportCooldown[0]) or 8))
    end

    if imgui.Button(u8"AFK sozlamani saqlash", imgui.ImVec2(170, 25)) then
        local keywords = UtilityManager.trim(UtilityManager.bufferToString(MainUI.buffers.afkReportKeywords) or "")
        if keywords == "" then
            keywords = "help, yordam, помогите, chin, tuzat, tuzating"
        end

        local replyText = UtilityManager.trim(UtilityManager.bufferToString(MainUI.buffers.afkReportReplyText) or "")
        if replyText == "" then
            replyText = "Assalom alekum, kuzatyapman"
        end

        local adminHelp = UtilityManager.trim(UtilityManager.bufferToString(MainUI.buffers.afkReportAdminHelpText) or "")
        if adminHelp == "" then
            adminHelp = "help {id}"
        end

        local cooldown = math.max(0, math.min(300, tonumber(MainUI.buffers.afkReportCooldown[0]) or 8))

        ReportCatchManager.settings.afkReportKeywords = keywords
        ReportCatchManager.settings.afkReportReplyText = replyText
        ReportCatchManager.settings.afkReportAdminHelpText = adminHelp
        ReportCatchManager.settings.afkReportCooldown = cooldown

        UtilityManager.setBufferString(MainUI.buffers.afkReportKeywords, keywords)
        UtilityManager.setBufferString(MainUI.buffers.afkReportReplyText, replyText)
        UtilityManager.setBufferString(MainUI.buffers.afkReportAdminHelpText, adminHelp)
        MainUI.buffers.afkReportCooldown[0] = cooldown

        ReportCatchManager.saveSettings()
    end

    imgui.TextDisabled(string.format(
        "AFK kalitlar: %s",
        tostring(ReportCatchManager.settings.afkReportKeywords or "")))
    imgui.TextDisabled(string.format(
        "AFK /ans: %s",
        tostring(ReportCatchManager.settings.afkReportReplyText or "")))
    imgui.TextDisabled(string.format(
        "AFK /a shablon: %s",
        tostring(ReportCatchManager.settings.afkReportAdminHelpText or "")))
    imgui.TextDisabled(string.format(
        "AFK cooldown: %ds",
        tonumber(ReportCatchManager.settings.afkReportCooldown) or 8))
    imgui.TextDisabled(u8"Eslatma: AFK bo'lish shart emas, yoqilgan bo'lsa doimiy ishlaydi.")
    imgui.TextDisabled(u8"Trigger bo'lsa: /ans + /sp + (suvda bo'lsa /a) + (ag'darilgan/buzilgan bo'lsa /flip)")
end

function MainUI.renderKerakliAccessGuard(scopeSuffix)
    -- Parol o'chirilgan (Harvey tomonidan)
    MainUI.kerakliAccess.unlocked = true
    ReportCatchManager.kerakliUnlocked = true
    return true
end

function MainUI.renderMpAccessGuard(scopeSuffix)
    -- Parol o'chirilgan (Harvey tomonidan)
    MainUI.mpAccess.unlocked = true
    return true
end

function MainUI.renderKerakliProtected(scopeSuffix)
    if not MainUI.renderKerakliAccessGuard(scopeSuffix) then
        return
    end

    local suffix = tostring(scopeSuffix or "main")
    if imgui.Button("Qulfla##kerakli_lock_" .. suffix, imgui.ImVec2(90, 25)) then
        MainUI.kerakliAccess.unlocked = false
        MainUI.kerakliAccess.lastError = ""
        ReportCatchManager.kerakliUnlocked = false
        UtilityManager.setBufferString(MainUI.buffers.kerakliPassword, "")
        return
    end

    imgui.Separator()
    MainUI.renderKerakliControls({ hideKeywordTp = true, scopeSuffix = tostring(scopeSuffix or "kerakli") })
end

function MainUI.renderKerakli()
    imgui.TextColored(COLORS.WARNING, u8"KERAKLI")
    imgui.TextDisabled(u8"Bu bo'lim admin menyuda alohida tab sifatida chiqarildi.")
    imgui.Separator()
    MainUI.renderKerakliProtected("tab")
end

function MainUI.normalizeMpMessageLine(text)
    local value = UtilityManager.trim(tostring(text or ""))
    if value == "" then
        return ""
    end

    value = value:gsub("^/[Mm][Ss][Gg]%s*", "")
    return UtilityManager.trim(value)
end

function MainUI.getMpEventName()
    local eventName = UtilityManager.trim(UtilityManager.bufferToString(MainUI.buffers.mpEventName) or "")
    if eventName == "" then
        eventName = "Go'sht maydalagich"
        UtilityManager.setBufferString(MainUI.buffers.mpEventName, eventName)
    end
    return eventName
end

function MainUI.buildMpReklamaLines()
    local eventName = MainUI.getMpEventName()
    return {
        "Assalomu alaykum, aziz o'yinchilar!",
        string.format("\"%s\" tadbiri boshlanish arafasida.", eventName),
        "Ishtirok etish uchun hisobotingizga \"+\" belgisini yozing.",
        "Teleportatsiyadan so'ng siz qochishingiz kerak!",
        "Sovrin jamg'armasi: 50 000 rubl."
    }
end

function MainUI.getLocalPlayerId()
    if not PLAYER_PED or type(sampGetPlayerIdByCharHandle) ~= "function" then
        return nil
    end

    local ok, a, b = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
    if not ok then
        return nil
    end

    if type(a) == "boolean" then
        if a then
            return tonumber(b)
        end
        return nil
    end

    return tonumber(a)
end

function MainUI.getPlayerPedHandleById(playerId)
    local id = tonumber(playerId)
    if not id then
        return nil
    end

    if ReportCatchManager and type(ReportCatchManager.getPlayerPedHandle) == "function" then
        return ReportCatchManager.getPlayerPedHandle(id)
    end

    if type(sampGetCharHandleBySampPlayerId) ~= "function" then
        return nil
    end

    local ok, a, b = pcall(sampGetCharHandleBySampPlayerId, id)
    if not ok then
        return nil
    end

    local handle = nil
    if type(a) == "boolean" then
        if a then
            handle = tonumber(b)
        end
    else
        handle = tonumber(a)
    end

    if not handle then
        return nil
    end

    if type(doesCharExist) == "function" then
        local okExists, exists = pcall(doesCharExist, handle)
        if okExists and not exists then
            return nil
        end
    end

    return handle
end

function MainUI.collectPlayersInRadius(radiusValue)
    local radius = math.max(1, math.min(3000, math.floor(tonumber(radiusValue) or 0)))
    local hasLocalCoords, localX, localY, localZ = UtilityManager.getPlayerCoords()
    if not hasLocalCoords then
        return {}, radius
    end

    if type(sampGetMaxPlayerId) ~= "function" or type(sampIsPlayerConnected) ~= "function" then
        return {}, radius
    end

    local maxPlayerId = 1000
    local okMax, a, b = pcall(sampGetMaxPlayerId, false)
    if okMax then
        if type(a) == "boolean" then
            if a and tonumber(b) then
                maxPlayerId = tonumber(b)
            end
        elseif tonumber(a) then
            maxPlayerId = tonumber(a)
        end
    end

    local localPlayerId = MainUI.getLocalPlayerId()
    local targets = {}

    for i = 0, maxPlayerId do
        if sampIsPlayerConnected(i) and (not localPlayerId or i ~= localPlayerId) then
            local ped = MainUI.getPlayerPedHandleById(i)
            if ped and type(getCharCoordinates) == "function" then
                local okPos, x1, y1, z1, z2 = pcall(getCharCoordinates, ped)
                if okPos then
                    local px, py, pz = nil, nil, nil
                    if TeleportClickManager and type(TeleportClickManager.extractCoords) == "function" then
                        px, py, pz = TeleportClickManager.extractCoords(x1, y1, z1, z2)
                    else
                        px, py, pz = tonumber(x1), tonumber(y1), tonumber(z1)
                        if type(x1) == "boolean" and x1 then
                            px, py, pz = tonumber(y1), tonumber(z1), tonumber(z2)
                        end
                    end

                    if px and py and pz then
                        local dx = px - localX
                        local dy = py - localY
                        local dz = pz - localZ
                        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                        if distance <= radius then
                            table.insert(targets, i)
                        end
                    end
                end
            end
        end
    end

    return targets, radius
end

function MainUI.executeRadiusCommand(title, radiusValue, commandBuilder)
    if type(sampSendChat) ~= "function" then
        sampAddChatMessage("[MP] Chat API topilmadi.", 0xFF6666)
        return
    end

    if type(commandBuilder) ~= "function" then
        return
    end

    local targets, radius = MainUI.collectPlayersInRadius(radiusValue)
    if #targets == 0 then
        sampAddChatMessage(string.format("[MP] Radius %d ichida o'yinchi topilmadi.", radius), 0xFF9933)
        return
    end

    local sendAll = function()
        for _, playerId in ipairs(targets) do
            local command = UtilityManager.trim(tostring(commandBuilder(playerId) or ""))
            if command ~= "" then
                sampSendChat(command)
                if type(wait) == "function" then
                    wait(0)
                end
            end
        end
    end

    if lua_thread and type(lua_thread.create) == "function" then
        lua_thread.create(sendAll)
    else
        sendAll()
    end

    sampAddChatMessage(string.format("[MP] %s bajarildi: radius %d, nishonlar %d", tostring(title or "Amal"), radius, #targets), 0x33FF66)
    LogManager.admin(string.format("MP radius action: %s (radius=%d, targets=%d)", tostring(title or "action"), radius, #targets))
end

function MainUI.sendRadiusGun()
    local radius = math.max(1, tonumber(MainUI.buffers.mpGunRadius[0]) or 0)
    local weaponId = math.max(0, tonumber(MainUI.buffers.mpGunId[0]) or 0)
    local ammo = math.max(1, tonumber(MainUI.buffers.mpGunAmmo[0]) or 1)
    MainUI.executeRadiusCommand("Aruja berish (/gun)", radius, function(playerId)
        return string.format("/gun %d %d %d", playerId, weaponId, ammo)
    end)
end

function MainUI.sendRadiusRemoveGun()
    local radius = math.max(1, tonumber(MainUI.buffers.mpRgunRadius[0]) or 0)
    MainUI.executeRadiusCommand("Arujani olish (/rgun)", radius, function(playerId)
        return string.format("/rgun %d", playerId)
    end)
end

function MainUI.sendRadiusHp()
    local radius = math.max(1, tonumber(MainUI.buffers.mpHpRadius[0]) or 0)
    local hpValue = math.max(1, tonumber(MainUI.buffers.mpHpValue[0]) or 1)
    MainUI.executeRadiusCommand("HP berish (/hp)", radius, function(playerId)
        return string.format("/hp %d %d", playerId, hpValue)
    end)
end

function MainUI.sendRadiusSetSkin()
    local radius = math.max(1, tonumber(MainUI.buffers.mpSkinRadius[0]) or 0)
    local skinId = math.max(0, tonumber(MainUI.buffers.mpSkinId[0]) or 0)
    MainUI.executeRadiusCommand("Skin berish (/setskin)", radius, function(playerId)
        return string.format("/setskin %d %d", playerId, skinId)
    end)
end

function MainUI.sendMpBroadcast(lines, title)
    if type(lines) ~= "table" or #lines == 0 then
        return
    end

    if type(sampSendChat) ~= "function" then
        sampAddChatMessage("[Harvey] /msg API topilmadi.", 0xFF6666)
        return
    end

    local sendAll = function()
        for _, rawLine in ipairs(lines) do
            local line = MainUI.normalizeMpMessageLine(rawLine)
            if line ~= "" then
                sampSendChat("/msg " .. line)
                if type(wait) == "function" then
                    wait(0)
                end
            end
        end
    end

    if lua_thread and type(lua_thread.create) == "function" then
        lua_thread.create(sendAll)
    else
        sendAll()
    end

    sampAddChatMessage(string.format("[Harvey] %s yuborildi (%d ta /msg)", tostring(title or "Reklama"), #lines), 0x33FF66)
end

function MainUI.renderMpBroadcastBlock(title, lines, suffix)
    local blockTitle = tostring(title or "Reklama")
    local blockSuffix = tostring(suffix or "default")
    local list = type(lines) == "table" and lines or {}

    if imgui.CollapsingHeader(blockTitle .. "##mp_block_" .. blockSuffix) then
        imgui.BeginChild("##mp_lines_" .. blockSuffix, imgui.ImVec2(0, 120), true)
        for i, rawLine in ipairs(list) do
            local line = MainUI.normalizeMpMessageLine(rawLine)
            if line ~= "" then
                imgui.BulletText(string.format("%d) %s", i, line))
            end
        end
        imgui.EndChild()

        if imgui.Button("Yuborish##mp_send_" .. blockSuffix, imgui.ImVec2(140, 30)) then
            MainUI.sendMpBroadcast(list, blockTitle)
        end
        imgui.SameLine()
        imgui.TextDisabled(string.format("%d ta xabar", #list))
    end
end

function MainUI.renderMP()
    imgui.TextColored(COLORS.INFO or imgui.ImVec4(0.20, 0.60, 0.86, 1.0), "MP")
    imgui.TextDisabled(u8"O'ziga TP va /msg reklama boshqaruvi.")
    imgui.Separator()

    if not MainUI.renderMpAccessGuard("mp") then
        return
    end

    if imgui.Button("Qulfla##mp_lock", imgui.ImVec2(90, 25)) then
        MainUI.mpAccess.unlocked = false
        MainUI.mpAccess.lastError = ""
        UtilityManager.setBufferString(MainUI.buffers.mpPassword, "")
        return
    end

    imgui.Separator()
    if imgui.CollapsingHeader(u8"O'ziga TP qilish") then
        MainUI.renderKerakliControls({ onlyKeywordTp = true, scopeSuffix = "mp" })
    end

    imgui.Separator()
    imgui.Text(u8"MP reklama nomi (faqat shu satr o'zgaradi):")
    imgui.InputText("##mp_event_name", MainUI.buffers.mpEventName, 96)
    MainUI.renderMpBroadcastBlock("MP reklama", MainUI.buildMpReklamaLines(), "mp_reklama")
    MainUI.renderMpBroadcastBlock("Admin reklama", MainUI.mpBroadcasts.adminReklama, "admin_reklama")

    imgui.Separator()
    imgui.TextColored(COLORS.WARNING or imgui.ImVec4(0.95, 0.77, 0.06, 1.0), u8"Radius bo'yicha amallar")

    if imgui.CollapsingHeader(u8"1) Aruja berish (/gun)") then
        imgui.InputInt(u8"Radius##mp_gun_radius", MainUI.buffers.mpGunRadius)
        imgui.InputInt(u8"Aruja ID##mp_gun_weapon", MainUI.buffers.mpGunId)
        imgui.InputInt(u8"O'q soni##mp_gun_ammo", MainUI.buffers.mpGunAmmo)
        if imgui.Button(u8"Aruja berish##mp_gun_apply", imgui.ImVec2(180, 30)) then
            MainUI.sendRadiusGun()
        end
    end

    if imgui.CollapsingHeader(u8"2) Arujani olib qo'yish (/rgun)") then
        imgui.InputInt(u8"Radius##mp_rgun_radius", MainUI.buffers.mpRgunRadius)
        if imgui.Button(u8"Arujani olib qo'yish##mp_rgun_apply", imgui.ImVec2(180, 30)) then
            MainUI.sendRadiusRemoveGun()
        end
    end

    if imgui.CollapsingHeader(u8"3) HP berish (/hp)") then
        imgui.InputInt(u8"Radius##mp_hp_radius", MainUI.buffers.mpHpRadius)
        imgui.InputInt(u8"HP miqdori##mp_hp_value", MainUI.buffers.mpHpValue)
        if imgui.Button(u8"HP berish##mp_hp_apply", imgui.ImVec2(180, 30)) then
            MainUI.sendRadiusHp()
        end
    end

    if imgui.CollapsingHeader(u8"4) Skin berish (/setskin)") then
        imgui.InputInt(u8"Radius##mp_skin_radius", MainUI.buffers.mpSkinRadius)
        imgui.InputInt(u8"Skin ID##mp_skin_id", MainUI.buffers.mpSkinId)
        if imgui.Button(u8"Skin berish##mp_skin_apply", imgui.ImVec2(180, 30)) then
            MainUI.sendRadiusSetSkin()
        end
    end
end

function MainUI.renderReportCatch()
    local enabled = imgui.ImBool(ReportCatchManager.enabled)
    if imgui.Checkbox(u8"Report Catch yoqish", enabled) then
        ReportCatchManager.enabled = enabled[0]
        ReportCatchManager.saveSettings()
    end

    imgui.SameLine()

    if ReportCatchManager.enabled then
        imgui.TextColored(COLORS.PRIMARY, u8"[ACTIVE]")
    else
        imgui.TextColored(COLORS.DANGER, u8"[DISABLED]")
    end

    imgui.Separator()

    if imgui.CollapsingHeader(u8"Hotkey Settings") then
        imgui.Text(u8"Toggle Hotkey: N")
        imgui.TextDisabled(u8"Press N to enable/disable Report Catch")

        local hotkeyItems = {"N"}
        if imgui.BeginCombo(u8"Change Hotkey", "N") then
            for _, key in ipairs(hotkeyItems) do
                if imgui.Selectable(key) then
                end
            end
            imgui.EndCombo()
        end
    end

    if imgui.CollapsingHeader(u8"Popup Settings") then
        local animEnabled = imgui.ImBool(ReportCatchManager.settings.animationEnabled)
        if imgui.Checkbox(u8"Enable Animation", animEnabled) then
            ReportCatchManager.settings.animationEnabled = animEnabled[0]
            ReportCatchManager.saveSettings()
        end

        local soundEnabled = imgui.ImBool(ReportCatchManager.settings.soundEnabled)
        if imgui.Checkbox(u8"Sound Notification", soundEnabled) then
            ReportCatchManager.settings.soundEnabled = soundEnabled[0]
            ReportCatchManager.saveSettings()
        end

        imgui.Spacing()
        imgui.Text(u8"Popup Position:")

        local posX = imgui.ImInt(ReportCatchManager.settings.popupPos.x)
        local posY = imgui.ImInt(ReportCatchManager.settings.popupPos.y)
        if imgui.InputInt(u8"X Position", posX) then
            ReportCatchManager.settings.popupPos.x = posX[0]
        end
        if imgui.InputInt(u8"Y Position", posY) then
            ReportCatchManager.settings.popupPos.y = posY[0]
        end

        imgui.Spacing()
        imgui.Text(u8"Popup Size:")

        local width = imgui.ImInt(ReportCatchManager.settings.popupSize.width)
        local height = imgui.ImInt(ReportCatchManager.settings.popupSize.height)
        if imgui.InputInt(u8"Width", width) then
            ReportCatchManager.settings.popupSize.width = width[0]
        end
        if imgui.InputInt(u8"Height", height) then
            ReportCatchManager.settings.popupSize.height = height[0]
        end
    end

    if imgui.CollapsingHeader(u8"Auto Actions") then
        local autoTP = imgui.ImBool(ReportCatchManager.settings.autoTP)
        if imgui.Checkbox(u8"Auto Teleport to Reporter", autoTP) then
            ReportCatchManager.settings.autoTP = autoTP[0]
            ReportCatchManager.saveSettings()
        end

        local autoSP = imgui.ImBool(ReportCatchManager.settings.autoSP)
        if imgui.Checkbox(u8"Auto Spectate Reporter", autoSP) then
            ReportCatchManager.settings.autoSP = autoSP[0]
            ReportCatchManager.saveSettings()
        end
    end

    if imgui.CollapsingHeader(u8"Kerakli") then
        MainUI.renderKerakliProtected("reportcatch")
    end

    if imgui.CollapsingHeader(u8"Reply Templates") then
        imgui.BeginChild("##TemplateList", imgui.ImVec2(0, 150), true)
        for _, template in ipairs(ReportCatchManager.templates) do
            imgui.Text(string.format("[%d] %s", template.id, template.shortcut))
            imgui.SameLine(100)
            imgui.TextDisabled(template.text:sub(1, 40))
            if #template.text > 40 then
                imgui.TextDisabled("...")
            end
            if imgui.IsItemHovered() then
                imgui.BeginTooltip()
                imgui.Text(template.text)
                imgui.EndTooltip()
            end
        end
        imgui.EndChild()

        imgui.InputText(u8"New Template Text", MainUI.buffers.reason, 256)
        imgui.InputText(u8"Shortcut", MainUI.buffers.search, 64)
        if imgui.Button(u8"Add Template", imgui.ImVec2(120, 25)) then
            ReportCatchManager.addTemplate(UtilityManager.bufferToString(MainUI.buffers.reason), UtilityManager.bufferToString(MainUI.buffers.search))
        end
    end

    if imgui.CollapsingHeader(u8"Queue Management") then
        imgui.Text(string.format("Pending Reports: %d", ReportCatchManager.getQueueCount()))
        imgui.Text(string.format("Max Queue Size: %d", ReportCatchManager.settings.queueLimit))

        if imgui.Button(u8"Clear Queue", imgui.ImVec2(120, 30)) then
            ReportCatchManager.clearQueue()
        end
        imgui.SameLine()
        if imgui.Button(u8"Show Next Report", imgui.ImVec2(140, 30)) then
            if #ReportCatchManager.reportQueue > 0 then
                local nextReport = table.remove(ReportCatchManager.reportQueue)
                ReportCatchManager.showReport(nextReport)
            end
        end
    end

    if imgui.CollapsingHeader(u8"Xavfsizlik") then
        local dedupe = imgui.ImInt(ReportCatchManager.settings.dedupeInterval)
        imgui.InputInt(u8"Duplicate Detection (seconds)", dedupe)

        local limit = imgui.ImInt(ReportCatchManager.settings.queueLimit)
        if imgui.InputInt(u8"Queue Limit", limit) then
            ReportCatchManager.settings.queueLimit = limit[0]
            ReportCatchManager.saveSettings()
        end

        imgui.TextDisabled(u8"Spam and duplicate reports are automatically filtered")
    end

    imgui.Separator()
    if imgui.Button(u8"Test Popup", imgui.ImVec2(120, 30)) then
        ReportCatchManager.showReport({
            id = 999,
            nick = "TestPlayer",
            text = "Bu test report matni. Haqiqiy reportni sinash uchun.",
            time = os.time(),
            formattedTime = os.date("%H:%M:%S"),
            playerId = 0
        })
    end
    imgui.SameLine()
    if imgui.Button(u8"Force Close", imgui.ImVec2(120, 30)) then
        ReportCatchManager.closePopup()
    end
end

function MainUI.renderPlayerManagement()
    imgui.Text(u8"Target Player:")
    imgui.InputInt(u8"Player ID", MainUI.buffers.playerId)
    imgui.SameLine()
    if imgui.Button(u8"Online List", imgui.ImVec2(100, 25)) then
        imgui.OpenPopup("##OnlineListPopup")
    end

    if imgui.BeginPopup("##OnlineListPopup") then
        local players = PlayerManager.getOnlineList()
        for _, player in ipairs(players) do
            if imgui.Selectable(string.format("[%d] %s (Ping: %d)",
                player.id, player.name, player.ping)) then
                MainUI.buffers.playerId[0] = player.id
            end
        end
        imgui.EndPopup()
    end

    local playerId = MainUI.buffers.playerId[0]
    if sampIsPlayerConnected(playerId) then
        imgui.TextDisabled(string.format("Selected: %s", sampGetPlayerNickname(playerId)))
    end

    imgui.Separator()

    if imgui.CollapsingHeader(u8"Punishments") then
        imgui.InputText(u8"Sabab", MainUI.buffers.reason, 256)
        imgui.InputInt(u8"Duration (min/hours)", MainUI.buffers.duration)

        if imgui.Button(u8"Chiqarish", imgui.ImVec2(80, 25)) then
            PlayerManager.kick(playerId, UtilityManager.bufferToString(MainUI.buffers.reason))
        end
        imgui.SameLine()
        if imgui.Button(u8"Ban", imgui.ImVec2(80, 25)) then
            PlayerManager.ban(playerId, UtilityManager.bufferToString(MainUI.buffers.reason))
        end
        imgui.SameLine()
        if imgui.Button(u8"TempBan", imgui.ImVec2(80, 25)) then
            PlayerManager.ban(playerId, UtilityManager.bufferToString(MainUI.buffers.reason), MainUI.buffers.duration[0])
        end
        imgui.SameLine()
        if imgui.Button(u8"Sukut", imgui.ImVec2(80, 25)) then
            PlayerManager.mute(playerId, MainUI.buffers.duration[0], UtilityManager.bufferToString(MainUI.buffers.reason))
        end
        imgui.SameLine()
        if imgui.Button(u8"Jail", imgui.ImVec2(80, 25)) then
            PlayerManager.jail(playerId, MainUI.buffers.duration[0], UtilityManager.bufferToString(MainUI.buffers.reason))
        end
        imgui.SameLine()
        if imgui.Button(u8"Ogohlantirish", imgui.ImVec2(80, 25)) then
            PlayerManager.warn(playerId, UtilityManager.bufferToString(MainUI.buffers.reason))
        end

        if imgui.Button(u8"Sukutni olish", imgui.ImVec2(80, 25)) then
            PlayerManager.unmute(playerId)
        end
        imgui.SameLine()
        if imgui.Button(u8"Unjail", imgui.ImVec2(80, 25)) then
            PlayerManager.unjail(playerId)
        end
        imgui.SameLine()
        if imgui.Button(u8"Unwarn", imgui.ImVec2(80, 25)) then
            PlayerManager.unwarn(playerId)
        end
        imgui.SameLine()
        if imgui.Button(u8"Clear Warns", imgui.ImVec2(90, 25)) then
            PlayerManager.clearWarns(playerId)
        end
    end

    if imgui.CollapsingHeader(u8"Health & Stats") then
        imgui.InputInt(u8"HP Amount", MainUI.buffers.amount)

        if imgui.Button(u8"Set HP", imgui.ImVec2(80, 25)) then
            PlayerManager.setHP(playerId, MainUI.buffers.amount[0])
        end
        imgui.SameLine()
        if imgui.Button(u8"Set Armor", imgui.ImVec2(80, 25)) then
            PlayerManager.setArmor(playerId, MainUI.buffers.amount[0])
        end
        imgui.SameLine()
        if imgui.Button(u8"Davolash", imgui.ImVec2(80, 25)) then
            PlayerManager.heal(playerId)
        end
        imgui.SameLine()
        if imgui.Button(u8"Armor Refill", imgui.ImVec2(90, 25)) then
            PlayerManager.armorRefill(playerId)
        end

        imgui.InputInt(u8"Money/Level", MainUI.buffers.amount)
        if imgui.Button(u8"Give Money", imgui.ImVec2(100, 25)) then
            PlayerManager.giveMoney(playerId, MainUI.buffers.amount[0])
        end
        imgui.SameLine()
        if imgui.Button(u8"Set Level", imgui.ImVec2(100, 25)) then
            PlayerManager.setLevel(playerId, MainUI.buffers.amount[0])
        end
        imgui.SameLine()
        if imgui.Button(u8"Set Skin", imgui.ImVec2(100, 25)) then
            PlayerManager.setSkin(playerId, MainUI.buffers.amount[0])
        end
    end

    if imgui.CollapsingHeader(u8"Teleport & Actions") then
        if imgui.Button(u8"Borishni", imgui.ImVec2(80, 25)) then
            PlayerManager.teleportTo(playerId)
        end
        imgui.SameLine()
        if imgui.Button(u8"Get Here", imgui.ImVec2(80, 25)) then
            PlayerManager.bring(playerId)
        end
        imgui.SameLine()
        if imgui.Button(u8"Kuzatish", imgui.ImVec2(80, 25)) then
            PlayerManager.spectate(playerId)
        end
        imgui.SameLine()
        if imgui.Button(u8"Qotirish", imgui.ImVec2(80, 25)) then
            PlayerManager.freeze(playerId)
        end
        imgui.SameLine()
        if imgui.Button(u8"Qotishni olish", imgui.ImVec2(80, 25)) then
            PlayerManager.unfreeze(playerId)
        end

        if imgui.Button(u8"Slap", imgui.ImVec2(80, 25)) then
            PlayerManager.slap(playerId)
        end
        imgui.SameLine()
        if imgui.Button(u8"Disarm", imgui.ImVec2(80, 25)) then
            PlayerManager.disarm(playerId)
        end
        imgui.SameLine()
        if imgui.Button(u8"Check Stats", imgui.ImVec2(90, 25)) then
            PlayerManager.statsCheck(playerId)
        end
        imgui.SameLine()
        if imgui.Button(u8"Inventory", imgui.ImVec2(90, 25)) then
            PlayerManager.inventoryCheck(playerId)
        end
    end

    if imgui.CollapsingHeader(u8"Interior & VW") then
        imgui.InputInt(u8"Interior ID", MainUI.buffers.duration)
        if imgui.Button(u8"Set Interior", imgui.ImVec2(100, 25)) then
            PlayerManager.setInterior(playerId, MainUI.buffers.duration[0])
        end
        imgui.SameLine()
        imgui.InputInt(u8"VW ID", MainUI.buffers.amount)
        imgui.SameLine()
        if imgui.Button(u8"Set VW", imgui.ImVec2(80, 25)) then
            PlayerManager.setVirtualWorld(playerId, MainUI.buffers.amount[0])
        end
    end
end

function MainUI.renderTeleportSystem()
    imgui.Text(u8"Tadbir teleportlari:")

    local eventTeleports = {
        { name = u8"Labirint", x = -413.863, y = -1746.627, z = 1199.865 },
        { name = u8"Qurollar poygasi", x = 2579.394, y = -2336.619, z = 1206.085 },
        { name = u8"Hellouin", x = 1281.344, y = 258.192, z = 1296.038 },
        { name = u8"Bank", x = -259.460, y = 1832.385, z = 1205.060 },
        { name = u8"Karting", x = -1280.336, y = -2455.017, z = 1207.449 },
        { name = u8"Omon qolish", x = 1038.759, y = 1832.604, z = 1210.139 },
        { name = u8"Qamoqxona", x = -1879.807, y = -1763.518, z = 1210.139 },
        { name = u8"Muzli labirint", x = -1039.179, y = 205.692, z = 1202.792 },
        { name = u8"Samolyot", x = -2062.170, y = -2460.885, z = 1205.545 },
        { name = u8"Otxona", x = 800.215, y = 2627.931, z = 1202.210 },
        { name = u8"Sovg'alar zavodi", x = 2177.467, y = 1162.572, z = 1201.951 },
        { name = u8"1xBet", x = 1126.926, y = -1074.470, z = 1195.282 },
        { name = u8"Kasino", x = -1672.516, y = -351.303, z = 1205.190 },
        { name = u8"Yashil maydon", x = 1043.603, y = -2491.291, z = 1185.933 },
        { name = u8"Vulkan", x = 274.486, y = 254.193, z = 1276.787 },
        { name = u8"Lava", x = 310.303, y = 319.771, z = 1276.548 },
        { name = u8"Maktab", x = 373.237, y = 1826.968, z = 1208.051 },
        { name = u8"Aylana derbi", x = 1636.648, y = -1136.465, z = 1201.039 },
        { name = u8"Ormon", x = 1102.402, y = -2441.989, z = 1186.846 },
        { name = u8"Duel", x = 544.652, y = 1164.850, z = 1202.023 }
    }

    for i, tp in ipairs(eventTeleports) do
        local label = string.format("%s##eventtp%d", tp.name, i)
        if imgui.Button(label, imgui.ImVec2(160, 30)) then
            TeleportManager.teleportToCoords(tp.x, tp.y, tp.z)
            LogManager.admin(string.format("Teleported to %s", tp.name))
        end
        if i % 3 ~= 0 then
            imgui.SameLine()
        end
    end

    imgui.Separator()

    if imgui.CollapsingHeader(u8"Coordinate Teleport") then
        imgui.InputFloat(u8"X", MainUI.buffers.coordX)
        imgui.InputFloat(u8"Y", MainUI.buffers.coordY)
        imgui.InputFloat(u8"Z", MainUI.buffers.coordZ)
        if imgui.Button(u8"Teleport to Coords", imgui.ImVec2(150, 30)) then
            TeleportManager.teleportToCoords(
                MainUI.buffers.coordX[0],
                MainUI.buffers.coordY[0],
                MainUI.buffers.coordZ[0]
            )
        end
        imgui.SameLine()
        if imgui.Button(u8"Get Current Coords", imgui.ImVec2(150, 30)) then
            local result, x, y, z = UtilityManager.getPlayerCoords()
            if result then
                MainUI.buffers.coordX[0] = x
                MainUI.buffers.coordY[0] = y
                MainUI.buffers.coordZ[0] = z
            end
        end
    end

    if imgui.CollapsingHeader(u8"Interiors") then
        for _, interior in ipairs(TeleportManager.interiors) do
            if imgui.Button(string.format("%s##int%d", interior.name, interior.id),
                           imgui.ImVec2(120, 25)) then
                TeleportManager.teleportToInterior(interior.id)
            end
            if (interior.id + 1) % 4 ~= 0 then
                imgui.SameLine()
            end
        end
    end

    if imgui.CollapsingHeader(u8"Virtual Worlds") then
        for _, vw in ipairs(TeleportManager.virtualWorlds) do
            if imgui.Button(string.format("%s##vw%d", vw.name, vw.id),
                           imgui.ImVec2(120, 25)) then
                TeleportManager.teleportToVirtualWorld(vw.id)
            end
            if (vw.id + 1) % 4 ~= 0 then
                imgui.SameLine()
            end
        end
    end

    if imgui.CollapsingHeader(u8"Special Teleports") then
        if imgui.Button(u8"To Waypoint", imgui.ImVec2(120, 25)) then
            TeleportManager.teleportToWaypoint()
        end
        imgui.SameLine()
        if imgui.Button(u8"Last Death", imgui.ImVec2(120, 25)) then
            TeleportManager.teleportToLastDeath()
        end
        imgui.SameLine()
        if imgui.Button(u8"Random", imgui.ImVec2(120, 25)) then
            TeleportManager.randomTeleport()
        end

        imgui.InputInt(u8"Player ID", MainUI.buffers.playerId)
        if imgui.Button(u8"Teleport to Player", imgui.ImVec2(150, 25)) then
            TeleportManager.teleportToPlayer(MainUI.buffers.playerId[0])
        end
    end

    if imgui.CollapsingHeader(u8"Saved Locations") then
        if #TeleportManager.savedLocations == 0 then
            imgui.TextDisabled(u8"No saved locations")
        else
            for _, loc in ipairs(TeleportManager.savedLocations) do
                if imgui.Button(loc.name, imgui.ImVec2(150, 25)) then
                    TeleportManager.teleportToLocation(loc.name)
                end
                imgui.SameLine()
                imgui.TextDisabled(string.format("(%.1f, %.1f, %.1f)", loc.x, loc.y, loc.z))
            end
        end

        if imgui.Button(u8"Save Current Location", imgui.ImVec2(180, 30)) then
            TeleportManager.saveLocation()
        end
    end
end

function MainUI.renderServerControl()
    if imgui.CollapsingHeader(u8"Online Players") then
        imgui.BeginChild("##OnlineList", imgui.ImVec2(0, 150), true)
        local players = PlayerManager.getOnlineList()
        for _, player in ipairs(players) do
            imgui.Text(string.format("[%d] %s - Score: %d - Ping: %d",
                player.id, player.name, player.score, player.ping))
        end
        imgui.EndChild()
    end

    if imgui.CollapsingHeader(u8"Server Settings") then
        imgui.InputInt(u8"Server Hour", MainUI.buffers.duration)
        if imgui.Button(u8"Set Time", imgui.ImVec2(100, 25)) then
            ServerManager.setServerTime(MainUI.buffers.duration[0])
        end

        imgui.SameLine()
        imgui.InputInt(u8"Weather ID", MainUI.buffers.amount)
        imgui.SameLine()
        if imgui.Button(u8"Set Weather", imgui.ImVec2(100, 25)) then
            ServerManager.setWeather(MainUI.buffers.amount[0])
        end
    end

    if imgui.CollapsingHeader(u8"Announcements") then
        imgui.InputText(u8"Xabar", MainUI.buffers.reason, 256)
        if imgui.Button(u8"Global Announce", imgui.ImVec2(130, 25)) then
            ServerManager.globalAnnouncement(UtilityManager.bufferToString(MainUI.buffers.reason))
        end
        imgui.SameLine()
        if imgui.Button(u8"Clear Chat", imgui.ImVec2(100, 25)) then
            ServerManager.clearChat()
        end
    end

    if imgui.CollapsingHeader(u8"Server Management") then
        imgui.InputInt(u8"Restart in (minutes)", MainUI.buffers.duration)
        if imgui.Button(u8"Schedule Restart", imgui.ImVec2(130, 25)) then
            ServerManager.scheduleRestart(MainUI.buffers.duration[0])
        end

        imgui.SameLine()
        local eventMode = imgui.ImBool(ServerManager.eventMode)
        if imgui.Checkbox(u8"Event Mode", eventMode) then
            ServerManager.toggleEventMode()
        end

        if imgui.Button(u8"Lock Server", imgui.ImVec2(100, 25)) then
            ServerManager.lockServer()
        end
        imgui.SameLine()
        if imgui.Button(u8"Unlock Server", imgui.ImVec2(100, 25)) then
            ServerManager.unlockServer()
        end
    end

    if imgui.CollapsingHeader(u8"Server Statistics") then
        local entities = ServerManager.getEntityCount()
        imgui.Text(string.format("Memory: %.2f KB", ServerManager.getMemoryUsage()))
        imgui.Text(string.format("Server FPS: %d", ServerManager.getServerFPS()))
        imgui.Text(string.format("Vehicles: %d | Objects: %d", entities.vehicles, entities.objects))
    end
end

function MainUI.renderSecurityCenter()
    imgui.InputInt(u8"Target Player ID", MainUI.buffers.playerId)

    local playerId = MainUI.buffers.playerId[0]

    imgui.Separator()
    imgui.Text(u8"Security Checks:")
    if imgui.Button(u8"IP Check", imgui.ImVec2(100, 25)) then
        SecurityManager.ipCheck(playerId)
    end
    imgui.SameLine()
    if imgui.Button(u8"Serial Check", imgui.ImVec2(100, 25)) then
        SecurityManager.serialCheck(playerId)
    end
    imgui.SameLine()
    if imgui.Button(u8"Multi-Account", imgui.ImVec2(100, 25)) then
        SecurityManager.detectMultiAccount(playerId)
    end
    imgui.SameLine()
    if imgui.Button(u8"Speed Hack", imgui.ImVec2(100, 25)) then
        SecurityManager.detectSpeedHack(playerId)
    end

    if imgui.CollapsingHeader(u8"Hack Detection") then
        if imgui.Button(u8"Health Hack Check", imgui.ImVec2(130, 25)) then
            SecurityManager.detectHealthHack(playerId)
        end
        imgui.SameLine()
        if imgui.Button(u8"Teleport Hack Check", imgui.ImVec2(140, 25)) then
            SecurityManager.detectTeleportHack(playerId)
        end
        imgui.SameLine()
        if imgui.Button(u8"Movement Check", imgui.ImVec2(130, 25)) then
            SecurityManager.detectSuspiciousMovement(playerId)
        end
    end

    if imgui.CollapsingHeader(u8"Blacklist") then
        imgui.InputText(u8"ID/Name", MainUI.buffers.reason, 256)
        imgui.InputInt(u8"Type (1=ID, 2=Serial, 3=IP)", MainUI.buffers.amount)

        if imgui.Button(u8"Add to Blacklist", imgui.ImVec2(130, 25)) then
            local types = {"id", "serial", "ip"}
            SecurityManager.addToBlacklist(UtilityManager.bufferToString(MainUI.buffers.reason),
                types[MainUI.buffers.amount[0]] or "id", "Manual add")
        end
        imgui.SameLine()
        if imgui.Button(u8"Remove from Blacklist", imgui.ImVec2(160, 25)) then
            SecurityManager.removeFromBlacklist(UtilityManager.bufferToString(MainUI.buffers.reason))
        end

        imgui.TextDisabled(string.format("Blacklisted: %d entries", #SecurityManager.blacklist))
    end

    if imgui.CollapsingHeader(u8"Whitelist") then
        imgui.InputText(u8"ID/Name", MainUI.buffers.reason, 256)
        if imgui.Button(u8"Add to Whitelist", imgui.ImVec2(140, 25)) then
            SecurityManager.addToWhitelist(UtilityManager.bufferToString(MainUI.buffers.reason))
        end
        imgui.SameLine()
        if imgui.Button(u8"Remove from Whitelist", imgui.ImVec2(170, 25)) then
            SecurityManager.removeFromWhitelist(UtilityManager.bufferToString(MainUI.buffers.reason))
        end
    end

    if imgui.CollapsingHeader(u8"Chat Filter") then
        local filterEnabled = imgui.ImBool(true)
        imgui.Checkbox(u8"Enable Filter", filterEnabled)

        imgui.Text(u8"Filtered Words:")
        for _, word in ipairs(SecurityManager.chatFilter) do
            imgui.BulletText(word)
        end
    end

    if imgui.Button(u8"Export Security Log", imgui.ImVec2(150, 30)) then
        SecurityManager.exportSecurityLog(getWorkingDirectory() .. "/security_" .. os.time() .. ".txt")
    end
end

function MainUI.renderAnalytics()
    imgui.Columns(2, "##AnalyticsCols", false)

    imgui.TextColored(COLORS.PRIMARY, u8"REPORT STATISTIKASI")
    imgui.Text(string.format("Hozir: %d", StatsManager.data.session.answers))
    for i = 1, 7 do
        local day = StatsManager.getWeekdayData(i)
        imgui.Text(string.format("%s: %d", StatsManager.getWeekdayLabel(i), day.answers or 0))
    end
    imgui.Text(string.format("Shu oy: %d", StatsManager.data.monthly.answers))

    imgui.NextColumn()

    imgui.TextColored(COLORS.SECONDARY, u8"VAQT STATISTIKASI")
    imgui.Text(string.format("Hozir: %s", UtilityManager.formatTime(StatsManager.data.session.playtime or 0)))
    for i = 1, 7 do
        local day = StatsManager.getWeekdayData(i)
        imgui.Text(string.format("%s: %s", StatsManager.getWeekdayLabel(i),
            UtilityManager.formatTime(day.playtime or 0)))
    end
    imgui.Text(string.format("Shu oy: %s", UtilityManager.formatTime(StatsManager.data.monthly.playtime)))

    imgui.Columns(1)
    imgui.Separator()

    if imgui.CollapsingHeader(u8"Performance Metrics") then
        imgui.Text(string.format("Efficiency: %.1f%%", StatsManager.data.efficiency))
        imgui.Text(string.format("Performance Score: %d", StatsManager.getPerformanceScore()))
        imgui.Text(string.format("Weekly Trend: %d%%", StatsManager.getWeeklyTrend()))

        local trend = StatsManager.getWeeklyTrend()
        local trendColor = trend >= 0 and COLORS.PRIMARY or COLORS.DANGER
        local trendIcon = trend >= 0 and "+" or ""
        imgui.TextColored(trendColor, string.format("Trend: %s%d%%", trendIcon, trend))
    end

    if imgui.CollapsingHeader(u8"Activity Charts") then
        local values = {0.3, 0.5, 0.8, 0.6, 0.9, 0.7, 0.85}
        if imgui.PlotHistogram then
            imgui.PlotHistogram("##Activity", values, #values, 0, "Activity", 0, 1, imgui.ImVec2(0, 80))
        else
            imgui.TextDisabled("Activity chart not supported by your mimgui build")
        end
    end

    imgui.Separator()
    imgui.Text(u8"Export Data:")
    if imgui.Button(u8"Export to TXT", imgui.ImVec2(120, 30)) then
        AnalyticsManager.exportToTxt(getWorkingDirectory() .. "/analytics_" .. os.time() .. ".txt")
    end
    imgui.SameLine()
    if imgui.Button(u8"Export to JSON", imgui.ImVec2(120, 30)) then
        AnalyticsManager.exportToJson(getWorkingDirectory() .. "/analytics_" .. os.time() .. ".json")
    end
    imgui.SameLine()
    if imgui.Button(u8"Compare Week", imgui.ImVec2(120, 30)) then
        local comp = AnalyticsManager.comparePreviousWeek()
        print(string.format("Comparison: %d%%", comp.percentage))
    end
end

function MainUI.renderUtilities()
    if imgui.CollapsingHeader(u8"Transport") then
        imgui.InputInt(u8"Vehicle ID", MainUI.buffers.amount)
        if imgui.Button(u8"Spawn Vehicle", imgui.ImVec2(120, 30)) then
            LogManager.admin(string.format("Spawned vehicle %d", MainUI.buffers.amount[0]))
        end
        imgui.SameLine()
        if imgui.Button(u8"Repair Vehicle", imgui.ImVec2(120, 30)) then
        end
    end

    if imgui.CollapsingHeader(u8"Admin Modes") then
        local godMode = imgui.ImBool(SettingsManager.get("godMode"))
        if imgui.Checkbox(u8"Xudo rejimi", godMode) then
            SettingsManager.set("godMode", godMode[0])
            if godMode[0] then
                AdminModesManager.warnedGodUnsupported = false
                AdminModesManager.applyGodMode(true)
                sampAddChatMessage("[Harvey] Xudo rejimi: YOQIQ", 0x33FF66)
            else
                AdminModesManager.applyGodMode(false)
                sampAddChatMessage("[Harvey] Xudo rejimi: O'CHIQ", 0xFF9933)
            end
        end

        local invisible = imgui.ImBool(SettingsManager.get("invisible"))
        if imgui.Checkbox(u8"Invisible Mode", invisible) then
            SettingsManager.set("invisible", invisible[0])
            if invisible[0] then
                AdminModesManager.warnedInvisibleUnsupported = false
                AdminModesManager.applyInvisibleMode(true)
                sampAddChatMessage("[Harvey] Ko'rinmaslik rejimi: YOQIQ", 0x33FF66)
            else
                AdminModesManager.applyInvisibleMode(false)
                sampAddChatMessage("[Harvey] Ko'rinmaslik rejimi: O'CHIQ", 0xFF9933)
            end
        end

        local adminDuty = imgui.ImBool(SettingsManager.get("adminDuty"))
        if imgui.Checkbox(u8"Admin Duty", adminDuty) then
            SettingsManager.set("adminDuty", adminDuty[0])
            sampSendChat(adminDuty[0] and "/aduty on" or "/aduty off")
        end
    end

    if imgui.CollapsingHeader(u8"Movement") then
        local speedBoost = imgui.ImBool(false)
        imgui.Checkbox(u8"Speed Boost", speedBoost)

        local noRecoil = imgui.ImBool(false)
        imgui.Checkbox(u8"No Recoil", noRecoil)
    end

    if imgui.CollapsingHeader(u8"Quick Commands") then
        if imgui.Button(u8"Admin Chat", imgui.ImVec2(100, 25)) then
        end
        imgui.SameLine()
        if imgui.Button(u8"Report List", imgui.ImVec2(100, 25)) then
        end
        imgui.SameLine()
        if imgui.Button(u8"Help", imgui.ImVec2(100, 25)) then
        end
    end

    if imgui.CollapsingHeader(u8"Notifications") then
        local notifications = imgui.ImBool(SettingsManager.get("notifications"))
        if imgui.Checkbox(u8"Enable Notifications", notifications) then
            SettingsManager.set("notifications", notifications[0])
        end

        local soundEnabled = imgui.ImBool(SettingsManager.get("soundEnabled"))
        if imgui.Checkbox(u8"Sound Effects", soundEnabled) then
            SettingsManager.set("soundEnabled", soundEnabled[0])
        end
    end
end

function MainUI.renderFuraMonitor()
    local enabled = imgui.ImBool(FuraKillManager.enabled)
    if imgui.Checkbox(u8"Enable Fura Kill Monitor", enabled) then
        FuraKillManager.setEnabled(enabled[0])
    end
    imgui.SameLine()
    if FuraKillManager.enabled then
        imgui.TextColored(COLORS.PRIMARY or imgui.ImVec4(0.15, 0.68, 0.38, 1.0), "[ON]")
    else
        imgui.TextColored(COLORS.DANGER or imgui.ImVec4(0.90, 0.30, 0.30, 1.0), "[OFF]")
    end

    local activeState = "Idle"
    if FuraKillManager.activeCheck then
        local phase = FuraKillManager.activeCheck.phase or "pending"
        local side = FuraKillManager.activeCheck[phase]
        if side then
            activeState = string.format("Checking %s: %s", phase, FuraKillManager.playerLabel(side.id, side.nick))
        else
            activeState = "Checking"
        end
    end

    imgui.TextDisabled(string.format("Queue: %d | Tracked Kills: %d | State: %s",
        #FuraKillManager.pendingChecks, #FuraKillManager.kills, activeState))
    imgui.TextDisabled("Rule: killer/victim  ichida jinoiy guruh matni qayerda kelsa ham hisoblanadi")

    if imgui.Button(u8"Export TXT", imgui.ImVec2(120, 30)) then
        local path = getWorkingDirectory() .. "/fura_kills_" .. os.time() .. ".txt"
        local ok = FuraKillManager.exportToTxt(path)
        if ok then
            sampAddChatMessage("[Harvey] Fura kill eksporti saqlandi: " .. path, 0x33FF66)
        else
            sampAddChatMessage("[Harvey] Fura kill eksporti muvaffaqiyatsiz", 0xFF6666)
        end
    end
    imgui.SameLine()
    if imgui.Button(u8"Clear List", imgui.ImVec2(120, 30)) then
        FuraKillManager.clearData()
    end

    if FuraKillManager.lastExportPath ~= "" then
        imgui.TextDisabled("Last export: " .. FuraKillManager.lastExportPath)
    end

    imgui.Separator()
    imgui.TextColored(COLORS.INFO or imgui.ImVec4(0.20, 0.60, 0.86, 1.0), u8"Summary")

    local top = FuraKillManager.getTopKiller()
    if top then
        imgui.Text(string.format("Eng kop kill qilgan: %s - %d",
            FuraKillManager.playerLabel(top.id, top.nick), top.kills))
    else
        imgui.Text("Eng kop kill qilgan: N/A")
    end

    if FuraKillManager.firstKill then
        local firstCount = (FuraKillManager.killerStats[tostring(FuraKillManager.firstKill.killerId)] or {}).kills or 1
        imgui.Text(string.format("Eng birinchi kill qilgan: %s - %d",
            FuraKillManager.playerLabel(FuraKillManager.firstKill.killerId, FuraKillManager.firstKill.killerNick),
            firstCount))
    else
        imgui.Text("Eng birinchi kill qilgan: N/A")
    end

    if FuraKillManager.lastKill then
        local lastCount = (FuraKillManager.killerStats[tostring(FuraKillManager.lastKill.killerId)] or {}).kills or 1
        imgui.Text(string.format("Eng oxirgi kill qilgan: %s - %d",
            FuraKillManager.playerLabel(FuraKillManager.lastKill.killerId, FuraKillManager.lastKill.killerNick),
            lastCount))
    else
        imgui.Text("Eng oxirgi kill qilgan: N/A")
    end
    imgui.Text(string.format("TK (bir xil guruh): %d", FuraKillManager.getTeamKillCount()))

    imgui.Separator()

    if imgui.CollapsingHeader(u8"Killerlar ro'yxati") then
        local killers = FuraKillManager.getSortedKillerStats()
        if #killers == 0 then
            imgui.TextDisabled("No killers tracked yet")
        else
            for _, entry in ipairs(killers) do
                imgui.BulletText(string.format("%s - %d",
                    FuraKillManager.playerLabel(entry.id, entry.nick), entry.kills))
            end
        end
    end

    if imgui.CollapsingHeader(u8"Guruh bo'yicha kill") then
        local groupStats = FuraKillManager.getSortedGroupStats(FuraKillManager.groupKillStats)
        if #groupStats == 0 then
            imgui.TextDisabled("No groups tracked yet")
        else
            for _, entry in ipairs(groupStats) do
                imgui.BulletText(string.format("%s - %d", tostring(entry.group), tonumber(entry.count) or 0))
            end
        end
    end

    if imgui.CollapsingHeader(u8"TK (bir xil guruh)") then
        local tkStats = FuraKillManager.getSortedGroupStats(FuraKillManager.teamKillStats)
        if #tkStats == 0 then
            imgui.TextDisabled("No TK tracked yet")
        else
            for _, entry in ipairs(tkStats) do
                imgui.BulletText(string.format("%s - %d", tostring(entry.group), tonumber(entry.count) or 0))
            end
        end
    end

    if imgui.CollapsingHeader(u8"Kill log (o'ldirgan | o'lgan)") then
        imgui.BeginChild("##FuraKillLog", imgui.ImVec2(0, 220), true)
        if #FuraKillManager.kills == 0 then
            imgui.TextDisabled("No tracked kills")
        else
            for i = #FuraKillManager.kills, 1, -1 do
                local record = FuraKillManager.kills[i]
                local killerGroup = UtilityManager.trim(tostring(record.killerGroup or ""))
                local victimGroup = UtilityManager.trim(tostring(record.victimGroup or ""))
                if killerGroup == "" then killerGroup = "Noma'lum guruh" end
                if victimGroup == "" then victimGroup = "Noma'lum guruh" end
                local tkText = record.isTeamKill and " [TK]" or ""
                imgui.Text(string.format("%s: %s oldirdi %s%s",
                    string.format("%s -> %s", killerGroup, victimGroup),
                    FuraKillManager.playerLabel(record.killerId, record.killerNick),
                    FuraKillManager.playerLabel(record.victimId, record.victimNick),
                    tkText))
                imgui.SameLine()
                imgui.TextDisabled(record.formattedTime or "")
            end
        end
        imgui.EndChild()
    end
end

function MainUI.renderSettings()
    if imgui.CollapsingHeader(u8"Appearance") then
        local themeItems = {"Dark", "Light", "Auto"}
        local currentTheme = 1
        if imgui.BeginCombo(u8"Theme", themeItems[currentTheme]) then
            for i, theme in ipairs(themeItems) do
                if imgui.Selectable(theme, currentTheme == i) then
                    SettingsManager.set("theme", theme:lower())
                end
            end
            imgui.EndCombo()
        end

        imgui.Text(u8"Primary Color:")
        if not MainUI.buffers.primaryColor then
            MainUI.buffers.primaryColor = imgui.new.float[3]()
            MainUI.buffers.primaryColor[0] = 0.15
            MainUI.buffers.primaryColor[1] = 0.68
            MainUI.buffers.primaryColor[2] = 0.38
        end
        imgui.ColorEdit3("##PrimaryColor", MainUI.buffers.primaryColor)
    end

    if imgui.CollapsingHeader(u8"Hotkeys") then
        imgui.Text(string.format("Current Toggle Key: %s", SettingsManager.getHotkeyName()))
        imgui.TextDisabled(u8"Press M to toggle panel")
    end

    if imgui.CollapsingHeader(u8"AFK Settings") then
        local afkEnabled = imgui.ImBool(SettingsManager.get("afkEnabled"))
        if imgui.Checkbox(u8"Enable AFK Detection", afkEnabled) then
            SettingsManager.set("afkEnabled", afkEnabled[0])
        end

        imgui.TextDisabled(string.format("AFK Timeout: %d seconds", CONFIG.AFK_TIMEOUT))
    end

    if imgui.CollapsingHeader(u8"Auto Save") then
        local autoSave = imgui.ImBool(SettingsManager.get("autoSave"))
        if imgui.Checkbox(u8"Enable Auto Save", autoSave) then
            SettingsManager.set("autoSave", autoSave[0])
        end

        imgui.TextDisabled(string.format("Save Interval: %d seconds", CONFIG.AUTO_SAVE_INTERVAL))
    end

    if imgui.CollapsingHeader(u8"Language") then
        local langItems = {"Uzbek", "English", "Russian"}
        local currentLang = 1
        if imgui.BeginCombo(u8"Language", langItems[currentLang]) then
            for i, lang in ipairs(langItems) do
                if imgui.Selectable(lang, currentLang == i) then
                    SettingsManager.set("language", lang:lower():sub(1, 2))
                end
            end
            imgui.EndCombo()
        end
    end

    if imgui.CollapsingHeader(u8"HUD Settings") then
        local clockEnabled = imgui.ImBool(HudManager.clock.enabled)
        if imgui.Checkbox(u8"Enable Clock HUD", clockEnabled) then
            HudManager.clock.enabled = clockEnabled[0]
            SettingsManager.set("hudClockEnabled", HudManager.clock.enabled)
        end

        local dateEnabled = imgui.ImBool(HudManager.dateBar.enabled)
        if imgui.Checkbox(u8"Enable Date HUD", dateEnabled) then
            HudManager.dateBar.enabled = dateEnabled[0]
            SettingsManager.set("hudDateEnabled", HudManager.dateBar.enabled)
        end

        local adminEnabled = imgui.ImBool(HudManager.adminBar.enabled)
        if imgui.Checkbox(u8"Enable Admin HUD", adminEnabled) then
            HudManager.adminBar.enabled = adminEnabled[0]
            SettingsManager.set("hudAdminEnabled", HudManager.adminBar.enabled)
        end

        local editMode = imgui.ImBool(HudManager.editMode)
        if imgui.Checkbox(u8"Enable Drag Mode", editMode) then
            HudManager.setEditMode(editMode[0])
        end

        if imgui.Button(u8"Reset HUD Positions", imgui.ImVec2(180, 28)) then
            HudManager.resetPositions()
        end

        local hudScale = imgui.ImFloat(HudManager.scale or 1.0)
        if imgui.SliderFloat(u8"Change HUD Scale", hudScale, 0.75, 1.75, "%.2f") then
            HudManager.setScale(hudScale[0])
        end

        local hudOpacity = imgui.ImFloat(HudManager.opacity or 1.0)
        if imgui.SliderFloat(u8"Change HUD Opacity", hudOpacity, 0.25, 1.0, "%.2f") then
            HudManager.setOpacity(hudOpacity[0])
        end

        imgui.TextDisabled(u8"Drag mode is active only while this menu is open.")

        imgui.Separator()
        imgui.TextDisabled(string.format("Admin HUD refreshes every %d seconds.", HudManager.autoRefreshIntervalSec))
        imgui.Text("Admins Online: " .. (HudManager.adminCount and tostring(HudManager.adminCount) or "updating..."))
        imgui.Text(string.format("Play Time: %s", UtilityManager.formatTime(StatsManager.data.session.playtime or 0)))
        imgui.Text("Admin Levels:")
        for _, line in ipairs(HudManager.getAdminListLines(6)) do
            imgui.TextDisabled(u8(line))
        end
        if imgui.Button(u8"Refresh Now", imgui.ImVec2(120, 24)) then
            sampSendChat(HudManager.adminCommand or "/admin")
            HudManager.beginAdminCapture()
        end
    end

    imgui.Separator()
    if imgui.Button(u8"Save Settings", imgui.ImVec2(120, 30)) then
        SettingsManager.save()
    end
    imgui.SameLine()
    if imgui.Button(u8"Factory Reset", imgui.ImVec2(120, 30)) then
        SettingsManager.reset()
    end

    imgui.Separator()
    imgui.TextDisabled(string.format("Grand Mobile Tools by Harvey v%s", CONFIG.VERSION))
    imgui.TextDisabled("Built for MoonLoader SAMP")
end

-- ============================================
-- RECONNECT MANAGER
-- ============================================
local ReconnectManager = {
    active = false,
    reconnectAtMs = 0,
    delaySec = 5,
    serverIp = nil,
    serverPort = nil,
    playerNick = nil
}

function ReconnectManager.getNowMs()
    if type(getTickCount) == "function" then
        local ok, value = pcall(getTickCount)
        if ok and type(value) == "number" then
            return value
        end
    end
    return math.floor(os.clock() * 1000)
end

function ReconnectManager.getLocalNick()
    if not sampGetPlayerIdByCharHandle or not sampGetPlayerNickname or not PLAYER_PED then
        return nil
    end

    local okId, success, playerId = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
    if (not okId) or (not success) or (not playerId) then
        return nil
    end

    local okNick, nick = pcall(sampGetPlayerNickname, playerId)
    if not okNick then
        return nil
    end

    nick = UtilityManager.trim(tostring(nick or ""))
    if nick == "" then
        return nil
    end
    return nick
end

function ReconnectManager.captureCurrentServer()
    if type(sampGetCurrentServerAddress) ~= "function" then
        return nil, nil
    end

    local ok, ip, port = pcall(sampGetCurrentServerAddress)
    if not ok then
        return nil, nil
    end

    if type(ip) ~= "string" then
        return nil, nil
    end

    ip = UtilityManager.trim(ip)
    port = tonumber(port)

    if ip == "" then
        return nil, nil
    end
    if not port or port <= 0 or port > 65535 then
        return nil, nil
    end

    return ip, math.floor(port)
end

function ReconnectManager.tryDisconnect()
    local strategies = {
        function()
            if type(sampDisconnectWithReason) ~= "function" then return false end
            sampDisconnectWithReason(0)
            return true
        end,
        function()
            if type(sampDisconnectWithReason) ~= "function" then return false end
            sampDisconnectWithReason(1)
            return true
        end,
        function()
            if type(sampDisconnect) ~= "function" then return false end
            sampDisconnect()
            return true
        end,
        function()
            if type(sampSetGamestate) ~= "function" then return false end
            sampSetGamestate(0)
            return true
        end
    }

    for _, strategy in ipairs(strategies) do
        local ok, success = pcall(strategy)
        if ok and success then
            return true
        end
    end
    return false
end

function ReconnectManager.tryReconnect()
    local ip = ReconnectManager.serverIp
    local port = ReconnectManager.serverPort
    local nick = ReconnectManager.playerNick

    local strategies = {
        function()
            if type(sampConnectToServer) ~= "function" then return false end
            if not ip or not port then return false end
            if nick and nick ~= "" then
                sampConnectToServer(ip, port, nick)
            else
                sampConnectToServer(ip, port)
            end
            return true
        end,
        function()
            if type(sampConnectToServer) ~= "function" then return false end
            if not ip or not port then return false end
            sampConnectToServer(ip, port)
            return true
        end,
        function()
            if type(sampProcessChatInput) ~= "function" then return false end
            sampProcessChatInput("/reconnect")
            return true
        end
    }

    for _, strategy in ipairs(strategies) do
        local ok, success = pcall(strategy)
        if ok and success then
            return true
        end
    end
    return false
end

function ReconnectManager.start(delaySec)
    if ReconnectManager.active then
        return false, "REC allaqachon ishlayapti."
    end

    local delay = tonumber(delaySec) or 5
    delay = math.max(1, math.min(600, math.floor(delay)))

    local ip, port = ReconnectManager.captureCurrentServer()
    ReconnectManager.serverIp = ip
    ReconnectManager.serverPort = port
    ReconnectManager.playerNick = ReconnectManager.getLocalNick()

    local disconnected = ReconnectManager.tryDisconnect()
    if not disconnected then
        return false, "Disconnect API topilmadi (MoonLoader build)."
    end

    ReconnectManager.delaySec = delay
    ReconnectManager.reconnectAtMs = ReconnectManager.getNowMs() + (delay * 1000)
    ReconnectManager.active = true

    return true, string.format("REC: uzildi, %d sekunddan keyin qayta ulanadi.", delay)
end

function ReconnectManager.update()
    if not ReconnectManager.active then
        return
    end

    local nowMs = ReconnectManager.getNowMs()
    if nowMs < ReconnectManager.reconnectAtMs then
        return
    end

    ReconnectManager.active = false

    local okReconnect = ReconnectManager.tryReconnect()
    if okReconnect then
        sampAddChatMessage("[Harvey] REC: qayta ulanish yuborildi.", 0x33FF66)
    else
        sampAddChatMessage("[Harvey] REC xato: qayta ulanish API topilmadi.", 0xFF6666)
    end
end

-- ============================================
-- ADMIN MODES MANAGER
-- ============================================
AdminModesManager = {
    lastTickMs = 0,
    lastGodState = false,
    lastInvisibleState = false,
    warnedGodUnsupported = false,
    warnedInvisibleUnsupported = false
}

function AdminModesManager.getNowMs()
    if type(getTickCount) == "function" then
        local ok, value = pcall(getTickCount)
        if ok and type(value) == "number" then
            return value
        end
    end
    return math.floor(os.clock() * 1000)
end

function AdminModesManager.getLocalPed()
    if not PLAYER_PED then
        return nil
    end

    if type(doesCharExist) == "function" then
        local okExists, exists = pcall(doesCharExist, PLAYER_PED)
        if okExists and not exists then
            return nil
        end
    end

    return PLAYER_PED
end

function AdminModesManager.tryGlobalCall(fnName, ...)
    local fn = _G[fnName]
    if type(fn) ~= "function" then
        return false
    end
    local ok = pcall(fn, ...)
    return ok
end

function AdminModesManager.getPedVehicle(ped)
    if not ped then
        return nil
    end

    local vehicle = nil
    if type(storeCarCharIsInNoSave) == "function" then
        local okCar, car = pcall(storeCarCharIsInNoSave, ped)
        if okCar then
            vehicle = tonumber(car)
        end
    elseif type(storeCarCharIsIn) == "function" then
        local okCar, car = pcall(storeCarCharIsIn, ped)
        if okCar then
            vehicle = tonumber(car)
        end
    end

    if not vehicle then
        return nil
    end

    if type(doesVehicleExist) == "function" then
        local okExists, exists = pcall(doesVehicleExist, vehicle)
        if okExists and not exists then
            return nil
        end
    end

    return vehicle
end

function AdminModesManager.applyGodMode(enabled)
    local ped = AdminModesManager.getLocalPed()
    if not ped then
        return false
    end

    local applied = false

    if enabled then
        if AdminModesManager.tryGlobalCall("setCharHealth", ped, 999.0) then
            applied = true
        elseif AdminModesManager.tryGlobalCall("setCharHealth", ped, 100.0) then
            applied = true
        end

        if AdminModesManager.tryGlobalCall("setCharProofs", ped, true, true, true, true, true) then
            applied = true
        end

        local vehicle = AdminModesManager.getPedVehicle(ped)
        if vehicle then
            if AdminModesManager.tryGlobalCall("setCarHealth", vehicle, 1000.0) then
                applied = true
            end
            if AdminModesManager.tryGlobalCall("setCarProofs", vehicle, true, true, true, true, true) then
                applied = true
            end
        end
    else
        AdminModesManager.tryGlobalCall("setCharProofs", ped, false, false, false, false, false)
        local vehicle = AdminModesManager.getPedVehicle(ped)
        if vehicle then
            AdminModesManager.tryGlobalCall("setCarProofs", vehicle, false, false, false, false, false)
        end
        applied = true
    end

    return applied
end

function AdminModesManager.applyInvisibleMode(enabled)
    local ped = AdminModesManager.getLocalPed()
    if not ped then
        return false
    end

    local applied = false

    if enabled then
        if AdminModesManager.tryGlobalCall("setCharVisible", ped, false) then
            applied = true
        end
        if AdminModesManager.tryGlobalCall("setCharAlpha", ped, 0) then
            applied = true
        end
    else
        if AdminModesManager.tryGlobalCall("setCharVisible", ped, true) then
            applied = true
        end
        if AdminModesManager.tryGlobalCall("setCharAlpha", ped, 255) then
            applied = true
        end
    end

    return applied
end

function AdminModesManager.update()
    local nowMs = AdminModesManager.getNowMs()
    if (nowMs - AdminModesManager.lastTickMs) < 120 then
        return
    end
    AdminModesManager.lastTickMs = nowMs

    local godEnabled = SettingsManager.get("godMode") == true
    local invisibleEnabled = SettingsManager.get("invisible") == true

    if godEnabled then
        local okGod = AdminModesManager.applyGodMode(true)
        if not okGod and not AdminModesManager.warnedGodUnsupported then
            AdminModesManager.warnedGodUnsupported = true
            sampAddChatMessage("[Harvey] Xudo rejimi API topilmadi (build mos emas).", 0xFF6666)
        end
    elseif AdminModesManager.lastGodState then
        AdminModesManager.applyGodMode(false)
    end

    if invisibleEnabled then
        local okInvisible = AdminModesManager.applyInvisibleMode(true)
        if not okInvisible and not AdminModesManager.warnedInvisibleUnsupported then
            AdminModesManager.warnedInvisibleUnsupported = true
            sampAddChatMessage("[Harvey] Ko'rinmaslik rejimi API topilmadi (build mos emas).", 0xFF6666)
        end
    elseif AdminModesManager.lastInvisibleState then
        AdminModesManager.applyInvisibleMode(false)
    end

    AdminModesManager.lastGodState = godEnabled
    AdminModesManager.lastInvisibleState = invisibleEnabled
end

function AdminModesManager.restore()
    AdminModesManager.applyInvisibleMode(false)
    AdminModesManager.applyGodMode(false)
end

-- ============================================
-- CLICK TELEPORT MANAGER
-- ============================================
TeleportClickManager = {
    enabled = false,
    middleLastState = false,
    leftLastState = false,
    lastTeleportAtMs = 0,
    lastErrorAtMs = 0,
    cooldownMs = 120,
    maxDistance = 200.0,
    dlRequest = nil,
    dlTimeoutMs = 2600,
    dlObservedVehicleId = nil,
    dlObservedAtMs = 0
}

function TeleportClickManager.getNowMs()
    if type(getTickCount) == "function" then
        local ok, value = pcall(getTickCount)
        if ok and type(value) == "number" then
            return value
        end
    end
    return math.floor(os.clock() * 1000)
end

function TeleportClickManager.readKeyDown(vk, asyncVk)
    local down = false

    if type(isKeyDown) == "function" then
        local ok, keyDown = pcall(isKeyDown, vk)
        if ok and keyDown then
            down = true
        end
    end

    if not down and user32 and user32.GetAsyncKeyState then
        local ok, state = pcall(user32.GetAsyncKeyState, asyncVk)
        if ok and state ~= nil then
            local value = tonumber(state) or 0
            down = (value < 0) or (value >= 0x8000)
        end
    end

    return down
end

function TeleportClickManager.isMiddleClicked()
    local down = TeleportClickManager.readKeyDown(vkeys.VK_MBUTTON or 0x04, 0x04)
    local clicked = down and not TeleportClickManager.middleLastState
    TeleportClickManager.middleLastState = down
    return clicked
end

function TeleportClickManager.isLeftClicked()
    local down = TeleportClickManager.readKeyDown(vkeys.VK_LBUTTON or 0x01, 0x01)
    local clicked = down and not TeleportClickManager.leftLastState
    TeleportClickManager.leftLastState = down
    return clicked
end

function TeleportClickManager.extractCoords(...)
    local a, b, c, d = ...
    if type(a) == "boolean" then
        if not a then return nil end
        a, b, c = b, c, d
    end

    if type(a) == "table" then
        local x = tonumber(a.x or a[1])
        local y = tonumber(a.y or a[2])
        local z = tonumber(a.z or a[3])
        if x and y and z then
            return x, y, z
        end
    end

    if type(a) == "userdata" then
        local okX, x = pcall(function() return tonumber(a.x) end)
        local okY, y = pcall(function() return tonumber(a.y) end)
        local okZ, z = pcall(function() return tonumber(a.z) end)
        if okX and okY and okZ and x and y and z then
            return x, y, z
        end

        local okI, i1, i2, i3 = pcall(function() return a[1], a[2], a[3] end)
        if okI then
            local x2 = tonumber(i1)
            local y2 = tonumber(i2)
            local z2 = tonumber(i3)
            if x2 and y2 and z2 then
                return x2, y2, z2
            end
        end
    end

    return tonumber(a), tonumber(b), tonumber(c)
end

function TeleportClickManager.tryGroundZAt(x, y, z)
    if type(getGroundZFor3dCoord) ~= "function" then
        return nil
    end

    local attempts = {
        function() return getGroundZFor3dCoord(x, y, z) end,
        function() return getGroundZFor3dCoord(x, y, z, false) end,
        function() return getGroundZFor3dCoord(x, y, z, true) end
    }

    for _, fn in ipairs(attempts) do
        local ok, a, b, c = pcall(fn)
        if ok then
            local gx, gy, gz = TeleportClickManager.extractCoords(a, b, c)
            if gx and gy and gz then
                return gz
            end

            if type(a) == "boolean" then
                if a then
                    local zValue = tonumber(b)
                    if zValue then
                        return zValue
                    end
                end
            else
                local zValue = tonumber(a)
                if zValue then
                    return zValue
                end
            end
        end
    end

    return nil
end

function TeleportClickManager.getGroundZ(x, y, seedZ)
    local base = tonumber(seedZ) or 100.0
    local heights = {
        base + 320.0,
        base + 160.0,
        base + 64.0,
        1200.0,
        800.0,
        400.0
    }

    local best = nil
    for _, h in ipairs(heights) do
        local gz = TeleportClickManager.tryGroundZAt(x, y, h)
        if gz and gz > -300.0 and gz < 5000.0 then
            if not best or gz > best then
                best = gz
            end
        end
    end

    return best
end

function TeleportClickManager.findGroundPointOnRay(fromX, fromY, fromZ, dirX, dirY, dirZ, maxDist)
    if dirZ >= -0.08 then
        return nil
    end

    local step = 4.0
    local t = step
    while t <= maxDist do
        local px = fromX + dirX * t
        local py = fromY + dirY * t
        local pz = fromZ + dirZ * t
        local gz = TeleportClickManager.getGroundZ(px, py, fromZ)
        if gz and pz <= (gz + 0.8) then
            return px, py, gz
        end
        t = t + step
    end

    return nil
end

function TeleportClickManager.getCursorScreenPos()
    local x, y = nil, nil

    if type(getCursorPos) == "function" then
        local ok, a, b, c = pcall(getCursorPos)
        if ok then
            if type(a) == "boolean" then
                if a then
                    x = tonumber(b)
                    y = tonumber(c)
                end
            else
                x = tonumber(a)
                y = tonumber(b)
            end
        end
    end

    local sx, sy = getScreenResolution()
    sx = sx or 1920
    sy = sy or 1080

    if not x or not y then
        x = sx * 0.5
        y = sy * 0.5
    end

    if x <= 1.5 and y <= 1.5 then
        x = x * sx
        y = y * sy
    end

    return x, y, sx, sy
end

function TeleportClickManager.getMaxDistance()
    local maxDist = tonumber(TeleportClickManager.maxDistance) or 200.0
    if maxDist <= 0 then maxDist = 200.0 end
    if maxDist > 200.0 then maxDist = 200.0 end
    return maxDist
end

function TeleportClickManager.getRayOrigin()
    if type(getActiveCameraCoordinates) == "function" then
        local camX, camY, camZ = TeleportClickManager.extractCoords(getActiveCameraCoordinates())
        if camX and camY and camZ then
            return camX, camY, camZ
        end
    end

    local ped = AdminModesManager.getLocalPed()
    if ped and type(getCharCoordinates) == "function" then
        local px, py, pz = TeleportClickManager.extractCoords(getCharCoordinates(ped))
        if px and py and pz then
            return px, py, pz + 0.8
        end
    end

    return nil
end

function TeleportClickManager.pullBackFromHit(fromX, fromY, fromZ, hitX, hitY, hitZ)
    local dx = hitX - fromX
    local dy = hitY - fromY
    local dz = hitZ - fromZ
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.001 then
        return hitX, hitY, hitZ
    end

    local back = 0.25
    if len <= back then
        back = len * 0.25
    end

    return hitX - (dx / len) * back,
           hitY - (dy / len) * back,
           hitZ - (dz / len) * back
end

function TeleportClickManager.lineOfSight(fromX, fromY, fromZ, toX, toY, toZ)
    if type(processLineOfSight) ~= "function" then
        return nil
    end

    local maxRayDist = math.sqrt((toX - fromX) ^ 2 + (toY - fromY) ^ 2 + (toZ - fromZ) ^ 2) + 3.0
    local function isLikelyEndPoint(x, y, z)
        local ex = x - toX
        local ey = y - toY
        local ez = z - toZ
        return (ex * ex + ey * ey + ez * ez) <= 0.75
    end
    local function isValidPoint(x, y, z)
        if not x or not y or not z then
            return false
        end
        if math.abs(x) >= 20000 or math.abs(y) >= 20000 or math.abs(z) >= 20000 then
            return false
        end
        local dx = x - fromX
        local dy = y - fromY
        local dz = z - fromZ
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        return dist <= maxRayDist
    end

    local attempts = {
        function()
            return processLineOfSight(fromX, fromY, fromZ, toX, toY, toZ, true, true, false, true, true, false, false, false)
        end,
        function()
            return processLineOfSight(fromX, fromY, fromZ, toX, toY, toZ, true, false, false, true, true, false, false, false)
        end,
        function()
            return processLineOfSight(fromX, fromY, fromZ, toX, toY, toZ, true, true, true, true, true, false, false, false)
        end,
        function()
            return processLineOfSight(fromX, fromY, fromZ, toX, toY, toZ)
        end
    }

    for _, fn in ipairs(attempts) do
        local results = { pcall(fn) }
        if results[1] then
            if type(results[2]) == "boolean" then
                if results[2] then
                    local rx, ry, rz = TeleportClickManager.extractCoords(results[3], results[4], results[5])
                    if isValidPoint(rx, ry, rz) and not isLikelyEndPoint(rx, ry, rz) then
                        return rx, ry, rz
                    end

                    for i = 3, #results - 2 do
                        local px, py, pz = TeleportClickManager.extractCoords(results[i], results[i + 1], results[i + 2])
                        if isValidPoint(px, py, pz) and not isLikelyEndPoint(px, py, pz) then
                            return px, py, pz
                        end
                    end
                end
            else
                for i = 2, #results - 2 do
                    local rx, ry, rz = TeleportClickManager.extractCoords(results[i], results[i + 1], results[i + 2])
                    if isValidPoint(rx, ry, rz) and not isLikelyEndPoint(rx, ry, rz) then
                        return rx, ry, rz
                    end
                end

                for i = 2, #results do
                    local value = results[i]
                    if type(value) == "table" or type(value) == "userdata" then
                        local rx, ry, rz = TeleportClickManager.extractCoords(value)
                        if isValidPoint(rx, ry, rz) and not isLikelyEndPoint(rx, ry, rz) then
                            return rx, ry, rz
                        end
                    end
                end
            end
        end
    end

    return nil
end

function TeleportClickManager.getWorldTargetByCursor()
    if type(convertScreenCoordsToWorld3D) ~= "function" then
        return nil
    end

    local cx, cy, sx, sy = TeleportClickManager.getCursorScreenPos()
    local coordAttempts = {
        { cx, cy },
        { cx / math.max(1, sx), cy / math.max(1, sy) },
        { cx, sy - cy },
        { cx / math.max(1, sx), 1.0 - (cy / math.max(1, sy)) }
    }
    local maxDist = TeleportClickManager.getMaxDistance()
    local fromX, fromY, fromZ = TeleportClickManager.getRayOrigin()
    if not fromX or not fromY or not fromZ then
        return nil
    end

    for _, pair in ipairs(coordAttempts) do
        local px, py = pair[1], pair[2]
        local okNear, nearA, nearB, nearC = pcall(convertScreenCoordsToWorld3D, px, py, 1.0)
        local okFar, farA, farB, farC = pcall(convertScreenCoordsToWorld3D, px, py, maxDist)
        if okNear and okFar then
            local nearX, nearY, nearZ = TeleportClickManager.extractCoords(nearA, nearB, nearC)
            local farX, farY, farZ = TeleportClickManager.extractCoords(farA, farB, farC)
            if nearX and nearY and nearZ and farX and farY and farZ then
                local dirX = farX - nearX
                local dirY = farY - nearY
                local dirZ = farZ - nearZ
                local dirLen = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)
                if dirLen > 0.001 then
                    dirX = dirX / dirLen
                    dirY = dirY / dirLen
                    dirZ = dirZ / dirLen

                    local endX = fromX + dirX * maxDist
                    local endY = fromY + dirY * maxDist
                    local endZ = fromZ + dirZ * maxDist

                    local hitX, hitY, hitZ = TeleportClickManager.lineOfSight(fromX, fromY, fromZ, endX, endY, endZ)
                    if hitX and hitY and hitZ then
                        return TeleportClickManager.pullBackFromHit(fromX, fromY, fromZ, hitX, hitY, hitZ)
                    end

                    -- If aiming down and no object hit, allow ground point only.
                    if dirZ < -0.05 then
                        local gx, gy, gz = TeleportClickManager.findGroundPointOnRay(fromX, fromY, fromZ, dirX, dirY, dirZ, maxDist)
                        if gx and gy and gz then
                            return gx, gy, gz
                        end
                    end
                end
            end
        end
    end

    return nil
end

function TeleportClickManager.getWorldTargetByCamera()
    if type(getActiveCameraCoordinates) ~= "function" or type(getActiveCameraPointAt) ~= "function" then
        return nil
    end

    local camX, camY, camZ = TeleportClickManager.extractCoords(getActiveCameraCoordinates())
    local atX, atY, atZ = TeleportClickManager.extractCoords(getActiveCameraPointAt())
    if not camX or not atX then
        return nil
    end

    local dx = atX - camX
    local dy = atY - camY
    local dz = atZ - camZ
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.001 then
        return nil
    end

    dx = dx / len
    dy = dy / len
    dz = dz / len

    local maxDist = TeleportClickManager.getMaxDistance()
    local originX, originY, originZ = TeleportClickManager.getRayOrigin()
    if not originX or not originY or not originZ then
        originX, originY, originZ = camX, camY, camZ
    end

    local farX = originX + dx * maxDist
    local farY = originY + dy * maxDist
    local farZ = originZ + dz * maxDist

    local hitX, hitY, hitZ = TeleportClickManager.lineOfSight(originX, originY, originZ, farX, farY, farZ)
    if hitX and hitY and hitZ then
        return TeleportClickManager.pullBackFromHit(originX, originY, originZ, hitX, hitY, hitZ)
    end

    if dz < -0.05 then
        local gx, gy, gz = TeleportClickManager.findGroundPointOnRay(originX, originY, originZ, dx, dy, dz, maxDist)
        if gx and gy and gz then
            return gx, gy, gz
        end
    end

    return nil
end

function TeleportClickManager.getTeleportTarget()
    -- Use cursor ray only for precise click destination.
    return TeleportClickManager.getWorldTargetByCursor()
end

function TeleportClickManager.teleportLocalWithVehicle(x, y, z)
    local ped = AdminModesManager.getLocalPed()
    if not ped then
        return false
    end

    local targetX = tonumber(x)
    local targetY = tonumber(y)
    local targetZ = tonumber(z)
    if not targetX or not targetY or not targetZ then
        return false
    end

    local vehicle = AdminModesManager.getPedVehicle(ped)
    local curX, curY, curZ = nil, nil, nil
    if type(getCharCoordinates) == "function" then
        local okPos, a, b, c = pcall(getCharCoordinates, ped)
        if okPos then
            curX, curY, curZ = TeleportClickManager.extractCoords(a, b, c)
        end
    end

    if curX and curY and curZ then
        local dx = targetX - curX
        local dy = targetY - curY
        local dz = targetZ - curZ
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if dist < 1.2 then
            return true
        end
    end

    if vehicle and vehicle > 0 and type(setCarCoordinates) == "function" then
        local okCar = pcall(setCarCoordinates, vehicle, targetX, targetY, targetZ + 0.4)
        return okCar == true
    end

    if type(setCharCoordinates) == "function" then
        local okPed = pcall(setCharCoordinates, ped, targetX, targetY, targetZ + 0.9)
        return okPed == true
    end

    return false
end

function TeleportClickManager.toggle()
    TeleportClickManager.enabled = not TeleportClickManager.enabled
    local color = TeleportClickManager.enabled and 0x33FF66 or 0xFF9933
    local state = TeleportClickManager.enabled and "YOQIQ" or "O'CHIQ"
    sampAddChatMessage("[Harvey] Click TP: " .. state .. " (MMB toggle, LMB teleport)", color)

    if TeleportClickManager.enabled then
        imgui.Process = true
        imgui.ShowCursor = true
    end
end

function TeleportClickManager.renderCursorOverlay()
    if not TeleportClickManager.enabled then
        return
    end

    local x, y = TeleportClickManager.getCursorScreenPos()
    if not x or not y then
        return
    end

    local flags = imgui.WindowFlags.NoTitleBar +
                  imgui.WindowFlags.NoResize +
                  imgui.WindowFlags.NoMove +
                  imgui.WindowFlags.NoScrollbar +
                  imgui.WindowFlags.NoCollapse +
                  imgui.WindowFlags.NoSavedSettings +
                  imgui.WindowFlags.NoInputs +
                  (imgui.WindowFlags.NoBackground or 0)

    imgui.SetNextWindowPos(imgui.ImVec2(x - 10, y - 10), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(24, 24), imgui.Cond.Always)
    if imgui.Begin("##ClickTpCursorOverlay", nil, flags) then
        if imgui.SetWindowFontScale then
            imgui.SetWindowFontScale(1.35)
        end
        imgui.TextColored(COLORS.WARNING or imgui.ImVec4(0.95, 0.77, 0.06, 1.0), "O")
        if imgui.SetWindowFontScale then
            imgui.SetWindowFontScale(1.0)
        end
    end
    imgui.End()
end

function TeleportClickManager.parseVehicleIdFromDlText(text)
    local source = tostring(text or "")
    if source == "" then
        return nil
    end

    local raw = source:gsub("%b{}", " "):gsub("%s+", " ")
    local variants = UtilityManager.getMatchVariants(raw)
    if #variants == 0 then
        table.insert(variants, raw)
    end

    local patterns = {
        "[iI][dD]%s*[:#]%s*(%d+)",
        "[iI][dD]%s+(%d+)",
        "vehicle%s*[iI][dD]%s*[:#]%s*(%d+)"
    }

    for _, value in ipairs(variants) do
        for _, pattern in ipairs(patterns) do
            local id = tonumber(value:match(pattern))
            if id and id > 0 and id < 10000 then
                return id
            end
        end
    end

    return nil
end

function TeleportClickManager.captureVehicleIdFromServerMessage(text)
    local vehicleId = TeleportClickManager.parseVehicleIdFromDlText(text)
    if vehicleId and vehicleId > 0 then
        TeleportClickManager.dlObservedVehicleId = vehicleId
        TeleportClickManager.dlObservedAtMs = TeleportClickManager.getNowMs()
        return vehicleId
    end
    return nil
end

function TeleportClickManager.resolveSpectateTargetVehicleId(targetId)
    local id = tonumber(targetId)
    if not id or id <= 0 then
        return nil
    end

    local ped = nil
    if ReportCatchManager and type(ReportCatchManager.getPlayerPedHandle) == "function" then
        ped = ReportCatchManager.getPlayerPedHandle(id)
    end
    if not ped then
        return nil
    end

    if type(isCharInAnyCar) == "function" then
        local okInCar, inCar = pcall(isCharInAnyCar, ped)
        if not okInCar or not inCar then
            return nil
        end
    end

    local vehicle = nil
    if type(storeCarCharIsInNoSave) == "function" then
        local okCar, car = pcall(storeCarCharIsInNoSave, ped)
        if okCar then
            vehicle = tonumber(car)
        end
    elseif type(storeCarCharIsIn) == "function" then
        local okCar, car = pcall(storeCarCharIsIn, ped)
        if okCar then
            vehicle = tonumber(car)
        end
    end
    if not vehicle or vehicle <= 0 then
        return nil
    end

    if type(doesVehicleExist) == "function" then
        local okExists, exists = pcall(doesVehicleExist, vehicle)
        if okExists and not exists then
            return nil
        end
    end

    if type(sampGetVehicleIdByCarHandle) ~= "function" then
        return nil
    end

    local okVehId, a, b = pcall(sampGetVehicleIdByCarHandle, vehicle)
    if not okVehId then
        return nil
    end

    local sampVehId = nil
    if type(a) == "boolean" then
        if a then
            sampVehId = tonumber(b)
        end
    else
        sampVehId = tonumber(a)
    end

    if sampVehId and sampVehId > 0 then
        return sampVehId
    end

    return nil
end

function TeleportClickManager.startDlRequestForSpectate(targetId, x, y, z)
    if type(sampSendChat) ~= "function" then
        return false
    end

    local id = tonumber(targetId)
    local tx = tonumber(x)
    local ty = tonumber(y)
    local tz = tonumber(z)
    if not id or id <= 0 or not tx or not ty or not tz then
        return false
    end

    TeleportClickManager.dlRequest = {
        targetId = id,
        x = tx,
        y = ty,
        z = tz,
        startMs = TeleportClickManager.getNowMs()
    }

    local directVehicleId = TeleportClickManager.resolveSpectateTargetVehicleId(id)
    if directVehicleId then
        TeleportClickManager.finishDlSpectateTeleport(directVehicleId)
        return true
    end

    sampSendChat("/dl")
    sampAddChatMessage(string.format("[Harvey] Click TP (SP): /dl yuborildi, target #%d mashinasi kutilmoqda...", id), 0x33FF66)
    return true
end

function TeleportClickManager.finishDlSpectateTeleport(vehicleId)
    local req = TeleportClickManager.dlRequest
    TeleportClickManager.dlRequest = nil
    if not req then
        return false
    end

    local carId = tonumber(vehicleId)
    if not carId or carId <= 0 then
        sampAddChatMessage("[Harvey] Click TP (SP): /dl dan mashina ID topilmadi.", 0xFF6666)
        return false
    end

    if type(sampSendChat) ~= "function" or not (lua_thread and type(lua_thread.create) == "function") then
        return false
    end

    local function isLocalNearTarget(x, y, z, radius)
        local ped = AdminModesManager.getLocalPed()
        if not ped or type(getCharCoordinates) ~= "function" then
            return false
        end

        local okPos, a, b, c = pcall(getCharCoordinates, ped)
        if not okPos then
            return false
        end

        local px, py, pz = TeleportClickManager.extractCoords(a, b, c)
        if not px or not py or not pz then
            return false
        end

        local dx = (tonumber(x) or 0.0) - px
        local dy = (tonumber(y) or 0.0) - py
        local dz = (tonumber(z) or 0.0) - pz
        local rr = tonumber(radius) or 5.0
        return (dx * dx + dy * dy + dz * dz) <= (rr * rr)
    end

    lua_thread.create(function()
        sampSendChat("/spoff")
        if SpectateQuickPanel and SpectateQuickPanel.stop then
            SpectateQuickPanel.stop()
        end

        wait(180)
        local reached = false
        for _ = 1, 8 do
            TeleportClickManager.teleportLocalWithVehicle(req.x, req.y, req.z)
            wait(170)
            if isLocalNearTarget(req.x, req.y, req.z, 6.0) then
                reached = true
                break
            end
        end

        if not reached then
            sampAddChatMessage("[Harvey] Click TP (SP): avval belgilangan joyga TP bo'lmadi, /getcar bekor qilindi.", 0xFF6666)
            return
        end

        wait(120)
        sampSendChat(string.format("/getcar %d", carId))
        wait(260)
        sampSendChat(string.format("/sp %d", req.targetId))
    end)

    sampAddChatMessage(string.format("[Harvey] Click TP (SP): /getcar %d va /sp %d yuborildi.", carId, req.targetId), 0x33FF66)
    return true
end

function TeleportClickManager.processDlServerMessage(text)
    if not TeleportClickManager.dlRequest then
        return false
    end

    local vehicleId = TeleportClickManager.parseVehicleIdFromDlText(text)
    if vehicleId then
        TeleportClickManager.finishDlSpectateTeleport(vehicleId)
        return true
    end

    return false
end

function TeleportClickManager.updateDlRequest()
    local req = TeleportClickManager.dlRequest
    if not req then
        return
    end

    local directVehicleId = TeleportClickManager.resolveSpectateTargetVehicleId(req.targetId)
    if directVehicleId then
        TeleportClickManager.finishDlSpectateTeleport(directVehicleId)
        return
    end

    local nowMs = TeleportClickManager.getNowMs()
    if (nowMs - (tonumber(req.startMs) or 0)) > (tonumber(TeleportClickManager.dlTimeoutMs) or 2600) then
        TeleportClickManager.dlRequest = nil
        sampAddChatMessage("[Harvey] Click TP (SP): /dl javobida mashina ID topilmadi.", 0xFF6666)
    end
end

function TeleportClickManager.performSpectateTargetTeleport(x, y, z)
    if not SpectateQuickPanel or not SpectateQuickPanel.active then
        return false
    end

    local targetId = tonumber(SpectateQuickPanel.targetId)
    if not targetId or targetId <= 0 then
        return false
    end

    return TeleportClickManager.startDlRequestForSpectate(targetId, x, y, z)
end

function TeleportClickManager.performTeleport()
    local nowMs = TeleportClickManager.getNowMs()
    if (nowMs - TeleportClickManager.lastTeleportAtMs) < TeleportClickManager.cooldownMs then
        return
    end
    TeleportClickManager.lastTeleportAtMs = nowMs

    local x, y, z = TeleportClickManager.getTeleportTarget()
    if not x or not y or not z then
        if (nowMs - TeleportClickManager.lastErrorAtMs) > 1200 then
            TeleportClickManager.lastErrorAtMs = nowMs
            sampAddChatMessage("[Harvey] Click TP xato: target coord topilmadi.", 0xFF6666)
        end
        return
    end

    local ok = TeleportClickManager.teleportLocalWithVehicle(x, y, z)

    if not ok and (nowMs - TeleportClickManager.lastErrorAtMs) > 1200 then
        TeleportClickManager.lastErrorAtMs = nowMs
        sampAddChatMessage("[Harvey] Click TP xato: teleport API ishlamadi.", 0xFF6666)
    end
end

function TeleportClickManager.update(canToggle, canTeleport)
    if not canToggle then
        TeleportClickManager.middleLastState = false
        TeleportClickManager.leftLastState = false
        return
    end

    if TeleportClickManager.isMiddleClicked() then
        TeleportClickManager.toggle()
    end

    if TeleportClickManager.enabled and canTeleport and TeleportClickManager.isLeftClicked() then
        TeleportClickManager.performTeleport()
    end
end

-- ============================================
-- HUD MANAGER IMPLEMENTATION
-- ============================================
function HudManager.initialize()
    HudManager.clock.enabled = SettingsManager.get("hudClockEnabled") == true
    HudManager.clock.pos.x = tonumber(SettingsManager.get("hudClockPosX")) or 0
    HudManager.clock.pos.y = tonumber(SettingsManager.get("hudClockPosY")) or 0
    HudManager.dateBar.enabled = SettingsManager.get("hudDateEnabled") == true
    HudManager.dateBar.pos.x = tonumber(SettingsManager.get("hudDatePosX")) or 0
    HudManager.dateBar.pos.y = tonumber(SettingsManager.get("hudDatePosY")) or 0
    HudManager.adminBar.enabled = SettingsManager.get("hudAdminEnabled") == true
    HudManager.adminBar.pos.x = tonumber(SettingsManager.get("hudAdminPosX")) or 0
    HudManager.adminBar.pos.y = tonumber(SettingsManager.get("hudAdminPosY")) or 0
    HudManager.scale = UtilityManager.clamp(tonumber(SettingsManager.get("hudScale")) or 1.0, 0.75, 1.75)
    HudManager.opacity = UtilityManager.clamp(tonumber(SettingsManager.get("hudOpacity")) or 1.0, 0.25, 1.0)
    HudManager.adminCommand = tostring(SettingsManager.get("hudAdminCommand") or "/admin")
    if HudManager.adminCommand == "" then HudManager.adminCommand = "/admin" end
    HudManager.adminList = {}
    HudManager.lastAutoRefreshAt = 0
    LogManager.system("HUD manager initialized")
end

function HudManager.isAnyEnabled()
    return HudManager.clock.enabled or HudManager.dateBar.enabled or HudManager.adminBar.enabled
end

function HudManager.storeToSettings()
    if not SettingsManager or not SettingsManager.data then return end
    SettingsManager.data.hudClockEnabled = HudManager.clock.enabled
    SettingsManager.data.hudClockPosX = tonumber(HudManager.clock.pos.x) or 0
    SettingsManager.data.hudClockPosY = tonumber(HudManager.clock.pos.y) or 0
    SettingsManager.data.hudDateEnabled = HudManager.dateBar.enabled
    SettingsManager.data.hudDatePosX = tonumber(HudManager.dateBar.pos.x) or 0
    SettingsManager.data.hudDatePosY = tonumber(HudManager.dateBar.pos.y) or 0
    SettingsManager.data.hudAdminEnabled = HudManager.adminBar.enabled
    SettingsManager.data.hudAdminPosX = tonumber(HudManager.adminBar.pos.x) or 0
    SettingsManager.data.hudAdminPosY = tonumber(HudManager.adminBar.pos.y) or 0
    SettingsManager.data.hudScale = UtilityManager.clamp(tonumber(HudManager.scale) or 1.0, 0.75, 1.75)
    SettingsManager.data.hudOpacity = UtilityManager.clamp(tonumber(HudManager.opacity) or 1.0, 0.25, 1.0)
    SettingsManager.data.hudAdminCommand = tostring(HudManager.adminCommand or "/admin")
end

function HudManager.saveToDisk()
    HudManager.storeToSettings()
    if SettingsManager and SettingsManager.save then
        SettingsManager.save()
    end
end

-- IMPORTANT: imgui.Process ni doim yoqib qo'yish sichqonchani (kamera aylanishini)
-- buzadi, shuning uchun oddiy holatda HUD imgui'siz, native renderFontDrawText
-- orqali chiziladi. imgui faqat "joylashuvni tahrirlash" rejimida ishlatiladi,
-- va u rejim faqat M panel ochiq bo'lganda yoqilishi mumkin (Process allaqachon true).
function HudManager.setEditMode(state)
    HudManager.editMode = state == true
    if HudManager.editMode then
        HudManager.clock.initialized = false
        HudManager.dateBar.initialized = false
        HudManager.adminBar.initialized = false
    else
        HudManager.saveToDisk()
    end
end

function HudManager.resetPositions()
    HudManager.clock.pos = { x = 0, y = 0 }
    HudManager.dateBar.pos = { x = 0, y = 0 }
    HudManager.adminBar.pos = { x = 0, y = 0 }
    HudManager.clock.initialized = false
    HudManager.dateBar.initialized = false
    HudManager.adminBar.initialized = false
    HudManager.saveToDisk()
end

function HudManager.setScale(value)
    HudManager.scale = UtilityManager.clamp(tonumber(value) or 1.0, 0.75, 1.75)
    HudManager.fontReady = nil
    HudManager.font = nil
    HudManager.storeToSettings()
end

function HudManager.setOpacity(value)
    HudManager.opacity = UtilityManager.clamp(tonumber(value) or 1.0, 0.25, 1.0)
    HudManager.storeToSettings()
end

function HudManager.beginAdminCapture()
    HudManager.capture.active = true
    HudManager.capture.startedAt = os.clock()
    HudManager.capture.lineCount = 0
    HudManager.capture.directTotal = nil
    HudManager.capture.entries = {}
end

-- "PlayerName [Level 3]" kabi turli formatlarni sinab ko'radi va
-- ism + darajani ajratishga harakat qiladi. Aniq format boshqacha bo'lsa,
-- shu funksiyani GRAND MOBILE'ning haqiqiy /admins matniga moslab tahrirlash kifoya.
function HudManager.parseAdminLine(line)
    local raw = UtilityManager.trim(tostring(line or ""))
    if raw == "" then
        return nil, nil
    end

    local cleaned = raw:gsub("{%x+}", "")
    cleaned = cleaned:gsub("^%s*%d+[%.)%]%-%s]+", "")
    cleaned = UtilityManager.trim(cleaned)

    local name, level
    local patterns = {
        "^(.-)%s*%[%s*[Aa]dmin%s*[Ll]?[Vv]?[Ll]?%s*[:%-]?%s*([1-5])%s*%]",
        "^(.-)%s*%[%s*[Ll][Vv][Ll]?%s*[:%-]?%s*([1-5])%s*%]",
        "^(.-)%s*%(%s*[Aa]dmin%s*[Ll]?[Vv]?[Ll]?%s*[:%-]?%s*([1-5])%s*%)",
        "^(.-)%s*%(%s*[Ll][Vv][Ll]?%s*[:%-]?%s*([1-5])%s*%)",
        "^(.-)%s*[%-|]%s*[Aa]dmin%s*[Ll]?[Vv]?[Ll]?%s*[:%-]?%s*([1-5])%s*$",
        "^(.-)%s*[%-|]%s*[Ll][Vv][Ll]?%s*[:%-]?%s*([1-5])%s*$",
        "^(.-)%s+[Aa]dmin%s*[Ll]?[Vv]?[Ll]?%s*[:%-]?%s*([1-5])%s*$",
        "^(.-)%s+[Ll][Vv][Ll]?%s*[:%-]?%s*([1-5])%s*$",
        "^(.-)%s+[Dd]araja%s*[:%-]?%s*([1-5])%s*$",
        "^(.-)%s+[Uu]roven%s*[:%-]?%s*([1-5])%s*$"
    }

    for _, pattern in ipairs(patterns) do
        name, level = cleaned:match(pattern)
        if name and level then
            break
        end
    end

    if not name then
        name = cleaned
    end

    name = UtilityManager.trim(tostring(name or ""))
    name = name:gsub("^%s*%d+[%.)%]%-%s]+", "")
    name = UtilityManager.trim(name)
    if name == "" then
        name = cleaned
    end

    level = tonumber(level)
    if not level or level < 1 or level > 5 then
        level = nil
    end

    return name, level
end

function HudManager.processServerMessage(text)
    if not HudManager.capture.active then
        return
    end

    local raw = tostring(text or "")

    for _, pattern in ipairs(HudManager.directTotalPatterns) do
        local num = raw:match(pattern)
        if num then
            HudManager.capture.directTotal = tonumber(num)
            break
        end
    end

    local ignored = false
    for _, pattern in ipairs(HudManager.ignoreLinePatterns) do
        if raw:match(pattern) then
            ignored = true
            break
        end
    end

    local trimmed = UtilityManager.trim(raw)
    if not ignored and trimmed ~= "" then
        HudManager.capture.lineCount = HudManager.capture.lineCount + 1

        local name, level = HudManager.parseAdminLine(trimmed)
        table.insert(HudManager.capture.entries, {
            name = name or trimmed,
            level = level
        })
    end
end

function HudManager.processAdminDialog(title, text)
    if not HudManager.capture.active then
        return false
    end

    local header = tostring(title or ""):lower()
    local body = tostring(text or "")
    local foldedBody = body:lower()
    if not (header:find("admin", 1, true) or header:find("administrator", 1, true) or
            foldedBody:find("admin", 1, true) or foldedBody:find("administrator", 1, true)) then
        return false
    end

    for line in body:gmatch("[^\r\n]+") do
        HudManager.processServerMessage(line)
    end

    HudManager.capture.startedAt = os.clock() - HudManager.captureWindowSeconds
    return true
end

function HudManager.update()
    -- Yoqilgan bo'lsa, /admins buyrug'ini o'zi vaqti-vaqti bilan yuboradi -
    -- tugma bosish shart emas.
    if HudManager.adminBar.enabled and not HudManager.capture.active then
        if (os.time() - (HudManager.lastAutoRefreshAt or 0)) >= HudManager.autoRefreshIntervalSec then
            HudManager.lastAutoRefreshAt = os.time()
            if type(sampSendChat) == "function" and isSampAvailable and isSampAvailable() then
                sampSendChat(HudManager.adminCommand or "/admin")
                HudManager.beginAdminCapture()
            end
        end
    end

    if not HudManager.capture.active then
        return
    end

    if (os.clock() - HudManager.capture.startedAt) >= HudManager.captureWindowSeconds then
        local finalCount = HudManager.capture.directTotal
        if not finalCount and HudManager.capture.lineCount > 0 then
            finalCount = HudManager.capture.lineCount
        end

        if finalCount then
            HudManager.adminCount = finalCount
            HudManager.adminList = HudManager.capture.entries or {}
            HudManager.adminCountUpdatedAt = os.time()
        end

        HudManager.capture.active = false
    end
end

function HudManager.getAdminCountText()
    if not HudManager.adminCount then
        return u8"Adminlar: kutilmoqda..."
    end

    local ageSec = os.time() - HudManager.adminCountUpdatedAt
    if ageSec > 600 then
        return string.format(u8"Adminlar: %d (eski)", HudManager.adminCount)
    end

    return string.format(u8"Adminlar: %d", HudManager.adminCount)
end

-- Har bir admin uchun "Ism - LVL X" qatorlarini qaytaradi (ko'p bo'lsa cheklaydi).
function HudManager.getAdminListLines(maxLines)
    local lines = {}
    local list = HudManager.adminList or {}
    local limit = math.min(#list, maxLines or 6)

    for i = 1, limit do
        local entry = list[i]
        if entry.level then
            table.insert(lines, string.format("%s - LVL %d", tostring(entry.name), entry.level))
        else
            table.insert(lines, tostring(entry.name))
        end
    end

    if #list > limit then
        table.insert(lines, string.format(u8"... yana %d ta", #list - limit))
    end

    return lines
end

-- ============================================
-- NATIVE RENDERING (imgui.Process shart emas, sichqonchaga tegmaydi)
-- ============================================
function HudManager.ensureFont()
    local wantedScale = UtilityManager.clamp(tonumber(HudManager.scale) or 1.0, 0.75, 1.75)
    if HudManager.fontReady ~= nil and HudManager.fontScale == wantedScale then
        return HudManager.fontReady
    end

    local fontSize = math.max(8, math.floor(9 * wantedScale + 0.5))
    local ok, font = pcall(renderCreateFont, "Segoe UI", fontSize, 0)
    if ok and font then
        HudManager.font = font
        HudManager.fontReady = true
        HudManager.fontScale = wantedScale
    else
        HudManager.fontReady = false
        LogManager.error("HUD: renderCreateFont ishlamadi, native HUD o'chirilgan")
    end

    return HudManager.fontReady
end

function HudManager.getNativeLineHeight()
    local lineHeight = math.max(15, math.floor(16 * (tonumber(HudManager.scale) or 1.0)))
    local okHeight, height = pcall(renderGetFontDrawHeight, HudManager.font)
    if okHeight and height and height > 0 then
        lineHeight = height + math.max(2, math.floor(3 * (tonumber(HudManager.scale) or 1.0)))
    end
    return lineHeight
end

function HudManager.getNativeTextWidth(text)
    local okWidth, width = pcall(renderGetFontDrawTextLength, HudManager.font, tostring(text or ""))
    if okWidth and width then
        return tonumber(width) or 0
    end
    return #(tostring(text or "")) * math.max(6, math.floor(7 * (tonumber(HudManager.scale) or 1.0)))
end

function HudManager.makeColor(alpha, r, g, b)
    local a = UtilityManager.clamp(math.floor((tonumber(alpha) or 255) + 0.5), 0, 255)
    return a * 0x1000000 + (r or 255) * 0x10000 + (g or 255) * 0x100 + (b or 255)
end

function HudManager.drawNativePanel(x, y, lines, accentColor)
    if not HudManager.ensureFont() then return end

    local opacity = UtilityManager.clamp(tonumber(HudManager.opacity) or 1.0, 0.25, 1.0)
    local lineHeight = HudManager.getNativeLineHeight()
    local textColor = HudManager.makeColor(255 * opacity, 255, 255, 255)

    for i, line in ipairs(lines) do
        pcall(renderFontDrawText, HudManager.font, line, x, y + (i - 1) * lineHeight, textColor)
    end
end

function HudManager.renderClockNative()
    if not HudManager.clock.enabled then return end

    local posX = tonumber(HudManager.clock.pos.x) or 0
    local posY = tonumber(HudManager.clock.pos.y) or 0
    if posX <= 0 and posY <= 0 then
        local sx, sy = 0, 0
        if getScreenResolution then
            local okRes, w, h = pcall(getScreenResolution)
            if okRes then sx, sy = w or 0, h or 0 end
        end
        posX = math.max(10, (sx > 0 and sx or 1280) - 95)
        posY = 10
    end

    local uzTimestamp = UtilityManager.getUzTimestamp()
    HudManager.drawNativePanel(posX, posY, { os.date("!%H:%M:%S", uzTimestamp) })
end

function HudManager.renderDateNative()
    if not HudManager.dateBar.enabled then return end

    local posX = tonumber(HudManager.dateBar.pos.x) or 0
    local posY = tonumber(HudManager.dateBar.pos.y) or 0
    if posX <= 0 and posY <= 0 then
        local sx, sy = 0, 0
        if getScreenResolution then
            local okRes, w, h = pcall(getScreenResolution)
            if okRes then sx, sy = w or 0, h or 0 end
        end
        posX = math.max(10, (sx > 0 and sx or 1280) - 125)
        posY = 30
    end

    local uzTimestamp = UtilityManager.getUzTimestamp()
    local weekdayIndex = tonumber(os.date("!%w", uzTimestamp)) or 0
    local weekdayText = HudManager.weekdays[weekdayIndex + 1] or ""
    local dateText = os.date("!%d.%m.%Y", uzTimestamp)
    HudManager.drawNativePanel(posX, posY, { weekdayText, dateText })
end

function HudManager.renderAdminBarNative()
    if not HudManager.adminBar.enabled then return end

    local posX = tonumber(HudManager.adminBar.pos.x) or 0
    local posY = tonumber(HudManager.adminBar.pos.y) or 0
    if posX <= 0 and posY <= 0 then
        local sx, sy = 0, 0
        if getScreenResolution then
            local okRes, w, h = pcall(getScreenResolution)
            if okRes then sx, sy = w or 0, h or 0 end
        end
        posX = math.max(10, (sx > 0 and sx or 1280) - 270)
        posY = 76
    end

    local lines = {
        "Admins Online: " .. (HudManager.adminCount and tostring(HudManager.adminCount) or "updating..."),
        string.format("Play Time: %s", UtilityManager.formatTime(StatsManager.data.session.playtime or 0)),
        "Admin Levels:"
    }
    for _, line in ipairs(HudManager.getAdminListLines(6)) do
        table.insert(lines, line)
    end

    HudManager.drawNativePanel(posX, posY, lines, HudManager.makeColor(235 * HudManager.opacity, 65, 156, 255))
end

function HudManager.renderNative()
    if HudManager.editMode then return end
    HudManager.renderClockNative()
    HudManager.renderDateNative()
    HudManager.renderAdminBarNative()
end

-- ============================================
-- EDIT-MODE RENDERING (imgui, faqat M panel ichida tahrirlash uchun)
-- ============================================
function HudManager.renderClockEdit()
    if not HudManager.clock.enabled or not HudManager.editMode then return end

    local posX = tonumber(HudManager.clock.pos.x) or 0
    local posY = tonumber(HudManager.clock.pos.y) or 0
    if posX <= 0 and posY <= 0 then
        local io = imgui.GetIO and imgui.GetIO()
        local screenX = (io and io.DisplaySize and io.DisplaySize.x) or 1280
        posX = math.max(10, screenX - 130)
        posY = 10
    end

    local flags = imgui.WindowFlags.NoResize +
                  imgui.WindowFlags.NoScrollbar +
                  imgui.WindowFlags.NoCollapse +
                  imgui.WindowFlags.NoSavedSettings

    if not HudManager.clock.initialized then
        imgui.SetNextWindowPos(imgui.ImVec2(posX, posY), imgui.Cond.Always)
        HudManager.clock.initialized = true
    end

    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.05, 0.06, 0.08, 0.35))
    local styleVarPushed = 0
    if imgui.PushStyleVar and imgui.StyleVar then
        imgui.PushStyleVar(imgui.StyleVar.WindowRounding, 8)
        styleVarPushed = styleVarPushed + 1
    end
    if imgui.Begin(u8"Soat (sudrab ko'chiring)##HudClockEdit", nil, flags) then
        if imgui.SetWindowFontScale then
            imgui.SetWindowFontScale(HudManager.scale)
        end
        local currentPos = imgui.GetWindowPos()
        HudManager.clock.pos.x = currentPos.x
        HudManager.clock.pos.y = currentPos.y
        HudManager.storeToSettings()

        local uzTimestamp = UtilityManager.getUzTimestamp()
        imgui.TextColored(COLORS.PRIMARY or imgui.ImVec4(0.3, 0.9, 0.5, 1.0), os.date("!%H:%M:%S", uzTimestamp))
    end
    imgui.End()
    if styleVarPushed > 0 and imgui.PopStyleVar then
        imgui.PopStyleVar(styleVarPushed)
    end
    imgui.PopStyleColor()
end

function HudManager.renderDateEdit()
    if not HudManager.dateBar.enabled or not HudManager.editMode then return end

    local posX = tonumber(HudManager.dateBar.pos.x) or 0
    local posY = tonumber(HudManager.dateBar.pos.y) or 0
    if posX <= 0 and posY <= 0 then
        local io = imgui.GetIO and imgui.GetIO()
        local screenX = (io and io.DisplaySize and io.DisplaySize.x) or 1280
        posX = math.max(10, screenX - 160)
        posY = 42
    end

    local flags = imgui.WindowFlags.NoResize +
                  imgui.WindowFlags.NoScrollbar +
                  imgui.WindowFlags.NoCollapse +
                  imgui.WindowFlags.NoSavedSettings

    if not HudManager.dateBar.initialized then
        imgui.SetNextWindowPos(imgui.ImVec2(posX, posY), imgui.Cond.Always)
        HudManager.dateBar.initialized = true
    end

    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.05, 0.06, 0.08, 0.35))
    local styleVarPushed = 0
    if imgui.PushStyleVar and imgui.StyleVar then
        imgui.PushStyleVar(imgui.StyleVar.WindowRounding, 8)
        styleVarPushed = styleVarPushed + 1
    end
    if imgui.Begin(u8"Sana (sudrab ko'chiring)##HudDateEdit", nil, flags) then
        if imgui.SetWindowFontScale then
            imgui.SetWindowFontScale(HudManager.scale)
        end
        local currentPos = imgui.GetWindowPos()
        HudManager.dateBar.pos.x = currentPos.x
        HudManager.dateBar.pos.y = currentPos.y
        HudManager.storeToSettings()

        local uzTimestamp = UtilityManager.getUzTimestamp()
        local weekdayIndex = tonumber(os.date("!%w", uzTimestamp)) or 0
        imgui.Text(HudManager.weekdays[weekdayIndex + 1] or "")
        imgui.Text(os.date("!%d.%m.%Y", uzTimestamp))
    end
    imgui.End()
    if styleVarPushed > 0 and imgui.PopStyleVar then
        imgui.PopStyleVar(styleVarPushed)
    end
    imgui.PopStyleColor()
end

function HudManager.renderAdminBarEdit()
    if not HudManager.adminBar.enabled or not HudManager.editMode then return end

    local posX = tonumber(HudManager.adminBar.pos.x) or 0
    local posY = tonumber(HudManager.adminBar.pos.y) or 0
    if posX <= 0 and posY <= 0 then
        local io = imgui.GetIO and imgui.GetIO()
        local screenX = (io and io.DisplaySize and io.DisplaySize.x) or 1280
        posX = math.max(10, screenX - 240)
        posY = 42
    end

    local flags = imgui.WindowFlags.NoResize +
                  imgui.WindowFlags.NoScrollbar +
                  imgui.WindowFlags.NoCollapse +
                  imgui.WindowFlags.NoSavedSettings

    if not HudManager.adminBar.initialized then
        imgui.SetNextWindowPos(imgui.ImVec2(posX, posY), imgui.Cond.Always)
        HudManager.adminBar.initialized = true
    end

    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.05, 0.06, 0.08, 0.35))
    local styleVarPushed = 0
    if imgui.PushStyleVar and imgui.StyleVar then
        imgui.PushStyleVar(imgui.StyleVar.WindowRounding, 8)
        styleVarPushed = styleVarPushed + 1
    end
    if imgui.Begin(u8"Adminlar (sudrab ko'chiring)##HudAdminEdit", nil, flags) then
        if imgui.SetWindowFontScale then
            imgui.SetWindowFontScale(HudManager.scale)
        end
        local currentPos = imgui.GetWindowPos()
        HudManager.adminBar.pos.x = currentPos.x
        HudManager.adminBar.pos.y = currentPos.y
        HudManager.storeToSettings()

        imgui.TextColored(COLORS.INFO or imgui.ImVec4(0.4, 0.7, 1.0, 1.0),
            "Admins Online: " .. (HudManager.adminCount and tostring(HudManager.adminCount) or "updating..."))
        imgui.Text(string.format("Play Time: %s", UtilityManager.formatTime(StatsManager.data.session.playtime or 0)))
        imgui.Text("Admin Levels:")
        for _, line in ipairs(HudManager.getAdminListLines(6)) do
            imgui.Text(u8(line))
        end
    end
    imgui.End()
    if styleVarPushed > 0 and imgui.PopStyleVar then
        imgui.PopStyleVar(styleVarPushed)
    end
    imgui.PopStyleColor()
end

function HudManager.renderEditOverlay()
    HudManager.renderClockEdit()
    HudManager.renderDateEdit()
    HudManager.renderAdminBarEdit()
end

-- ============================================
-- COMMAND HANDLERS
-- ============================================
function processCommand(cmd)
    local args = {}
    for arg in cmd:gmatch("%S+") do
        table.insert(args, arg)
    end

    if not args[1] then return true end
    local command = args[1]:gsub("^/", ""):lower()

    if command == "admin" or command == "admins" then
        HudManager.beginAdminCapture()
    end

    if command == "amenu" then
        sampAddChatMessage("[Harvey] /amenu disabled. M tugmasini bosib admin panelni oching.", -1)
        return false
    end

    if command == "rld" or command == "rdl" then
        SpectateQuickPanel.saveUiToDisk()
        if StatsManager and StatsManager.save then
            StatsManager.save()
        end
        SCRIPT_RELOAD_REQUESTED = true
        sampAddChatMessage("[Harvey] Qayta yuklash so'raldi: skript qayta yuklanmoqda...", 0x33FF66)
        return false
    end

    if command == "rec" then
        local delay = tonumber(args[2]) or 5
        local okRec, message = ReconnectManager.start(delay)
        sampAddChatMessage("[Harvey] " .. tostring(message or ""), okRec and 0x33FF66 or 0xFF6666)
        return false
    end

    if command == "ans" then
        local answeredId = tonumber(args[2])
        if answeredId then
            if StatsManager.registerOutgoingAnswer(answeredId, cmd) then
                StatsManager.addAnswer(answeredId)
            end
            ReportCatchManager.markAnswered(answeredId)
            if ReportCatchManager.popupOpen and ReportCatchManager.currentReport and
               tonumber(ReportCatchManager.currentReport.id) == answeredId then
                ReportCatchManager.closePopup()
            end
        end
    end

    if AdminRelayManager and AdminRelayManager.parseCommandParts and
       AdminRelayManager.extractTargetId and AdminRelayManager.updatePunishmentState then
        local outgoingInfo = AdminRelayManager.parseCommandParts(cmd)
        if outgoingInfo and AdminRelayManager.playerIdCommands and AdminRelayManager.playerIdCommands[outgoingInfo.name] then
            local outgoingTargetId = AdminRelayManager.extractTargetId(outgoingInfo)
            AdminRelayManager.updatePunishmentState(outgoingInfo.name, outgoingTargetId)
        end
    end

    SpectateQuickPanel.handleCommand(command, args)

    SecurityManager.logCommand(0, cmd)

    return true
end

-- ============================================
-- SAMPEV EVENTS
-- ============================================
function sampev.onSendCommand(cmd)
    return processCommand(cmd)
end

function sampev.onServerMessage(color, text)
    if TeleportClickManager and type(TeleportClickManager.captureVehicleIdFromServerMessage) == "function" then
        TeleportClickManager.captureVehicleIdFromServerMessage(text)
    end

    local answerMatch = text:match("Answer #(%d+)")
    if answerMatch then
        local id = tonumber(answerMatch)
        if not StatsManager.consumeOutgoingAnswer(id) then
            StatsManager.addAnswer(id)
        end
        LogManager.admin(string.format("Answer detected: #%d", id))
        ReportCatchManager.markAnswered(id)
        if ReportCatchManager.popupOpen and ReportCatchManager.currentReport and
           tonumber(ReportCatchManager.currentReport.id) == id then
            ReportCatchManager.closePopup()
        end
    end

    FuraKillManager.processStatsMessage(text)

    HudManager.processServerMessage(text)

    AdminRelayManager.processIncomingMessage(text)

    local consumedByPunishmentCheck = ReportCatchManager.processPunishmentInfoMessage(text)
    if consumedByPunishmentCheck then
        return false
    end

    ReportCatchManager.processReport(text)

    return true
end

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    if HudManager and type(HudManager.processAdminDialog) == "function" then
        if HudManager.processAdminDialog(title, text) then
            return false
        end
    end
    if FuraKillManager and type(FuraKillManager.processStatsDialog) == "function" then
        FuraKillManager.processStatsDialog(dialogId, style, title, button1, button2, text)
    end
    if ReportCatchManager and type(ReportCatchManager.processPunishmentInfoDialog) == "function" then
        ReportCatchManager.processPunishmentInfoDialog(dialogId, style, title, button1, button2, text)
    end
    if NavigatorManager and type(NavigatorManager.captureGpsDialog) == "function" then
        NavigatorManager.captureGpsDialog(dialogId, style, title, button1, button2, text)
    end
end

function sampev.onSendDialogResponse(dialogId, button, listboxId, inputText)
    if NavigatorManager and type(NavigatorManager.handleDialogResponse) == "function" then
        NavigatorManager.handleDialogResponse(dialogId, button, listboxId, inputText)
    end
end

function sampev.onPlayerDeathNotification(killerId, killedId, reason)
    FuraKillManager.onPlayerDeathNotification(killerId, killedId, reason)
end

function sampev.onSendChat(msg)
    if msg:sub(1, 1) == "/" then
        return processCommand(msg)
    end

    local filtered, word = SecurityManager.checkChatFilter(msg)
    if filtered then
        LogManager.security(string.format("Filtered word detected: %s", word))
    end

    return true
end

function onScriptTerminate(script, quitGame)
    if type(thisScript) == "function" and script and script ~= thisScript() then
        return
    end

    if SpectateQuickPanel and SpectateQuickPanel.saveUiToDisk then
        SpectateQuickPanel.saveUiToDisk()
    end

    if HudManager and HudManager.saveToDisk then
        HudManager.saveToDisk()
    end

    if AdminModesManager and AdminModesManager.restore then
        AdminModesManager.restore()
    end

    if StatsManager and StatsManager.save then
        StatsManager.save()
    end
end

-- ============================================
-- GLOBAL VARIABLES FOR KEY HANDLING
-- ============================================
local M_KEY_PRESSED = false
local M_KEY_LAST_STATE = false
SCRIPT_RELOAD_REQUESTED = false

-- ============================================
-- MAIN THREAD
-- ============================================
function main()
    -- Wait for SAMP to load
    while not isSampLoaded() do
        wait(100)
    end

    while not isSampAvailable() do
        wait(100)
    end

    -- Initialize all managers
    UtilityManager.initialize()
    LogManager.initialize()
    SettingsManager.initialize()
    StatsManager.initialize()
    HudManager.initialize()
    AFKManager.initialize()
    ReportManager.initialize()
    ReportCatchManager.initialize()
    AdminRelayManager.initialize()
    PlayerManager.initialize()
    TeleportManager.initialize()
    ServerManager.initialize()
    SecurityManager.initialize()
    AnalyticsManager.initialize()
    FuraKillManager.initialize()
    MainUI.initialize()

    -- Initialize imgui process state
    imgui.Process = false
    imgui.ShowCursor = false

    -- Print welcome message
    print(string.format("Grand Mobile Tools by Harvey v%s yuklandi", CONFIG.VERSION))
    print(string.format("%s tugmasini bosing - admin panel ochiladi", SettingsManager.getHotkeyName()))
    sampAddChatMessage(string.format("[Harvey] Grand Mobile Tools by Harvey v%s yuklandi", CONFIG.VERSION), 0x00FF00)
    sampAddChatMessage("[Harvey] M tugmasini bosib admin panelni oching", 0x00FF00)
    sampAddChatMessage("[Harvey] Qayta yuklash buyrug'i: /rld", 0x00FF00)
    sampAddChatMessage("[Harvey] Report Catch: YOQIQ (N tugmasi bilan o'chirish/yoqish)", 0x00FF00)
    sampAddChatMessage("[Harvey] Tinglash: faqat server xabarlari", 0x00FF00)

    LogManager.system("Tizim muvaffaqiyatli ishga tushirildi")

    -- Main loop
    local lastSave = os.time()
    local lastAFKCheck = os.time()
    local frameCount = 0

    while true do
        wait(0)

        if SCRIPT_RELOAD_REQUESTED then
            SCRIPT_RELOAD_REQUESTED = false
            if type(thisScript) == "function" then
                local okScript, scriptObj = pcall(thisScript)
                if okScript and scriptObj and scriptObj.reload then
                    local okReload = pcall(function()
                        scriptObj:reload()
                    end)
                    if okReload then
                        return
                    end
                end
            end
            sampAddChatMessage("[Harvey] Qayta yuklash muvaffaqiyatsiz: MoonLoader qo'llab-quvvatlamadi.", 0xFF6666)
        end

        frameCount = frameCount + 1

        -- AFK check (every second)
        if os.time() - lastAFKCheck >= 1 then
            AFKManager.checkPosition()
            StatsManager.updatePlaytime()
            lastAFKCheck = os.time()
        end

        ReportCatchManager.updatePendingPunishmentCheck()
        ReportCatchManager.processKeywordTpQueue()
        ReconnectManager.update()
        AdminModesManager.update()
        NavigatorManager.update()
        FuraKillManager.update()
        HudManager.update()
        HudManager.renderNative()

        -- Keep reset checks without touching filesystem in this environment
        if os.time() - lastSave >= CONFIG.AUTO_SAVE_INTERVAL then
            StatsManager.checkReset()
            StatsManager.save() -- Auto-save stats
            lastSave = os.time()
        end

        -- Keep imgui active when any panel is visible
        local spectatePanelActive = SpectateQuickPanel.active and SpectateQuickPanel.targetId ~= nil
        local clickTpActive = TeleportClickManager.enabled
        imgui.Process = MainUI.window.open or ReportCatchManager.popupOpen or AdminRelayManager.popupOpen or
                       (spectatePanelActive and SpectateQuickPanel.cursorVisible) or clickTpActive
        imgui.ShowCursor = MainUI.window.open or ReportCatchManager.popupOpen or AdminRelayManager.popupOpen or
                           (spectatePanelActive and SpectateQuickPanel.cursorVisible) or clickTpActive

        local clickTpCanToggle = not sampIsChatInputActive() and not sampIsDialogActive()
        local clickTpCanTeleport = clickTpCanToggle and
                                  not MainUI.window.open and
                                  not ReportCatchManager.popupOpen and
                                  not AdminRelayManager.popupOpen and
                                  not spectatePanelActive
        TeleportClickManager.update(clickTpCanToggle, clickTpCanTeleport)

        local rightMouseClicked = false
        local spacePressed = false
        if spectatePanelActive and not MainUI.window.open and not ReportCatchManager.popupOpen and
           not AdminRelayManager.popupOpen and
           not sampIsChatInputActive() and not sampIsDialogActive() then
            rightMouseClicked = SpectateQuickPanel.isRightMouseClicked()
            spacePressed = SpectateQuickPanel.isSpacePressed()
        else
            SpectateQuickPanel.rightMouseLastState = false
            SpectateQuickPanel.spaceLastState = false
        end

        if spectatePanelActive and rightMouseClicked then
            SpectateQuickPanel.cursorVisible = not SpectateQuickPanel.cursorVisible
        end

        if spectatePanelActive and spacePressed then
            SpectateQuickPanel.cursorVisible = false
        end

        -- KEY HANDLER - Main panel toggle with M key
        -- Use isKeyDown with manual toggle logic for reliability
        local mKeyDown = isKeyDown(vkeys.VK_M)

        -- Detect rising edge (key just pressed)
        if mKeyDown and not M_KEY_LAST_STATE then
            -- Check if chat is not open (don't toggle when typing)
            if not sampIsChatInputActive() and not sampIsDialogActive() then
                MainUI.toggle()
            end
        end

        M_KEY_LAST_STATE = mKeyDown

        -- Key handler - Report Catch enable/disable (N key)
        if isKeyJustPressed(ReportCatchManager.settings.hotkey) then
            if not sampIsChatInputActive() and not sampIsDialogActive() then
                local state = ReportCatchManager.toggle()
                sampAddChatMessage(string.format("[Harvey] Report Catch: %s (N)", state and "YOQIQ" or "O'CHIQ"), 0x00FF00)
                if state and #ReportCatchManager.reportQueue > 0 and not ReportCatchManager.popupOpen then
                    local nextReport = table.remove(ReportCatchManager.reportQueue)
                    ReportCatchManager.showReport(nextReport)
                end
            end
        end
    end
end
