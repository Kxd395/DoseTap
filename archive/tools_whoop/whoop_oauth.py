#!/usr/bin/env python3
"""WHOOP OAuth flow - captures code and exchanges for token automatically"""
import http.server
import urllib.parse
import urllib.request
import json
import ssl

# WHOOP credentials
CLIENT_ID = "edf2495a-adff-4b87-b845-9529051a7b39"
CLIENT_SECRET = "0aca5c56ec53b210260d85ac24cf57ced13dc4b4e77cbf7cf2ca20b7d3a9ed9e"
REDIRECT_URI = "http://127.0.0.1:8080/callback"
TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token"

class OAuthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        
        if 'code' in params:
            code = params['code'][0]
            print(f"\n✅ Got authorization code: {code[:20]}...")
            
            # Exchange code for token
            print("🔄 Exchanging code for access token...")
            token_data = self.exchange_code(code)
            
            if 'access_token' in token_data:
                access_token = token_data['access_token']
                refresh_token = token_data.get('refresh_token', 'N/A')
                expires_in = token_data.get('expires_in', 'N/A')
                
                print(f"\n🎉 SUCCESS!")
                print(f"Access Token: {access_token[:30]}...")
                print(f"Refresh Token: {refresh_token[:30] if refresh_token != 'N/A' else 'N/A'}...")
                print(f"Expires In: {expires_in} seconds")
                
                # Test the token by fetching profile
                print("\n📡 Testing API - fetching your profile...")
                profile = self.test_api(access_token)
                
                html = f"""<html><body style="font-family: system-ui; padding: 40px;">
                <h1>✅ WHOOP Connected Successfully!</h1>
                <h2>Your Profile:</h2>
                <pre style="background: #f0f0f0; padding: 15px;">{json.dumps(profile, indent=2)}</pre>
                <h2>Tokens (saved to terminal output):</h2>
                <p>Access Token: <code>{access_token[:40]}...</code></p>
                <p>Expires In: {expires_in} seconds</p>
                </body></html>"""
            else:
                error = token_data.get('error', 'Unknown error')
                print(f"\n❌ Token exchange failed: {error}")
                html = f"<html><body><h1>❌ Error</h1><pre>{json.dumps(token_data, indent=2)}</pre></body></html>"
        else:
            error = params.get('error', ['Unknown'])[0]
            html = f"<html><body><h1>❌ Auth Failed: {error}</h1></body></html>"
        
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(html.encode())
    
    def exchange_code(self, code):
        data = urllib.parse.urlencode({
            'grant_type': 'authorization_code',
            'code': code,
            'redirect_uri': REDIRECT_URI,
            'client_id': CLIENT_ID,
            'client_secret': CLIENT_SECRET
        }).encode()
        
        req = urllib.request.Request(TOKEN_URL, data=data, method='POST')
        req.add_header('Content-Type', 'application/x-www-form-urlencoded')
        
        try:
            with urllib.request.urlopen(req) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            return json.loads(e.read().decode())
    
    def test_api(self, token):
        req = urllib.request.Request('https://api.prod.whoop.com/developer/v1/user/profile/basic')
        req.add_header('Authorization', f'Bearer {token}')
        try:
            with urllib.request.urlopen(req) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            return {"error": e.code, "message": e.read().decode()}
    
    def log_message(self, format, *args):
        pass  # Suppress default logging

if __name__ == '__main__':
    print("="*50)
    print("WHOOP OAuth Token Exchange Server")
    print("="*50)
    print(f"Listening on {REDIRECT_URI}")
    print("Waiting for authorization callback...")
    print()
    
    server = http.server.HTTPServer(('127.0.0.1', 8080), OAuthHandler)
    server.handle_request()
    print("\n✅ Done! You can close this terminal.")
