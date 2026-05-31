-- imgplay: display images and GIFs on ComputerCraft
-- Usage: imgplay <url> [fps]
-- Example: imgplay https://media.giphy.com/media/xyz/giphy.gif 10

local args = {...}
if #args < 1 then
    print("Usage: imgplay <url> [fps]")
    return
end

local url   = args[1]
local fps   = tonumber(args[2]) or 10
local delay = 1 / fps

local server = settings.get("youcube.server") or "wss://youcube-server-production.up.railway.app"
local http_server = server:gsub("^wss://", "https://"):gsub("^ws://", "http://")

local w, h = term.getSize()

local function urlencode(s)
    return s:gsub("[^%w%-%.%_%~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

print("Fetching image...")
local response, err = http.get(
    http_server .. "/image?url=" .. urlencode(url) .. "&width=" .. w .. "&height=" .. h,
    nil, true
)

if not response then
    error("Failed to fetch: " .. (err or "unknown error"))
end

local data = response.readAll()
response.close()

if data:sub(1, 1) ~= "0" and #data < 10 then
    error("Server error: " .. data)
end

-- parse frames separated by ---
local frames = {}
for frame in (data .. "\n---\n"):gmatch("(.-)\n%-%-%-\n") do
    local rows = {}
    for row in (frame .. "\n"):gmatch("([^\n]*)\n") do
        if #row > 0 then rows[#rows + 1] = row end
    end
    if #rows > 0 then frames[#frames + 1] = rows end
end

if #frames == 0 then
    error("Could not decode any frames")
end

print("Loaded " .. #frames .. " frame(s). Press Q to stop.")
sleep(1)

local color_map = {
    ["0"]=colors.white,    ["1"]=colors.orange,
    ["2"]=colors.magenta,  ["3"]=colors.lightBlue,
    ["4"]=colors.yellow,   ["5"]=colors.lime,
    ["6"]=colors.pink,     ["7"]=colors.gray,
    ["8"]=colors.lightGray,["9"]=colors.cyan,
    ["a"]=colors.purple,   ["b"]=colors.blue,
    ["c"]=colors.brown,    ["d"]=colors.green,
    ["e"]=colors.red,      ["f"]=colors.black,
}

local function draw(frame)
    for y, row in ipairs(frame) do
        if y > h then break end
        for x = 1, math.min(#row, w) do
            local c = color_map[row:sub(x, x)]
            if c then
                term.setCursorPos(x, y)
                term.setBackgroundColor(c)
                term.write(" ")
            end
        end
    end
end

local running = true
term.clear()

parallel.waitForAny(
    function()
        local i = 1
        while running do
            draw(frames[i])
            i = (i % #frames) + 1
            sleep(delay)
        end
    end,
    function()
        while true do
            local _, key = os.pullEvent("key")
            if key == keys.q then
                running = false
                return
            end
        end
    end
)

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
