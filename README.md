# YouCube Server

[![Python Version: 3.7+]](https://www.python.org/downloads/)
[![Python Lint Workflow Status]](https://github.com/CC-YouCube/server/actions/workflows/pylint.yml)

![preview]

YouCube has a some public servers, which you can use if you don't want to host your own server. \
The client has the public servers set by default, so you can just run the client, and you're good to go. \
Moor Information about the servers can be seen on the [doc].

This fork includes Railway deployment support, YouTube cookie support for yt-dlp, and a patched `youcube.lua`
launcher that auto-routes video to a monitor when one is attached.

## Requirements

- [yt-dlp/FFmpeg] / [FFmpeg 5.1+]
- [sanjuuni]
- [Python 3.7+]
  - [sanic]
  - [yt-dlp]
  - [ujson] (Optional)
  - [spotipy]

You can install the required packages with [pip] by running:

```shell
pip install -r src/requirements.txt
```

## Starting the Server

```bash
python src/youcube.py
```

## Railway deployment

Railway builds this repo with `railway.json` and `src/Dockerfile`. Set these variables in Railway:

| Variable | Value | Required |
| -------- | ----- | -------- |
| `NO_FAST` | `true` | Yes - PyPy crashes with multiple workers |
| `HOST` | `0.0.0.0` | Yes - makes the server externally reachable |
| `YT_COOKIES_B64` | base64 encoded YouTube `cookies.txt` | Yes - helps yt-dlp avoid YouTube bot checks |
| `SANJUUNI_FPS` | `10` | No - output FPS before Sanjuuni conversion; use `0` to disable |

To generate `YT_COOKIES_B64`, export a slim `youtube.com` cookies.txt from your browser and run:

```bash
base64 -w 0 cookies.txt
```

Railway redeploys automatically when changes are pushed to `main`.

## ComputerCraft client

Configure the client to use your Railway WebSocket URL:

```lua
settings.set("youcube.server", "wss://youcube-server-production.up.railway.app")
settings.save()
```

Install the upstream client first:

```shell
wget run https://raw.githubusercontent.com/CC-YouCube/installer/main/installer.lua
```

Then update only the launcher from this fork:

```shell
rm youcube 2>/dev/null; wget https://raw.githubusercontent.com/disneyritozx/youcube-server/main/youcube.lua youcube
```

The forked launcher uses the first attached `monitor` for video and falls back to the terminal when no monitor is
found. It uses attached `speaker` peripherals for audio; if no speaker or tape drive is found, audio is disabled.

Monitor video defaults to text scale `1` for better FPS. Use `0.5` for higher resolution but slower playback:

```lua
settings.set("youcube.monitor_scale", 1)
settings.save()
```

## Environment variables

Environment variables you can use to configure the server:

| Variable                      | Default    | Description                                                                                                        |
| ----------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------ |
| `HOST`                        | `0.0.0.0`  | The host where the web server runs on.                                                                             |
| `PORT`                        | `5000`     | The port where the web server should run on                                                                        |
| `FFMPEG_PATH`                 | `ffmpeg`   | Path to the FFmpeg executable                                                                                      |
| `SANJUUNI_PATH`               | `sanjuuni` | Path to the Sanjuuni executable                                                                                    |
| `NO_COLOR`                    | `False`    | Disable colored output                                                                                             |
| `LOGLEVEL`                    | `DEBUG`    | Python Log level of the main logger                                                                                |
| `DISABLE_OPENCL`              | `False`    | Disables sanjuuni GPU acceleration                                                                                 |
| `SANJUUNI_FPS`                | `10`       | Output FPS before Sanjuuni conversion. Lower is faster; `0` disables FPS reduction.                                |
| `NO_FAST`                     | `False`    | Disable Sanic worker processes maximization                                                                        |
| `SPOTIPY_CLIENT_ID`           |            | The Client ID from your [spotify application]                                                                      |
| `SPOTIPY_CLIENT_SECRET`       |            | The Client Secret from your [spotify application]                                                                  |
| `DATA_CACHE_CLEANUP_INTERVAL` | `300`      | Time interval (in seconds) for the data cache cleaner to wait before checking for outdated cache entries.          |
| `DATA_CACHE_CLEANUP_AFTER`    | `3600`     | Time threshold (in seconds) for considering a cache entry outdated. Cache entries older than this will be removed. |

And [Sanic Builtin values].

## Docker Compose

```yml
---
services:
  youcube:
    image: ghcr.io/cc-youcube/youcube:latest
    restart: always
    hostname: youcube
    ports:
      - 5000:5000
...
```

[spotify application]: https://developer.spotify.com/dashboard/applications
[pip]: https://pip.pypa.io/en/stable/installation
[yt-dlp/FFmpeg]: https://github.com/yt-dlp/FFmpeg-Builds
[FFmpeg 5.1+]: https://ffmpeg.org
[sanjuuni]: https://github.com/MCJack123/sanjuuni
[Python 3.7+]: https://www.python.org/downloads
[sanic]: https://sanic.dev
[yt-dlp]: https://pypi.org/project/yt-dlp
[ujson]: https://pypi.org/project/ujson
[spotipy]: https://pypi.org/project/spotipy
[doc]: https://youcube.madefor.cc/api
[preview]: .README/preview-server.png
[Python Version: 3.7+]: https://img.shields.io/badge/Python-3.7+-green?style=for-the-badge&logo=Python&logoColor=white
[Python Lint Workflow Status]: https://img.shields.io/github/actions/workflow/status/CC-YouCube/server/pylint.yml?branch=main&label=Python%20Lint&logo=github&style=for-the-badge
[Sanic Builtin values]: https://sanic.dev/en/guide/running/configuration.md#builtin-values
