-- imgplay: display images and GIFs on ComputerCraft
-- Single image:  imgplay <url> [--fps N]
-- Slideshow:     imgplay <url1> <url2> ... [--delay N] [--fps N] [--loop]
-- Options:
--   --fps N      GIF playback frame rate (default 10)
--   --delay N    seconds between slides (default 5)
--   --loop       repeat slideshow forever until Q
--   --monitor S  use monitor on side S (default: auto-detect)

-- half-block char: upper half = fg color, lower half = bg color → 2x vertical res
local HALF = "\xe2\x96\x80"

local args, urls, fps, delay, loop_slides, mon_side = {...}, {}, 10, 5, false, nil

local i = 1
while i <= #args do
    local a = args[i]
    if a == "--fps"     and args[i+1] then i=i+1; fps        = tonumber(args[i]) or 10
    elseif a == "--delay"  and args[i+1] then i=i+1; delay      = tonumber(args[i]) or 5
    elseif a == "--loop"                 then loop_slides = true
    elseif a == "--monitor" and args[i+1] then i=i+1; mon_side   = args[i]
    elseif a:sub(1,1) ~= "-"             then urls[#urls+1] = a
    end
    i = i + 1
end

if #urls == 0 then
    print("Usage: imgplay <url> [url2 ...] [--fps N] [--delay N] [--loop] [--monitor <side>]")
    return
end

-- find display (monitor > terminal)
local display = term
if mon_side then
    display = peripheral.wrap(mon_side) or term
else
    local mon = peripheral.find("monitor")
    if mon then display = mon end
end

-- max resolution on monitor
if display ~= term and display.setTextScale then
    display.setTextScale(0.5)
end

local dw, dh = display.getSize()
-- half-block: each char row covers 2 pixel rows
local px_w, px_h = dw, dh * 2

local server = settings.get("youcube.server") or "wss://youcube-server-production.up.railway.app"
local http_server = server:gsub("^wss://", "https://"):gsub("^ws://", "http://")

local function urlencode(s)
    return s:gsub("[^%w%-%.%_%~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

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

local function fetch(url)
    local res, err = http.get(
        http_server .. "/image?url=" .. urlencode(url)
        .. "&width=" .. px_w .. "&height=" .. px_h,
        nil, true
    )
    if not res then return nil, err or "request failed" end
    local data = res.readAll(); res.close()

    local frames = {}
    for frame in (data .. "\n---\n"):gmatch("(.-)\n%-%-%-\n") do
        local rows = {}
        for row in (frame .. "\n"):gmatch("([^\n]*)\n") do
            if #row > 0 then rows[#rows+1] = row end
        end
        if #rows > 0 then frames[#frames+1] = rows end
    end
    return #frames > 0 and frames or nil, "no frames decoded"
end

-- pre-fetch
local all_frames = {}
for idx, url in ipairs(urls) do
    term.clear(); term.setCursorPos(1,1)
    print(("Fetching %d/%d..."):format(idx, #urls))
    print(url)
    local frames, err = fetch(url)
    if frames then
        all_frames[#all_frames+1] = frames
        print("OK - " .. #frames .. " frame(s)")
    else
        print("FAILED: " .. (err or "?") .. " — skipping")
        sleep(1)
    end
end

if #all_frames == 0 then error("No images loaded") end

term.clear(); term.setCursorPos(1,1)
local using_mon = display ~= term
print("Loaded " .. #all_frames .. " image(s).")
print("Display: " .. (using_mon and "monitor " .. dw .. "x" .. dh or "terminal") ..
      " | pixels: " .. px_w .. "x" .. px_h)
if #all_frames > 1 then
    print("Slideshow — " .. delay .. "s per slide" .. (loop_slides and ", looping" or "") .. ".")
end
print("Press Q to stop.")
sleep(1.5)

-- half-block draw: pairs pixel rows → one char row each
local function draw(surface, frame)
    for cy = 1, dh do
        local top_row = frame[cy*2 - 1] or ""
        local bot_row = frame[cy*2]     or ""
        for cx = 1, dw do
            local tc = color_map[top_row:sub(cx,cx)] or colors.black
            local bc = color_map[bot_row:sub(cx,cx)]  or colors.black
            surface.setCursorPos(cx, cy)
            if tc == bc then
                -- same color: solid block, no text color needed
                surface.setBackgroundColor(tc)
                surface.write(" ")
            else
                surface.setTextColor(tc)
                surface.setBackgroundColor(bc)
                surface.write(HALF)
            end
        end
    end
end

local running = true
local is_slideshow = #all_frames > 1

local function play()
    repeat
        for _, frames in ipairs(all_frames) do
            if not running then return end
            local fi = 1
            local is_gif = #frames > 1
            local start = os.clock()
            while running do
                draw(display, frames[fi])
                if is_gif then
                    fi = (fi % #frames) + 1
                    sleep(1/fps)
                    if is_slideshow and (os.clock()-start) >= delay then break end
                else
                    if is_slideshow then sleep(delay); break
                    else sleep(0.05) end
                end
            end
        end
    until not running or (is_slideshow and not loop_slides)
end

display.clear()

parallel.waitForAny(
    play,
    function()
        while true do
            local _, key = os.pullEvent("key")
            if key == keys.q then running = false; return end
        end
    end
)

display.setBackgroundColor(colors.black)
display.clear()
if display ~= term then
    term.setCursorPos(1,1)
    print("Done.")
else
    term.setCursorPos(1,1)
end
