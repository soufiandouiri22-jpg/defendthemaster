#!/usr/bin/env python3
"""Reads the published game's log (src/server/TraceService.luau) and prints it as one timeline: every server's and
every player's marks, errors and warnings, in local time, oldest first.

    python3 Tools/trace.py                    the last 30 minutes
    python3 Tools/trace.py --since 2h         the last 2 hours (also 45m, 1d)
    python3 Tools/trace.py --errors           only errors, warnings and failed teleports
    python3 Tools/trace.py --kind loading     only marks whose kind starts with this (loading, versus, click, ...)
    python3 Tools/trace.py --player Soufian   only this player (name or user id) and the servers' own marks
    python3 Tools/trace.py --stats            with the clients' frame rate, ping and memory every 30 s
    python3 Tools/trace.py --raw              each entry as a line of JSON
    python3 Tools/trace.py --prune 7          deletes what is older than 7 days

Reads the DataStore through Open Cloud with the API key in the macOS Keychain (service DefendTheMaster.RobloxOpenCloud,
as Tools/hero_sounds.py has it); the key needs the Data Stores permissions list, read and delete for the experience.
The key is never printed or written anywhere.
"""

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

from hero_sounds import api_key

UNIVERSE = 10773141270
STORE = "Trace_v1"
BASE = f"https://apis.roblox.com/datastores/v1/universes/{UNIVERSE}/standard-datastores/datastore/entries"
# A batch is written up to this long after its first mark (TraceService's FLUSH, and some room).
FLUSH = timedelta(seconds=90)
ERRORS = ("error", "warning", "teleport.failed", "trace.dropped")
# How often a call refused for too many requests is tried again.
RETRIES = 8


def call(url, key, method="GET", attempt=0):
    request = urllib.request.Request(url, method=method)
    request.add_header("x-api-key", key)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            body = response.read()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        text = error.read().decode(errors="replace")[:300]
        # Open Cloud's rate limit: wait longer each time and try again.
        if error.code == 429 and attempt < RETRIES:
            time.sleep(2 * (attempt + 1))
            return call(url, key, method, attempt + 1)
        if error.code == 404 and "DatastoreNotFound" in text:
            sys.exit("No log yet: the published game has not written one (is the version with TraceService published?).")
        if error.code in (401, 403):
            sys.exit(
                f"Open Cloud refused ({error.code}: {text}). Give the API key the Data Stores permissions "
                "(list, read and delete entries) for this experience on create.roblox.com > Open Cloud > API Keys."
            )
        sys.exit(f"{url.split('?')[0]}: HTTP {error.code} {text}")


def keys(key, prefix):
    cursor = None
    while True:
        query = {"datastoreName": STORE, "prefix": prefix, "limit": 100}
        if cursor:
            query["cursor"] = cursor
        page = call(f"{BASE}?{urllib.parse.urlencode(query)}", key)
        for item in page.get("keys", []):
            yield item["key"]
        cursor = page.get("nextPageCursor")
        if not cursor:
            return


def written(name):
    match = re.match(r"(\d{8}-\d{6})_", name)
    return datetime.strptime(match.group(1), "%Y%m%d-%H%M%S").replace(tzinfo=timezone.utc) if match else None


def in_window(key, since, until=None):
    names = []
    day = since.date()
    while day <= (until or datetime.now(timezone.utc)).date():
        names += [n for n in keys(key, day.strftime("%Y%m%d")) if (w := written(n)) and w >= since]
        day += timedelta(days=1)
    if until:
        names = [n for n in names if written(n) < until]
    return names


def fetch(key, name):
    query = urllib.parse.urlencode({"datastoreName": STORE, "entryKey": name})
    return call(f"{BASE}/entry?{query}", key)


def duration(text):
    match = re.fullmatch(r"(\d+)([mhd])", text)
    if not match:
        raise argparse.ArgumentTypeError("like 45m, 2h or 1d")
    amount, unit = int(match.group(1)), match.group(2)
    return timedelta(minutes=amount) if unit == "m" else timedelta(hours=amount) if unit == "h" else timedelta(days=amount)


def show(value):
    if isinstance(value, float):
        return f"{value:g}"
    text = str(value)
    return f'"{text}"' if " " in text else text


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--since", type=duration, default=timedelta(minutes=30))
    parser.add_argument("--errors", action="store_true")
    parser.add_argument("--kind")
    parser.add_argument("--player")
    parser.add_argument("--stats", action="store_true")
    parser.add_argument("--raw", action="store_true")
    parser.add_argument("--prune", type=int, metavar="DAYS")
    args = parser.parse_args()
    key = api_key()

    if args.prune is not None:
        before = datetime.now(timezone.utc) - timedelta(days=args.prune)
        old = in_window(key, before - timedelta(days=60), before)
        for name in old:
            query = urllib.parse.urlencode({"datastoreName": STORE, "entryKey": name})
            call(f"{BASE}/entry?{query}", key, "DELETE")
        print(f"{len(old)} batches older than {args.prune} days deleted.")
        return

    since = datetime.now(timezone.utc) - args.since
    names = in_window(key, since - FLUSH)
    with ThreadPoolExecutor(4) as pool:
        batches = list(pool.map(lambda name: (name, fetch(key, name)), names))

    players, rows = {}, []
    for name, batch in batches:
        server = name.split("_")[1]
        role = batch.get("role") or "?"
        for entry in batch.get("entries", []):
            data = entry.get("d") or {}
            if entry.get("k") == "player.join" and entry.get("p"):
                players[entry["p"]] = data.get("name", str(entry["p"]))
            rows.append((entry.get("t", 0), server, role, batch.get("place"), entry))
    rows.sort(key=lambda row: row[0])

    wanted = None
    if args.player:
        wanted = {p for p, n in players.items() if n.lower() == args.player.lower() or str(p) == args.player}
    shown = 0
    for time, server, role, place, entry in rows:
        if time < since.timestamp():
            continue
        kind = entry.get("k", "")
        if args.errors and not kind.startswith(ERRORS):
            continue
        if args.kind and not kind.startswith(args.kind):
            continue
        if kind == "client.stats" and not args.stats and not args.kind:
            continue
        who = entry.get("p")
        if wanted is not None and who is not None and who not in wanted:
            continue
        shown += 1
        if args.raw:
            print(json.dumps({"server": server, "role": role, "place": place, **entry}))
            continue
        stamp = datetime.fromtimestamp(time).strftime("%H:%M:%S.%f")[:-3]
        name = players.get(who, str(who)) if who else "server"
        data = " ".join(f"{k}={show(v)}" for k, v in (entry.get("d") or {}).items())
        print(f"{stamp}  {role[:5]:<5} {server}  {name[:14]:<14}  {kind:<22} {data}")
    if not args.raw:
        print(f"-- {shown} entries from {len(batches)} batches since {since.astimezone():%H:%M}", file=sys.stderr)


if __name__ == "__main__":
    main()
