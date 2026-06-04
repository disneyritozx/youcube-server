import sys
import unittest
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "src" / "youcube"))

import yc_image


class FetchTests(unittest.TestCase):
    @patch("yc_image.validate_url")
    @patch("yc_image._run")
    def test_resolves_relative_redirect(self, run_mock, validate_mock):
        run_mock.side_effect = [
            CompletedProcess([], 0, b"", b"HTTP/1.1 302 Found\r\nLocation: /image.png\r\n"),
            CompletedProcess([], 0, b"image data", b"HTTP/1.1 200 OK\r\n"),
        ]

        result = yc_image._fetch("https://example.com/start")

        self.assertEqual(result, b"image data")
        self.assertEqual(
            [call.args[0] for call in validate_mock.call_args_list],
            ["https://example.com/start", "https://example.com/image.png"],
        )

    @patch("yc_image.validate_url")
    @patch("yc_image._run")
    def test_reports_upstream_http_status(self, run_mock, _validate_mock):
        run_mock.return_value = CompletedProcess(
            [], 0, b"expired", b"HTTP/1.1 403 Forbidden\r\n"
        )

        with self.assertRaisesRegex(
            yc_image.ImageFetchError, "upstream image returned HTTP 403"
        ):
            yc_image._fetch("https://example.com/expired.png")

    @patch("yc_image.validate_url")
    @patch("yc_image._run")
    def test_uses_last_status_from_proxy_headers(self, run_mock, _validate_mock):
        run_mock.return_value = CompletedProcess(
            [],
            0,
            b"image data",
            b"HTTP/1.1 200 Connection established\r\nHTTP/2 200\r\n",
        )

        self.assertEqual(yc_image._fetch("https://example.com/image.png"), b"image data")


if __name__ == "__main__":
    unittest.main()
