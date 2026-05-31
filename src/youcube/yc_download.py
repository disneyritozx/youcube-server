#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Download Functionality of YC
"""

# Built-in modules
import base64
import atexit
from asyncio import run_coroutine_threadsafe
from os import getenv, listdir, unlink
from os.path import abspath, dirname, join
from shutil import rmtree
from tempfile import NamedTemporaryFile, mkdtemp
from threading import Thread

# Local modules
from yc_colours import RESET, Foreground
from yc_logging import NO_COLOR, YTDLPLogger, logger
from yc_magic import run_with_live_output
from yc_spotify import SpotifyURLProcessor
from yc_utils import (
    cap_width_and_height,
    create_data_folder_if_not_present,
    get_audio_name,
    get_video_name,
    get_video_rendering_path,
    is_audio_already_downloaded,
    is_video_already_downloaded,
    remove_ansi_escape_codes,
    remove_whitespace,
    SANJUUNI_FPS,
)

# optional pip modules
try:
    from orjson import dumps
except ModuleNotFoundError:
    from json import dumps

# pip modules
from sanic import Websocket
from yt_dlp import YoutubeDL

# pylint settings
# pylint: disable=pointless-string-statement
# pylint: disable=fixme
# pylint: disable=too-many-locals
# pylint: disable=too-many-arguments
# pylint: disable=too-many-branches

DATA_FOLDER = join(dirname(abspath(__file__)), "data")
FFMPEG_PATH = getenv("FFMPEG_PATH", "ffmpeg")
SANJUUNI_PATH = getenv("SANJUUNI_PATH", "sanjuuni")
DISABLE_OPENCL = bool(getenv("DISABLE_OPENCL"))

VIDEO_FORMAT = (
    "worst[ext=mp4][vcodec!=none][acodec!=none]/"
    "worst[vcodec!=none][acodec!=none]/"
    "worstvideo[ext=mp4]+worstaudio[ext=m4a]/"
    "worstvideo+worstaudio"
)
AUDIO_FORMAT = "worstaudio[acodec!=none]/worst[acodec!=none]"

# Write YouTube cookies from env var to a temp file for yt-dlp
_cookies_file = None
_cookies_b64 = getenv("YT_COOKIES_B64")
if _cookies_b64:
    try:
        _tmp = NamedTemporaryFile(mode="wb", suffix=".txt", delete=False, prefix="yc_cookies_")
        _tmp.write(base64.b64decode(_cookies_b64))
        _tmp.close()
        _cookies_file = _tmp.name
        atexit.register(unlink, _cookies_file)
    except Exception as _e:
        logger.warning("Failed to load YT_COOKIES_B64: %s", _e)


def download_video(
    temp_dir: str, media_id: str, resp: Websocket, loop, width: int, height: int
):
    """
    Converts the downloaded video to 32vid
    """
    run_coroutine_threadsafe(
        resp.send(
            dumps({"action": "status", "message": "Converting video to 32vid ..."})
        ),
        loop,
    )

    if NO_COLOR:
        prefix = "[Sanjuuni]"
    else:
        prefix = f"{Foreground.BRIGHT_YELLOW}[Sanjuuni]{RESET} "

    def handler(line):
        logger.debug("%s%s", prefix, line)
        run_coroutine_threadsafe(
            resp.send(dumps({"action": "status", "message": line})), loop
        )

    input_path = join(temp_dir, listdir(temp_dir)[0])
    if SANJUUNI_FPS:
        run_coroutine_threadsafe(
            resp.send(
                dumps(
                    {
                        "action": "status",
                        "message": f"Reducing video to {SANJUUNI_FPS} fps ...",
                    }
                )
            ),
            loop,
        )
        filtered_path = join(temp_dir, "youcube_sanjuuni_input.mp4")
        ffmpeg_code = run_with_live_output(
            [
                FFMPEG_PATH,
                "-hide_banner",
                "-loglevel",
                "warning",
                "-y",
                "-i",
                input_path,
                "-an",
                "-vf",
                f"fps={SANJUUNI_FPS}",
                "-c:v",
                "mpeg4",
                "-q:v",
                "5",
                filtered_path,
            ],
            handler,
        )
        if ffmpeg_code == 0:
            input_path = filtered_path
        else:
            logger.warning("FFmpeg video prefilter exited with %s", ffmpeg_code)

    cmd = [
        SANJUUNI_PATH,
        "--width=" + str(width),
        "--height=" + str(height),
        "-i",
        input_path,
        "--raw",
        "-o",
        join(DATA_FOLDER, get_video_name(media_id, width, height)),
    ]
    if DISABLE_OPENCL:
        cmd.append("--disable-opencl")

    returncode = run_with_live_output(cmd, handler)

    if returncode != 0:
        logger.warning("Sanjuuni exited with %s", returncode)
        run_coroutine_threadsafe(
            resp.send(dumps({"action": "error", "message": "Faild to convert video!"})),
            loop,
        )


def download_video_in_background(
    temp_dir: str, media_id: str, resp: Websocket, loop, width: int, height: int
):
    """Starts video conversion without blocking the media response"""
    rendering_path = get_video_rendering_path(media_id, width, height)
    with open(rendering_path, "w", encoding="utf-8"):
        pass

    def worker():
        try:
            download_video(temp_dir, media_id, resp, loop, width, height)
        finally:
            try:
                unlink(rendering_path)
            except FileNotFoundError:
                pass
            rmtree(temp_dir, ignore_errors=True)

    Thread(target=worker, daemon=True).start()


def download_audio(temp_dir: str, media_id: str, resp: Websocket, loop):
    """
    Converts the downloaded audio to dfpwm
    """
    run_coroutine_threadsafe(
        resp.send(
            dumps({"action": "status", "message": "Converting audio to dfpwm ..."})
        ),
        loop,
    )

    if NO_COLOR:
        prefix = "[FFmpeg]"
    else:
        prefix = f"{Foreground.BRIGHT_GREEN}[FFmpeg]{RESET} "

    def handler(line):
        logger.debug("%s%s", prefix, line)
        # TODO: send message to resp

    returncode = run_with_live_output(
        [
            FFMPEG_PATH,
            "-i",
            join(temp_dir, listdir(temp_dir)[0]),
            "-f",
            "dfpwm",
            "-ar",
            "48000",
            "-ac",
            "1",
            join(DATA_FOLDER, get_audio_name(media_id)),
        ],
        handler,
    )

    if returncode != 0:
        logger.warning("FFmpeg exited with %s", returncode)
        run_coroutine_threadsafe(
            resp.send(dumps({"action": "error", "message": "Faild to convert audio!"})),
            loop,
        )


def download(
    url: str,
    resp: Websocket,
    loop,
    width: int,
    height: int,
    spotify_url_processor: SpotifyURLProcessor,
) -> (dict[str, any], list):
    """
    Downloads and converts the media from the give URL
    """

    is_video = width is not None and height is not None

    # cap height and width
    if width and height:
        width, height = cap_width_and_height(width, height)

    def my_hook(info):
        """https://github.com/yt-dlp/yt-dlp#adding-logger-and-progress-hook"""
        if info.get("status") == "downloading":
            run_coroutine_threadsafe(
                resp.send(
                    dumps(
                        {
                            "action": "status",
                            "message": remove_ansi_escape_codes(
                                f"download {remove_whitespace(info.get('_percent_str'))} "
                                f"ETA {info.get('_eta_str')}"
                            ),
                        }
                    )
                ),
                loop,
            )

    # FIXME: Cleanup on Exception
    temp_dir = mkdtemp(prefix="youcube-")
    cleanup_temp_dir = True
    try:
        yt_dl_options = {
            "format": VIDEO_FORMAT if is_video else AUDIO_FORMAT,
            "js_runtimes": {"node": {}},
            "merge_output_format": "mp4",
            "outtmpl": join(temp_dir, "%(id)s.%(ext)s"),
            "default_search": "auto",
            "restrictfilenames": True,
            "extract_flat": "in_playlist",
            "noplaylist": True,
            "progress_hooks": [my_hook],
            "logger": YTDLPLogger(),
        }
        if _cookies_file:
            yt_dl_options["cookiefile"] = _cookies_file

        yt_dl = YoutubeDL(yt_dl_options)

        run_coroutine_threadsafe(
            resp.send(
                dumps(
                    {"action": "status", "message": "Getting resource information ..."}
                )
            ),
            loop,
        )

        playlist_videos = []

        if spotify_url_processor:
            # Spotify FIXME: The first media key is sometimes duplicated
            processed_url = spotify_url_processor.auto(url)
            if processed_url:
                if isinstance(processed_url, list):
                    url = spotify_url_processor.auto(processed_url[0])
                    processed_url.pop(0)
                    playlist_videos = processed_url
                else:
                    url = processed_url

        data = yt_dl.extract_info(url, download=False)

        if data.get("extractor") == "generic":
            data["id"] = "g" + data.get("webpage_url_domain") + data.get("id")

        """
        If the data is a playlist, we need to get the first video and return it,
        also, we need to grep all video in the playlist to provide support.
        """
        if data.get("_type") == "playlist":
            for video in data.get("entries"):
                playlist_videos.append(video.get("id"))

            playlist_videos.pop(0)

            data = data["entries"][0]

        """
        If the video is extract from a playlist,
        the video is extracted flat,
        so we need to get missing information by running the extractor again.
        """
        if data.get("extractor") == "youtube" and (
            data.get("view_count") is None or data.get("like_count") is None
        ):
            data = yt_dl.extract_info(data.get("id"), download=False)

        media_id = data.get("id")

        if data.get("is_live"):
            return {"action": "error", "message": "Livestreams are not supported"}

        create_data_folder_if_not_present()

        audio_downloaded = is_audio_already_downloaded(media_id)
        video_downloaded = is_video_already_downloaded(media_id, width, height)

        if not audio_downloaded or (not video_downloaded and is_video):
            run_coroutine_threadsafe(
                resp.send(
                    dumps({"action": "status", "message": "Downloading resource ..."})
                ),
                loop,
            )

            yt_dl.process_ie_result(data, download=True)

        # TODO: Thread audio & video download

        if not audio_downloaded:
            download_audio(temp_dir, media_id, resp, loop)

        if not video_downloaded and is_video:
            download_video_in_background(temp_dir, media_id, resp, loop, width, height)
            cleanup_temp_dir = False
    finally:
        if cleanup_temp_dir:
            rmtree(temp_dir, ignore_errors=True)

    out = {
        "action": "media",
        "id": media_id,
        # "fulltitle": data.get("fulltitle"),
        "title": data.get("title"),
        "like_count": data.get("like_count"),
        "view_count": data.get("view_count"),
        # "upload_date": data.get("upload_date"),
        # "tags": data.get("tags"),
        # "description": data.get("description"),
        # "categories": data.get("categories"),
        # "channel_name": data.get("channel"),
        # "channel_id": data.get("channel_id")
    }

    # Only return playlist_videos if there are videos in playlist_videos
    if len(playlist_videos) > 0:
        out["playlist_videos"] = playlist_videos

    files = []
    files.append(get_audio_name(media_id))
    if is_video:
        files.append(get_video_name(media_id, width, height))

    return out, files
