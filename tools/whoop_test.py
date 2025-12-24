#!/usr/bin/env python3
"""
WHOOP OAuth Token Exchange - Simple & Safe
Based on https://developer.whoop.com/docs/developing/oauth
"""
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs, urlencode
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import json
import sys

# Configuration from WHOOP Developer Dashboard
CLIENT_ID = "edf2495a-adff-4b87-b845-9529051a7b39"
CLIENT_SECRET = "0aca5c56ec53b210260d85ac24cf57ced13dc4b4e77cbf7cf2ca20b7d3a9ed9e"
REDIRECT_URI = "http://127.0.0.1:8080/callback"

# WHOOP API URLs (from docs)
WHOOP_API_HOSTNAME = "https://api.prod.whoop.com"
TOKEN_URL = f"{WHOOP_API_HOSTNAME}/oauth/oauth2/token"
PROFILE_URL = f"{WHOOP_API_HOSTNAME}/developer/v1/user/profile/basic"

class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Suppress HTTP logs
        pass
    
    def do_GET(self):
        query = parse_qs(urlparse(self.path).query)
        
        if 'code' not in query:
            self.respond(400, "<h1>No authorization code received</h1>")
            return
        
        code = query['code'][0]
        print(f"\n[1/3] Authorization code received: {code[:30]}...")
        
        # Exchange code for token
        print("[2/3] Exchanging code for access token...")
        token_result = self.exchange_token(code)
        
        if 'error' in token_result:
            print(f"ERROR: {token_result}")
            self.respond(400, f"<h1>Token Error</h1><pre>{json.dumps(token_result, indent=2)}</pre>")
            return
        
        access_token = token_result.get('access_token', '')
        refresh_token = token_result.get('refresh_token', 'N/A')
        expires_in = token_result.get('expires_in', 0)
        
        print(f"    Access Token: {access_token[:40]}...")
        print(f"    Refresh Token: {refresh_token[:40] if refresh_token != 'N/A' else 'N/A'}...")
        print(f"    Expires In: {expires_in} seconds")
        
        # Test API with profile request
        print("[3/3] Testing API - fetching profile...")
        profile = self.get_profile(access_token)
        print(f"    Profile: {profile}")
        
        # Show success page
        html = f"""<!DOCTYPE html>
<html>
<head><title>WHOOP Connected</title></head>
<body style="font-family: -apple-system, system-ui, sans-serif; max-width: 600px; margin: 50px auto; padding: 20px;">
<h1 style="color: green;">✅ WHOOP Connected!</h1>
<h2>Your Profile</h2>
<pre style="background: #f5f5f5; padding: 15px; border-radius: 8px; overflow: auto;">{json.dumps(profile, indent=2)}</pre>
<h2>Token Info</h2>
<table style="width: 100%; border-collapse: collapse;">
<tr><td style="padding: 8px; border-bottom: 1px solid #ddd;"><strong>Expires In</strong></td><td>{expires_in} seconds</td></tr>
<tr><td style="padding: 8px; border-bottom: 1px solid #ddd;"><strong>Token Type</strong></td><td>Bearer</td></tr>
</table>
<p style="color: #666; margin-top: 30px;">Tokens saved to terminal output. You can close this page.</p>
</body>
</html>"""
        self.respond(200, html)
        
        # Print tokens for copying
        print("\n" + "="*50)
        print("SAVE THESE TOKENS:")
        print("="*50)
        print(f"ACCESS_TOKEN={access_token}")
        print(f"REFRESH_TOKEN={refresh_token}")
        print(f"EXPIRES_IN={expires_in}")
        print("="*50)
    
    def exchange_token(self, code):
        """Exchange authorization code for access token"""
        data = urlencode({
            'grant_type': 'authorization_code',
            'code': code,
            'redirect_uri': REDIRECT_URI,
            'client_id': CLIENT_ID,
            'client_secret': CLIENT_SECRET
        }).encode('utf-8')
        
        req = Request(TOKEN_URL, data=data, method='POST')
        req.add_header('Content-Type', 'application/x-www-form-urlencoded')
        
        try:
            with urlopen(req, timeout=10) as resp:
                return json.loads(resp.read().decode('utf-8'))
        except HTTPError as e:
            return json.loads(e.read().decode('utf-8'))
        except Exception as e:
            return {'error': str(e)}
    
    def get_profile(self, token):
        """Fetch user profile to test the token"""
        req = Request(PROFILE_URL)
        req.add_header('Authorization', f'Bearer {token}')
        
        try:
            with urlopen(req, timeout=10) as resp:
                return json.loads(resp.read().decode('utf-8'))
        except HTTPError as e:
            return {'error': e.code, 'message': e.read().decode('utf-8')}
        except Exception as e:
            return {'error': str(e)}
    
    def respond(self, status, html):
        self.send_response(status)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(html.encode('utf-8'))

def main():
    print("="*50)
    print("WHOOP OAuth Server")
    print("="*50)
    print(f"Listening: {REDIRECT_URI}")
    print("Waiting for authorization...")
    print()
    
    try:
        server = HTTPServer(('127.0.0.1', 8080), Handler)
        server.handle_request()
    except KeyboardInterrupt:
        print("\nStopped.")
    except Exception as e:
        print(f"Error: {e}")
    
    print("\nDone!")

if __name__ == '__main__':
    main()
