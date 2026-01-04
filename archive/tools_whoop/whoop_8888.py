#!/usr/bin/env python3
"""Simple WHOOP OAuth - uses port 9090 to avoid Docker conflict"""
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs, urlencode
from urllib.request import Request, urlopen
import json

CLIENT_ID = "edf2495a-adff-4b87-b845-9529051a7b39"
CLIENT_SECRET = "0aca5c56ec53b210260d85ac24cf57ced13dc4b4e77cbf7cf2ca20b7d3a9ed9e"
REDIRECT_URI = "http://127.0.0.1:8888/callback"
TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token"
PROFILE_URL = "https://api.prod.whoop.com/developer/v1/user/profile/basic"

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        query = parse_qs(urlparse(self.path).query)
        if 'code' not in query:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"<h1>No code received</h1>")
            return
        
        code = query['code'][0]
        print(f"\n>>> Got authorization code: {code[:30]}...")
        
        # Exchange for token
        print(">>> Exchanging for access token...")
        data = urlencode({
            'grant_type': 'authorization_code',
            'code': code,
            'redirect_uri': REDIRECT_URI,
            'client_id': CLIENT_ID,
            'client_secret': CLIENT_SECRET
        }).encode()
        
        try:
            req = Request(TOKEN_URL, data=data)
            req.add_header('Content-Type', 'application/x-www-form-urlencoded')
            resp = urlopen(req, timeout=10)
            token_data = json.loads(resp.read())
            
            access_token = token_data.get('access_token', '')
            refresh_token = token_data.get('refresh_token', 'N/A')
            expires = token_data.get('expires_in', 0)
            
            print(f">>> SUCCESS!")
            print(f"    Access Token: {access_token[:50]}...")
            print(f"    Refresh Token: {refresh_token[:50] if refresh_token != 'N/A' else 'N/A'}...")
            print(f"    Expires: {expires}s")
            
            # Get profile
            print(">>> Fetching profile...")
            req2 = Request(PROFILE_URL)
            req2.add_header('Authorization', f'Bearer {access_token}')
            profile = json.loads(urlopen(req2).read())
            print(f">>> Profile: {profile}")
            
            html = f"""<html><body style="font-family:system-ui;padding:40px;">
            <h1 style="color:green">✅ WHOOP Connected!</h1>
            <h2>Your Profile:</h2>
            <pre style="background:#eee;padding:15px">{json.dumps(profile, indent=2)}</pre>
            <p>Check terminal for tokens.</p>
            </body></html>"""
            
        except Exception as e:
            error_msg = str(e)
            try:
                error_msg = e.read().decode() if hasattr(e, 'read') else str(e)
            except:
                pass
            html = f"<html><body><h1 style='color:red'>Error</h1><pre>{error_msg}</pre></body></html>"
            print(f">>> Error: {error_msg}")
        
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(html.encode())

if __name__ == '__main__':
    print("="*50)
    print("WHOOP OAuth Server (port 8888)")
    print("="*50)
    print("Waiting for callback...")
    HTTPServer(('127.0.0.1', 8888), Handler).handle_request()
    print("\nDone!")
