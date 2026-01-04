#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs, urlencode
from urllib.request import Request, urlopen
import json

CLIENT_ID = "edf2495a-adff-4b87-b845-9529051a7b39"
CLIENT_SECRET = "0aca5c56ec53b210260d85ac24cf57ced13dc4b4e77cbf7cf2ca20b7d3a9ed9e"
REDIRECT_URI = "http://127.0.0.1:9090/callback"
TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token"
PROFILE_URL = "https://api.prod.whoop.com/developer/v1/user/profile/basic"

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        query = parse_qs(urlparse(self.path).query)
        if 'code' not in query:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"<h1>Waiting for code...</h1>")
            return
        
        code = query['code'][0]
        print(f"\nGot code: {code[:30]}...")
        
        # Exchange for token
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
            print(f"SUCCESS! Token: {access_token[:40]}...")
            
            # Get profile
            req2 = Request(PROFILE_URL)
            req2.add_header('Authorization', f'Bearer {access_token}')
            profile = json.loads(urlopen(req2).read())
            print(f"Profile: {profile}")
            
            html = f"<h1>SUCCESS!</h1><pre>{json.dumps(profile, indent=2)}</pre>"
        except Exception as e:
            html = f"<h1>Error</h1><pre>{e}</pre>"
            print(f"Error: {e}")
        
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(html.encode())

print("Server on http://127.0.0.1:9090")
HTTPServer(('127.0.0.1', 9090), Handler).handle_request()
print("Done!")
