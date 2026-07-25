-- ============================================
-- SA-MP TO WEB DASHBOARD BRIDGE (UNIVERSAL FIX)
-- ============================================
local sampev = require("lib.samp.events")
local http = require("socket.http")
local ltn12 = require("ltn12")

local SERVER_URL = "http://127.0.0.1:3000"

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    sampAddChatMessage("{00FF00}[Mobile Admin Hub]{FFFFFF} Universal ko'prik yoqildi!", -1)

    while true do
        wait(300)
        checkCommands()
    end
end

function checkCommands()
    lua_thread.create(function()
        http.TIMEOUT = 0.2
        local response_body = {}
        local res, code = http.request{
            url = SERVER_URL .. "/api/get-commands",
            sink = ltn12.sink.table(response_body)
        }

        if code == 200 then
            local body = table.concat(response_body)
            for cmd in body:gmatch('"([^"]+)"') do
                if cmd and #cmd > 0 then
                    cmd = cmd:gsub("\\/", "/")
                    sampSendChat(cmd)
                end
            end
        end
    end)
end

-- SERVER CHATIDAN REPORT VA ADMIN CHATNI USHLASH
function sampev.onServerMessage(color, text)
    local msg = tostring(text or "")
    local cleanMsg = msg:gsub("{%x%x%x%x%x%x}", "") -- Rang kodlarini olib tashlash

    -- A) Admin Chat ([A], [ADM], [Admin])
    if cleanMsg:find("%[A%]") or cleanMsg:find("%[ADM%]") or cleanMsg:find("%[Admin%]") then
        sendToWeb("/api/send-chat", cleanMsg)
    end

    -- B) Har qanday Report va Shikoyat shakllari
    local checkText = cleanMsg:lower()
    if checkText:find("report") or checkText:find("жалоба") or checkText:find("репорт") or checkText:find("вопрос") or checkText:find("%[rep%]") then
        -- Takroriy bo'lmagan asl reportlarni yuborish
        if not checkText:find("ответил") and not checkText:find("javob berdi") then
            sendToWeb("/api/send-report", cleanMsg)
        end
    end
end

function sendToWeb(endpoint, text)
    lua_thread.create(function()
        http.TIMEOUT = 0.3
        local safeText = text:gsub('\\', '/'):gsub('"', "'"):gsub('\n', ' ')
        local reqbody = '{"text":"' .. safeText .. '"}'
        
        http.request{
            url = SERVER_URL .. endpoint,
            method = "POST",
            headers = {
                ["Content-Type"] = "application/json",
                ["Content-Length"] = tostring(#reqbody)
            },
            source = ltn12.source.string(reqbody)
        }
    end)
end