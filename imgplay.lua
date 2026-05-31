-- imgplay: display images and GIFs on ComputerCraft
-- Single image:  imgplay <url> [--fps N]
-- Slideshow:     imgplay <url1> <url2> ... [--delay N] [--fps N] [--loop]
-- Options:
--   --fps N      GIF playback frame rate (default 10)
--   --delay N    seconds between slides (default 5)
--   --loop       repeat slideshow forever until Q
--   --monitor S  use monitor on side S (default: auto-detect)

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
local px_w, px_h = dw, dh

local server = settings.get("youcube.server") or "wss://youcube-server-production.up.railway.app"
local http_server = server:gsub("^wss://", "https://"):gsub("^ws://", "http://")

local function urlencode(s)
    return s:gsub("[^%w%-%.%_%~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end


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

local function draw(surface, frame, prev)
    for y = 1, math.min(#frame, dh) do
        local row = frame[y]
        if prev and prev[y] == row then goto continue end
        local bg = row:sub(1, dw)
        if #bg < dw then bg = bg .. string.rep("f", dw - #bg) end
        local n = #bg
        surface.setCursorPos(1, y)
        surface.blit(string.rep(" ", n), string.rep("f", n), bg)
        ::continue::
    end
end

local running = true
local is_slideshow = #all_frames > 1
local MIN_FRAME_SLEEP = 0.05

local function play()
    if display.setCursorBlink then display.setCursorBlink(false) end
    repeat
        for _, frames in ipairs(all_frames) do
            if not running then return end
            local fi = 1
            local is_gif = #frames > 1
            local start = os.clock()
            local prev = nil
            while running do
                draw(display, frames[fi], prev)
                prev = frames[fi]
                if is_gif then
                    fi = (fi % #frames) + 1
                    sleep(math.max(1/fps, MIN_FRAME_SLEEP))
                    if is_slideshow and (os.clock()-start) >= delay then break end
                else
                    if is_slideshow then sleep(delay); break
                    else while running do sleep(0.5) end end
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
