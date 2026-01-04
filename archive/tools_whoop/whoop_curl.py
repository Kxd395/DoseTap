#!/usr/bin/env python3
"""WHOOP OAuth - uses curl for token exchange to avoid Cloudflare blocking"""
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import subprocess
import json

CLIENT_ID = "edf2495a-adff-4b87-b845-9529051a7b39"
CLIENT_SECRET = "0aca5c56ec53b210260d85ac24cf57ced13dc4b4e77cbf7cf2ca20b7d3a9ed9e"
REDIRECT_URI = "http://127.0.0.1:8888/callback"
TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token"
PROFILE_URL = "https://api.prod.whoop.com/developer/v1/user/profile/basic"

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    
    def do_GET(self):
        query = parse_qs(urlparse(self.path).query)
        if 'code' not in query:
            self.respond("<h1>No code</h1>")
            return
        
        code = query['code'][0]
        print(f"\n>>> Got code: {code[:30]}...")
        
        # Use curl to exchange token (avoids Cloudflare 1010)
        print(">>> Exchanging for token via curl...")
        result = subprocess.run([
            'curl', '-s', '-X', 'POST', TOKEN_URL,
            '-H', 'Content-Type: application/x-www-form-urlencoded',
            '-d', f'grant_type=authorization_code',
            '-d', f'code={code}',
            '-d', f'redirect_uri={REDIRECT_URI}',
            '-d', f'client_id={CLIENT_ID}',
            '-d', f'client_secret={CLIENT_SECRET}'
        ], capture_output=True, text=True)
        
        print(f">>> curl output: {result.stdout[:200]}...")
        
        try:
            token_data = json.loads(result.stdout)
            
            if 'error' in token_data:
                self.respond(f"<h1>Token Error</h1><pre>{json.dumps(token_data, indent=2)}</pre>")
                print(f">>> Error: {token_data}")
                return
            
            access_token = token_data.get('access_token', '')
            refresh_token = token_data.get('refresh_token', '')
            expires = token_data.get('expires_in', 0)
            
            print(f">>> SUCCESS!")
            print(f"    Access: {access_token[:50]}...")
            print(f"    Refresh: {refresh_token[:50]}..." if refresh_token else "    No refresh token")
            print(f"    Expires: {expires}s")
            
            # Get profile via curl
            print(">>> Fetching profile...")
            profile_result = subprocess.run([
                'curl', '-s', PROFILE_URL,
                '-H', f'Authorization: Bearer {access_token}'
            ], capture_output=True, text=True)
            
            profile = json.loads(profile_result.stdout)
            print(f">>> Profile: {profile}")
            
            html = f"""<html><body style="font-family:system-ui;padding:40px;max-width:600px;margin:auto;">
            <h1 style="color:green">✅ WHOOP Connected!</h1>
            <h2>Your Profile:</h2>
            <pre style="background:#f0f0f0;padding:15px;border-radius:8px">{json.dumps(profile, indent=2)}</pre>
            <h2>Tokens:</h2>
            <p><b>Access Token:</b> <code>{access_token[:40]}...</code></p>
            <p><b>Expires:</b> {expires} seconds</p>
            <p style="color:#666">Full tokens printed to terminal.</p>
            </body></html>"""
            self.respond(html)
            
            # Print full tokens
            print("\n" + "="*60)
            print("TOKENS (copy these):")
            print("="*60)
            print(f"ACCESS_TOKEN={access_token}")
            print(f"REFRESH_TOKEN={refresh_token}")
            print("="*60)
            
        except Exception as e:
            self.respond(f"<h1>Error</h1><pre>{e}\n{result.stdout}\n{result.stderr}</pre>")
            print(f">>> Exception: {e}")
    
    def respond(self, html):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(html.encode())

if __name__ == '__main__':
    print("="*50)
    print("WHOOP OAuth (port 8888, using curl)")
    print("="*50)
    print("Waiting for callback...")
    HTTPServer(('127.0.0.1', 8888), Handler).handle_request()
    print("\nDone!")
