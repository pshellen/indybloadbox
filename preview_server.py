#!/usr/bin/env python3
"""Local preview server for the BLOAD Indy showings grid."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
from urllib.parse import parse_qs, urlparse
import datetime
import json
import os

try:
    import pytz
except ImportError:
    pytz = None

PORT = 8765
ROOT = os.path.dirname(os.path.abspath(__file__))
GRAPHQL = "https://api-us.indy.systems/graphql"
UA = "bload-preview/1.0"
DEFAULT_TZ = "US/Eastern"


def badge_is_3d(badge):
    title = (badge.get("title") or badge.get("displayName") or "").strip().lower()
    return title == "3d" or title.startswith("3d ") or " 3d" in title


def showtime_parts(dt):
    hour, minute = dt.hour, dt.minute
    suffix = "am" if hour < 12 else "pm"
    display_hour = (hour - 1) % 12 + 1
    return {
        "hour": hour,
        "minute": minute,
        "offset": hour * 60 + minute,
        "string": "%d:%02d%s" % (display_hour, minute, suffix),
    }


def localize(dt, tz_name):
    if pytz is None:
        return dt.replace(tzinfo=None)
    dt = dt.replace(tzinfo=pytz.utc)
    return dt.astimezone(pytz.timezone(tz_name)).replace(tzinfo=None)


def parse_indy_showings(screen, options):
    tz_name = options.get("timezone", DEFAULT_TZ)
    hide_past = bool(options.get("hide_past", False))
    movies = {}

    for show in screen.get("todaysShowings", []):
        if hide_past and show.get("past"):
            continue

        movie = show["movie"]
        name = movie["name"]
        if name not in movies:
            badges = []
            is_3d = False
            for badge in show.get("showingBadges") or []:
                label = (badge.get("displayName") or badge.get("title") or "").strip()
                if label:
                    badges.append(label)
                if badge_is_3d(badge):
                    is_3d = True
            movies[name] = {
                "name": name,
                "image": "".join(ch for ch in name.lower() if ch.isalnum()),
                "mpaa": (movie.get("rating") or "").strip(),
                "threed": is_3d,
                "badges": badges,
                "shows": [],
            }

        dt = datetime.datetime.strptime(show["time"], "%Y-%m-%dT%H:%M:%SZ")
        dt = localize(dt, tz_name)
        parts = showtime_parts(dt)
        parts["past"] = bool(show.get("past"))
        parts["seats"] = 100
        parts["sold"] = 0
        movies[name]["shows"].append(parts)

    sorted_movies = sorted(movies.values(), key=lambda m: m["name"].lower())
    for movie in sorted_movies:
        movie["shows"].sort(key=lambda s: s["offset"])

    return {
        "source": "indy",
        "screen": screen.get("name") or "",
        "movies": sorted_movies,
        "movies_per_page": int(options.get("movies_per_page", 4)),
        "page_interval": max(1, int(options.get("page_interval", 5))),
        "hide_poster": bool(options.get("hide_poster", True)),
        "display_badges": bool(options.get("display_badges", True)),
        "show_logo": bool(options.get("show_logo", False)),
    }


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path.startswith("/api/showings/"):
            screen_id = parsed.path.split("/api/showings/", 1)[1].split("/", 1)[0]
            qs = parse_qs(parsed.query)
            options = {
                "timezone": qs.get("timezone", [DEFAULT_TZ])[0],
                "hide_past": qs.get("hide_past", ["0"])[0] in ("1", "true", "yes"),
                "movies_per_page": int(qs.get("movies_per_page", ["4"])[0]),
                "page_interval": int(qs.get("page_interval", ["5"])[0]),
                "hide_poster": qs.get("hide_poster", ["1"])[0] in ("1", "true", "yes"),
                "display_badges": qs.get("display_badges", ["1"])[0] in ("1", "true", "yes"),
                "show_logo": qs.get("show_logo", ["0"])[0] in ("1", "true", "yes"),
            }
            self.proxy_showings(screen_id, options)
            return
        return super().do_GET()

    def proxy_showings(self, screen_id, options):
        query = (
            '{ screen(id: "%s") { name todaysShowings { time current past '
            "showingBadges { id title displayName } "
            "movie { name rating ratingReason posterImage } } } }"
        ) % screen_id
        body = json.dumps({"query": query}).encode("utf-8")
        req = Request(
            GRAPHQL,
            data=body,
            headers={
                "Content-Type": "application/json",
                "Accept": "application/graphql-response+json",
                "User-Agent": UA,
            },
            method="POST",
        )
        try:
            with urlopen(req, timeout=10) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
            screen = payload["data"]["screen"]
            data = parse_indy_showings(screen, options)
            encoded = json.dumps(data).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(encoded)
        except (URLError, HTTPError, KeyError, ValueError) as err:
            payload = json.dumps({"error": {"message": str(err)}}).encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(payload)

    def log_message(self, fmt, *args):
        print("[%s] %s" % (self.log_date_time_string(), fmt % args))


if __name__ == "__main__":
    os.chdir(ROOT)
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print("Preview: http://127.0.0.1:%d/preview.html" % PORT)
    server.serve_forever()
