#!/usr/bin/env python3
"""
Statistics fetcher for YouTube Stats for Creators plugin.
Fetches public channel statistics via YouTube Data API v3 and private
watch time metrics via YouTube Analytics API.
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request
import datetime
from concurrent.futures import ThreadPoolExecutor

CONFIG_DIR = os.path.expanduser("~/.config/omarchy/youtube-stats")
CLIENT_SECRET_FILE = os.path.join(CONFIG_DIR, "client_secret.json")
TOKEN_FILE = os.path.join(CONFIG_DIR, "token.json")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")
STATS_FILE = os.path.join(CONFIG_DIR, "stats.json")
AVATAR_FILE = os.path.join(CONFIG_DIR, "avatar.png")
THUMB_FILE = os.path.join(CONFIG_DIR, "thumbnail.jpg")

def load_json(path):
    if os.path.exists(path):
        try:
            with open(path, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

def get_access_token():
    if not os.path.exists(CLIENT_SECRET_FILE):
        return None, "needs_client_secret"

    tokens = load_json(TOKEN_FILE)
    if not tokens or "refresh_token" not in tokens:
        return None, "auth_required"

    now = time.time()
    if "access_token" in tokens and tokens.get("expires_at", 0) > now + 60:
        return tokens["access_token"], None

    client_id = tokens.get("client_id")
    client_secret = tokens.get("client_secret")
    refresh_token = tokens.get("refresh_token")
    token_uri = tokens.get("token_uri", "https://oauth2.googleapis.com/token")

    payload = {
        "client_id": client_id,
        "client_secret": client_secret,
        "refresh_token": refresh_token,
        "grant_type": "refresh_token"
    }

    req = urllib.request.Request(
        token_uri,
        data=urllib.parse.urlencode(payload).encode("utf-8"),
        headers={"Content-Type": "application/x-www-form-urlencoded"}
    )

    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            tokens["access_token"] = data["access_token"]
            tokens["expires_at"] = now + data.get("expires_in", 3600)
            save_json(TOKEN_FILE, tokens)
            return tokens["access_token"], None
    except Exception as e:
        return None, f"auth_error: {e}"

def fetch_data():
    os.makedirs(CONFIG_DIR, exist_ok=True)
    cfg = load_json(CONFIG_FILE)
    period = cfg.get("period", "28d")
    selected_metric = cfg.get("metric", "subscribers")
    lang = cfg.get("lang", "en")

    if len(sys.argv) > 2 and sys.argv[1] == "--set-metric":
        selected_metric = sys.argv[2]
        cfg["metric"] = selected_metric
        save_json(CONFIG_FILE, cfg)
    elif len(sys.argv) > 2 and sys.argv[1] == "--set-period":
        period = sys.argv[2]
        cfg["period"] = period
        save_json(CONFIG_FILE, cfg)
    elif len(sys.argv) > 2 and sys.argv[1] == "--set-lang":
        lang = sys.argv[2]
        cfg["lang"] = lang
        save_json(CONFIG_FILE, cfg)

    access_token, status_err = get_access_token()
    if status_err:
        cached = load_json(STATS_FILE)
        cached_title = cached.get("channel_title", "YouTube")
        cached_url = cached.get("custom_url", "")
        error_stats = {
            "status": status_err,
            "channel_title": cached_title,
            "custom_url": cached_url,
            "subscribers": cached.get("subscribers", 0),
            "total_views": cached.get("total_views", 0),
            "total_videos": cached.get("total_videos", 0),
            "watch_time_hours": cached.get("watch_time_hours", 0.0),
            "period_views": cached.get("period_views", 0),
            "period": period,
            "selected_metric": selected_metric,
            "lang": lang,
            "last_updated": int(time.time()),
            "avatar_path": AVATAR_FILE if os.path.exists(AVATAR_FILE) else "",
            "latest_video": cached.get("latest_video")
        }
        print(json.dumps(error_stats))
        return

    headers = {"Authorization": f"Bearer {access_token}"}

    # 1. Dane kanału
    channel_url = "https://www.googleapis.com/youtube/v3/channels?part=snippet,statistics,contentDetails&mine=true"
    req_ch = urllib.request.Request(channel_url, headers=headers)
    try:
        with urllib.request.urlopen(req_ch) as resp:
            ch_data = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        # Przy błędzie sieci zwróć ostatni cache jeśli istnieje
        cached = load_json(STATS_FILE)
        if cached:
            print(json.dumps(cached))
            return
        print(json.dumps({"status": "network_error", "error": str(e)}))
        return

    items = ch_data.get("items", [])
    if not items:
        print(json.dumps({"status": "no_channel", "error": "No YouTube channels found on this account"}))
        return

    ch = items[0]
    snippet = ch.get("snippet", {})
    stats = ch.get("statistics", {})

    title = snippet.get("title", "YouTube")
    custom_url = snippet.get("customUrl", "")
    avatar_url = snippet.get("thumbnails", {}).get("medium", {}).get("url", "")

    subscribers = int(stats.get("subscriberCount", 0))
    total_views = int(stats.get("viewCount", 0))
    video_count = int(stats.get("videoCount", 0))

    # Pobierz awatar
    if avatar_url and (not os.path.exists(AVATAR_FILE) or time.time() - os.path.getmtime(AVATAR_FILE) > 86400):
        try:
            with urllib.request.urlopen(avatar_url) as resp:
                with open(AVATAR_FILE, "wb") as f:
                    f.write(resp.read())
        except Exception:
            pass

    # 2. Pobierz ostatni opublikowany film oraz ranking Studio (np. 3 z 6 lub 1 z 10)
    uploads_id = ch.get("contentDetails", {}).get("relatedPlaylists", {}).get("uploads")
    latest_video = None
    if uploads_id:
        try:
            pl_url = f"https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&playlistId={uploads_id}&maxResults=50"
            req_pl = urllib.request.Request(pl_url, headers=headers)
            with urllib.request.urlopen(req_pl) as resp:
                pl_data = json.loads(resp.read().decode("utf-8"))
            pl_items = pl_data.get("items", [])
            all_vids = [it.get("snippet", {}).get("resourceId", {}).get("videoId") for it in pl_items if it.get("snippet", {}).get("resourceId", {}).get("videoId")]

            if all_vids:
                # Pobierz szczegóły filmów (status, snippet, statistics)
                chunks = [all_vids[i:i + 50] for i in range(0, len(all_vids), 50)]
                public_videos = []
                for chunk in chunks:
                    v_url = f"https://www.googleapis.com/youtube/v3/videos?part=snippet,statistics,status,contentDetails&id={','.join(chunk)}"
                    req_v = urllib.request.Request(v_url, headers=headers)
                    with urllib.request.urlopen(req_v) as resp:
                        v_obj = json.loads(resp.read().decode("utf-8"))
                        for item in v_obj.get("items", []):
                            st = item.get("status", {})
                            sn = item.get("snippet", {})
                            if st.get("privacyStatus") == "public" and sn.get("liveBroadcastContent") != "upcoming":
                                public_videos.append(item)

                if public_videos:
                    # YouTube Studio porównuje ostatni film z maksymalnie 10 ostatnimi publicznymi filmami
                    target_videos = public_videos[:10]
                    latest_item = target_videos[0]
                    v_id = latest_item.get("id")
                    v_snippet = latest_item.get("snippet", {})
                    v_stats = latest_item.get("statistics", {})
                    v_title = v_snippet.get("title", "")
                    v_pub = v_snippet.get("publishedAt", "")
                    v_thumbs = v_snippet.get("thumbnails", {})
                    v_thumb_url = v_thumbs.get("medium", {}).get("url") or v_thumbs.get("high", {}).get("url") or v_thumbs.get("default", {}).get("url", "")
                    v_views = int(v_stats.get("viewCount", 0))
                    v_likes = int(v_stats.get("likeCount", 0))
                    v_comments = int(v_stats.get("commentCount", 0))

                    # Pobierz miniaturę
                    if v_thumb_url and (not os.path.exists(THUMB_FILE) or time.time() - os.path.getmtime(THUMB_FILE) > 86400):
                        try:
                            with urllib.request.urlopen(v_thumb_url) as resp:
                                with open(THUMB_FILE, "wb") as f:
                                    f.write(resp.read())
                        except Exception:
                            pass

                    # Oblicz ranking Studio (porównanie wyświetleń w tym samym czasie po publikacji)
                    rank_total = len(target_videos)
                    rank = 1
                    try:
                        latest_pub_dt = datetime.datetime.fromisoformat(v_pub.replace("Z", "+00:00"))
                        now_dt = datetime.datetime.now(datetime.timezone.utc)
                        delta_days = max(1, (now_dt.date() - latest_pub_dt.date()).days)

                        def get_video_normalized_views(item):
                            vid = item.get("id")
                            if vid == v_id:
                                return (vid, v_views)
                            pub_dt = datetime.datetime.fromisoformat(item.get("snippet", {}).get("publishedAt", "").replace("Z", "+00:00"))
                            start_date = pub_dt.date()
                            end_date = start_date + datetime.timedelta(days=delta_days)
                            today_date = now_dt.date()
                            if end_date > today_date:
                                end_date = today_date
                            url = f"https://youtubeanalytics.googleapis.com/v2/reports?ids=channel==MINE&startDate={start_date.isoformat()}&endDate={end_date.isoformat()}&metrics=views&filters=video=={vid}"
                            try:
                                with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=5) as resp:
                                    d = json.loads(resp.read().decode("utf-8"))
                                rows = d.get("rows", [])
                                views = rows[0][0] if rows else 0
                                return (vid, views)
                            except Exception:
                                return (vid, int(item.get("statistics", {}).get("viewCount", 0)))

                        with ThreadPoolExecutor(max_workers=min(10, len(target_videos))) as executor:
                            view_results = list(executor.map(get_video_normalized_views, target_videos))

                        v_views_map = dict(view_results)
                        ranked_ids = sorted(v_views_map.keys(), key=lambda x: v_views_map[x], reverse=True)
                        if v_id in ranked_ids:
                            rank = ranked_ids.index(v_id) + 1
                    except Exception as e:
                        print(f"Ranking calculation warning: {e}", file=sys.stderr)

                    latest_video = {
                        "id": v_id,
                        "title": v_title,
                        "published_at": v_pub,
                        "thumbnail_path": THUMB_FILE if os.path.exists(THUMB_FILE) else v_thumb_url,
                        "views": v_views,
                        "likes": v_likes,
                        "comments": v_comments,
                        "rank": rank,
                        "rank_total": rank_total
                    }
        except Exception as e:
            print(f"Latest video fetch warning: {e}", file=sys.stderr)

    # 3. Zakres dat dla Analytics
    period_days = 28
    if period == "7d":
        period_days = 7
    elif period == "28d":
        period_days = 28
    elif period == "90d":
        period_days = 90
    elif period == "365d":
        period_days = 365

    today = datetime.date.today()
    end_date = today - datetime.timedelta(days=1)
    start_date = end_date - datetime.timedelta(days=period_days)

    analytics_url = (
        f"https://youtubeanalytics.googleapis.com/v2/reports?"
        f"ids=channel==MINE&startDate={start_date.isoformat()}&endDate={end_date.isoformat()}&"
        f"metrics=estimatedMinutesWatched,views,subscribersGained,subscribersLost"
    )

    watch_time_minutes = 0
    period_views = 0

    req_an = urllib.request.Request(analytics_url, headers=headers)
    try:
        with urllib.request.urlopen(req_an) as resp:
            an_data = json.loads(resp.read().decode("utf-8"))
            rows = an_data.get("rows", [])
            if rows:
                row = rows[0]
                watch_time_minutes = int(row[0] or 0)
                period_views = int(row[1] or 0)
    except Exception as e:
        print(f"Analytics warning: {e}", file=sys.stderr)

    watch_time_hours = round(watch_time_minutes / 60.0, 1)

    result = {
        "status": "ok",
        "channel_title": title,
        "custom_url": custom_url,
        "avatar_path": AVATAR_FILE if os.path.exists(AVATAR_FILE) else avatar_url,
        "subscribers": subscribers,
        "total_views": total_views,
        "total_videos": video_count,
        "watch_time_minutes": watch_time_minutes,
        "watch_time_hours": watch_time_hours,
        "period_views": period_views,
        "period": period,
        "selected_metric": selected_metric,
        "lang": lang,
        "latest_video": latest_video,
        "last_updated": int(time.time())
    }

    save_json(STATS_FILE, result)
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    fetch_data()
