#!/usr/bin/env python3
"""
OAuth2 authentication script for YouTube Stats for Creators plugin.
Safe and portable: reads credentials from ~/.config/omarchy/youtube-stats/client_secret.json
and saves tokens to ~/.config/omarchy/youtube-stats/token.json with 0600 permissions.
"""
import json
import os
import sys
import urllib.parse
import urllib.request
import webbrowser
from http.server import HTTPServer, BaseHTTPRequestHandler

CONFIG_DIR = os.path.expanduser("~/.config/omarchy/youtube-stats")
CLIENT_SECRET_FILE = os.path.join(CONFIG_DIR, "client_secret.json")
TOKEN_FILE = os.path.join(CONFIG_DIR, "token.json")

SCOPES = [
    "https://www.googleapis.com/auth/youtube.readonly",
    "https://www.googleapis.com/auth/yt-analytics.readonly"
]

PORT = 8090
REDIRECT_URI = f"http://localhost:{PORT}"

auth_code = None

class OAuthHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        global auth_code
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)

        if "code" in params:
            auth_code = params["code"][0]
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            html = """
            <!DOCTYPE html>
            <html>
            <head><meta charset="utf-8"><title>Authorization Successful</title></head>
            <body style="font-family: sans-serif; text-align: center; padding-top: 50px; background: #181825; color: #cdd6f4;">
                <h1 style="color: #a6e3a1;">Authorization Successful!</h1>
                <p>Your YouTube account has been successfully connected to the Omarchy widget.</p>
                <p>You can safely close this browser tab.</p>
            </body>
            </html>
            """
            self.wfile.write(html.encode("utf-8"))
        else:
            self.send_response(400)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            err = params.get("error", ["Unknown error"])[0]
            self.wfile.write(f"<h1>Authorization Error: {err}</h1>".encode("utf-8"))

def run_auth():
    os.makedirs(CONFIG_DIR, exist_ok=True)

    if not os.path.exists(CLIENT_SECRET_FILE):
        print(f"\n[ERROR] client_secret.json file not found!")
        print(f"Download OAuth credentials (Desktop App) from Google Cloud Console")
        print(f"and place them in: {CLIENT_SECRET_FILE}\n")
        input("Press Enter to exit...")
        sys.exit(1)

    try:
        with open(CLIENT_SECRET_FILE, "r") as f:
            data = json.load(f)
    except Exception as e:
        print(f"[ERROR] Failed to read client_secret.json: {e}")
        input("Press Enter to exit...")
        sys.exit(1)

    cfg = data.get("installed") or data.get("web")
    if not cfg:
        print("[ERROR] Invalid client_secret.json format (missing 'installed' or 'web' section)")
        input("Press Enter to exit...")
        sys.exit(1)

    client_id = cfg["client_id"]
    client_secret = cfg["client_secret"]
    auth_uri = cfg.get("auth_uri", "https://accounts.google.com/o/oauth2/auth")
    token_uri = cfg.get("token_uri", "https://oauth2.googleapis.com/token")

    auth_params = {
        "client_id": client_id,
        "redirect_uri": REDIRECT_URI,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        "access_type": "offline",
        "prompt": "consent"
    }

    url = f"{auth_uri}?{urllib.parse.urlencode(auth_params)}"

    try:
        server = HTTPServer(("localhost", PORT), OAuthHandler)
    except OSError as e:
        print(f"[ERROR] Port {PORT} is already in use: {e}")
        input("Press Enter to exit...")
        sys.exit(1)

    print("\n" + "=" * 60)
    print("Opening browser to authorize your Google account...")
    print("If your browser doesn't open automatically, copy this URL:")
    print(url)
    print("=" * 60 + "\n")

    try:
        webbrowser.open(url)
    except Exception:
        pass

    while not auth_code:
        server.handle_request()

    if not auth_code:
        print("[ERROR] Authorization code was not received.")
        input("Press Enter to exit...")
        sys.exit(1)

    token_payload = {
        "code": auth_code,
        "client_id": client_id,
        "client_secret": client_secret,
        "redirect_uri": REDIRECT_URI,
        "grant_type": "authorization_code"
    }

    req = urllib.request.Request(
        token_uri,
        data=urllib.parse.urlencode(token_payload).encode("utf-8"),
        headers={"Content-Type": "application/x-www-form-urlencoded"}
    )

    try:
        with urllib.request.urlopen(req) as resp:
            tokens = json.loads(resp.read().decode("utf-8"))
            tokens["client_id"] = client_id
            tokens["client_secret"] = client_secret
            tokens["token_uri"] = token_uri

            with open(TOKEN_FILE, "w") as f:
                json.dump(tokens, f, indent=2)
            os.chmod(TOKEN_FILE, 0o600)
            print("\n Success! YouTube account connected successfully.")
            print(f"Tokens saved securely to {TOKEN_FILE}")
            print("You can close this window.")
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode("utf-8")
        print(f"[ERROR] Authorization code exchange failed: {err_msg}")
        input("Press Enter to exit...")
        sys.exit(1)

if __name__ == "__main__":
    run_auth()
