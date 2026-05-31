-- imgplay: display images and GIFs on ComputerCraft
-- Single image:  imgplay <url> [--fps N]
-- Slideshow:     imgplay <url1> <url2> ... [--delay N] [--fps N] [--loop]
-- Options:
--   --fps N    GIF playback frame rate (default 10)
--   --delay N  seconds between slides (default 5)
--   --loop     repeat slideshow forever until Q

local args = {...}
local urls, fps, delay, loop_slides = {}, 10, 5, false

local i = 1
while i <= #args do
    local a = args[i]
    if a == "--fps" and args[i+1] then
        i = i + 1; fps = tonumber(args[i]) or 10
    elseif a == "--delay" and args[i+1] then
        i = i + 1; delay = tonumber(args[i]) or 5
    elseif a == "--loop" then
        loop_slides = true
    elseif a:sub(1,1) ~= "-" then
        urls[#urls + 1] = a
    end
    i = i + 1
end

if #urls == 0 then
    print("Usage: imgplay <url> [url2 ...] [--fps N] [--delay N] [--loop]")
    print("")
    print("  Single image/GIF - loops until Q")
    print("  Multiple URLs    - slideshow, use --loop to repeat")
    print("  --fps N          GIF frame rate (default 10)")
    print("  --delay N        seconds per slide (default 5)")
    print("  --loop           repeat slideshow until Q")
    return
end

local server = settings.get("youcube.server") or "wss://youcube-server-production.up.railway.app"
local http_server = server:gsub("^wss://", "https://"):gsub("^ws://", "http://")
local w, h = term.getSize()

local function urlencode(s)
    return s:gsub("[^%w%-%.%_%~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local function fetch(url)
    local res, err = http.get(
        http_server .. "/image?url=" .. urlencode(url) .. "&width=" .. w .. "&height=" .. h,
        nil, true
    )
    if not res then return nil, err or "request failed" end
    local data = res.readAll()
    res.close()

    local frames = {}
    for frame in (data .. "\n---\n"):gmatch("(.-)\n%-%-%-\n") do
        local rows = {}
        for row in (frame .. "\n"):gmatch("([^\n]*)\n") do
            if #row > 0 then rows[#rows + 1] = row end
        end
        if #rows > 0 then frames[#frames + 1] = rows end
    end
    return #frames > 0 and frames or nil, "no frames decoded"
end

-- pre-fetch all images
local all_frames = {}
for idx, url in ipairs(urls) do
    term.clear(); term.setCursorPos(1, 1)
    print(("Fetching %d/%d..."):format(idx, #urls))
    print(url)
    local frames, err = fetch(url)
    if frames then
        all_frames[#all_frames + 1] = frames
        print("OK - " .. #frames .. " frame(s)")
    else
        print("FAILED: " .. (err or "?") .. " — skipping")
        sleep(1)
    end
end

if #all_frames == 0 then error("No images loaded") end

term.clear(); term.setCursorPos(1, 1)
print("Loaded " .. #all_frames .. " image(s).")
if #all_frames > 1 then
    print("Slideshow — " .. delay .. "s per slide" .. (loop_slides and ", looping" or "") .. ".")
end
print("Press Q to stop.")
sleep(1.5)

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
local is_slideshow = #all_frames > 1

local function play()
    repeat
        for _, frames in ipairs(all_frames) do
            if not running then return end
            local fi = 1
            local is_gif = #frames > 1
            local start = os.clock()

            while running do
                draw(frames[fi])
                if is_gif then
                    fi = (fi % #frames) + 1
                    sleep(1 / fps)
                    -- in slideshow, move to next slide after delay
                    if is_slideshow and (os.clock() - start) >= delay then break end
                else
                    -- static image
                    if is_slideshow then sleep(delay); break
                    else sleep(0.05) end  -- single image: redraw loop until Q
                end
            end
        end
    until not running or (is_slideshow and not loop_slides)
end

term.clear()

parallel.waitForAny(
    play,
    function()
        while true do
            local _, key = os.pullEvent("key")
            if key == keys.q then running = false; return end
        end
    end
)

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
