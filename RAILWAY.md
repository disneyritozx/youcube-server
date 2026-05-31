# Deploy YouCube Server on Railway (Free)

Host your own YouCube server for free using [Railway](https://railway.com). No credit card required on the hobby plan ($5 free credits/month — enough for light use).

## 1. Fork the repo

Fork [disneyritozx/youcube-server](https://github.com/disneyritozx/youcube-server) to your own GitHub account.

## 2. Deploy on Railway

1. Go to [railway.com](https://railway.com) → **New Project**
2. Choose **Deploy from GitHub repo**
3. Select your fork
4. Railway auto-detects `railway.json` and builds with the Dockerfile

## 3. Set required environment variables

In your Railway project → **Variables** tab, add:

| Variable | Value | Required |
|----------|-------|----------|
| `NO_FAST` | `true` | Yes — PyPy crashes with multiple workers |
| `HOST` | `0.0.0.0` | Yes — makes server accessible externally |
| `YT_COOKIES_B64` | *(see below)* | Yes — bypasses YouTube bot detection |

### Getting YouTube cookies

YouTube blocks requests from server IPs unless you provide browser cookies.

1. Install the **"Get cookies.txt LOCALLY"** extension ([Chrome](https://chrome.google.com/webstore/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc) / [Firefox](https://addons.mozilla.org/en-US/firefox/addon/cookies-txt/))
2. Log into [youtube.com](https://youtube.com) in your browser
3. Click the extension → select **youtube.com only** → export → save as `cookies.txt`
4. Encode it:
   ```bash
   base64 -w 0 cookies.txt
   ```
5. Copy the output and paste it as the value of `YT_COOKIES_B64` in Railway

> Cookies typically last 1–2 years. Re-export and update the variable if YouTube stops working.

## 4. Get your server URL

Railway assigns a public URL like `https://youcube-server-production.up.railway.app`.  
Find it under your project → **Settings** → **Domains**.

## 5. Configure the CC client

On your ComputerCraft computer:

```lua
settings.set("youcube.server", "wss://your-project.up.railway.app")
settings.save()
```

## 6. Install the CC client

```
wget run https://raw.githubusercontent.com/CC-YouCube/installer/main/installer.lua
```

## 7. Play

```
youcube https://www.youtube.com/watch?v=VIDEO_ID
```

Add a `speaker` peripheral to your computer for audio.  
Add an Advanced Monitor for video.

---

## imgplay — image & GIF viewer

`imgplay` renders images and animated GIFs on an Advanced Monitor using the `/image` endpoint on this server.

### Install

```
rm imgplay 2>/dev/null; wget https://raw.githubusercontent.com/disneyritozx/youcube-server/main/imgplay.lua imgplay
```

### Usage

```
imgplay <url>                          -- single image or GIF
imgplay <url1> <url2> --delay 5        -- slideshow, 5s per image
imgplay <url> --loop                   -- loop forever
imgplay <url> --fps 15                 -- override GIF frame rate
imgplay <url> --monitor right          -- use monitor on specific side
```

GIFs use native per-frame timing automatically. Press **Q** to stop.

---

## Troubleshooting

**"Sign in to confirm you're not a bot"** — `YT_COOKIES_B64` is missing, expired, or wrong. Re-export cookies and update the Railway variable.

**Audio only, no video** — requires sanjuuni (already in the Docker image). Make sure an Advanced Monitor is connected.

**Server not responding** — check Railway logs. `NO_FAST=true` must be set or PyPy will crash on startup.

**imgplay shows static image for GIF** — update imgplay: `rm imgplay && wget ... imgplay` (old version had a frame separator bug, fixed in current build).
