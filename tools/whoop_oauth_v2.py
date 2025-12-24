#!/usr/bin/env python3
"""
WHOOP OAuth 2.0 Token Exchange
Based on official WHOOP docs: https://developer.whoop.com/docs/developing/oauth
"""
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs, urlencode
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import json

# Configuration from Secrets.swift
CLIENT_ID = "edf2495a-adff-4b87-b845-9529051a7b39"
CLIENT_SECRET = "0aca5c56ec53b210260d85ac24cf57ced13dc4b4e77cbf7cf2ca20b7d3a9ed9e"
REDIRECT_URI = "http://127.0.0.1:8080/callback"

# WHOOP API URLs (from docs)
WHOOP_API_HOSTNAME = "https://api.prod.whoop.com"
TOKEN_URL = f"{WHOOP_API_HOSTNAME}/oauth/oauth2/token"
PROFILE_URL = f"{WHOOP_API_HOSTNAME}/developer/v1/user/profile/basic"


class OAuthCallbackHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        print(f"  [{args[1]}] {args[0]}")
    
    def do_GET(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)
        
        if 'code' not in params:
            self._send_error(params.get('error', ['Unknown error'])[0])
            return
        
        code = params['code'][0]
        state = params.get('state', [''])[0]
        print(f"\n✅ Received authorization code")
        print(f"   State: {state}")
        
        # Exchange code for token
        print("\n🔄 Exchanging code for access token...")
        token_result = self._exchange_token(code)
        
        if 'error' in token_result:
            print(f"❌ Token exchange failed: {token_result}")
            self._send_error(f"Token exchange failed: {token_result.get('error_description', token_result.get('error'))}")
            return
        
        access_token = token_result['access_token']
        refresh_token = token_result.get('refresh_token', 'N/A')
        expires_in = token_result.get('expires_in', 'N/A')
        
        print(f"\n🎉 Token exchange successful!")
        print(f"   Access Token: {access_token[:40]}...")
        print(f"   Refresh Token: {refresh_token[:40] if refresh_token != 'N/A' else 'N/A'}...")
        print(f"   Expires In: {expires_in} seconds")
        
        # Test API with the token
        print(f"\n📡 Testing API - fetching profile...")
        profile = self._fetch_profile(access_token)
        
        if 'error' in profile:
            print(f"⚠️  Profile fetch failed: {profile}")
        else:
            print(f"   User: {profile.get('first_name', '?')} {profile.get('last_name', '?')}")
            print(f"   Email: {profile.get('email', '?')}")
            print(f"   User ID: {profile.get('user_id', '?')}")
        
        # Send success page
        self._send_success(token_result, profile)
    
    def _exchange_token(self, code):
        """Exchange authorization code for access token"""
        data = urlencode({
            'grant_type': 'authorization_code',
            'code': code,
            'redirect_uri': REDIRECT_URI,
            'client_id': CLIENT_ID,
            'client_secret': CLIENT_SECRET,
        }).encode('utf-8')
        
        req = Request(TOKEN_URL, data=data, method='POST')
        req.add_header('Content-Type', 'application/x-www-form-urlencoded')
        
        try:
            with urlopen(req) as resp:
                return json.loads(resp.read().decode('utf-8'))
        except HTTPError as e:
            return json.loads(e.read().decode('utf-8'))
    
    def _fetch_profile(self, access_token):
        """Fetch user profile using access token"""
        req = Request(PROFILE_URL)
        req.add_header('Authorization', f'Bearer {access_token}')
        
        try:
            with urlopen(req) as resp:
                return json.loads(resp.read().decode('utf-8'))
        except HTTPError as e:
            try:
                return json.loads(e.read().decode('utf-8'))
            except:
                return {'error': f'HTTP {e.code}'}
    
    def _send_success(self, tokens, profile):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        
        html = f"""<!DOCTYPE html>
<html>
<head><title>WHOOP Connected!</title></head>
<body style="font-family: -apple-system, system-ui, sans-serif; max-width: 600px; margin: 50px auto; padding: 20px;">
    <h1 style="color: green;">✅ WHOOP Connected Successfully!</h1>
    
    <h2>Your Profile</h2>
    <pre style="background: #f5f5f5; padding: 15px; border-radius: 8px; overflow-x: auto;">{json.dumps(profile, indent=2)}</pre>
    
    <h2>Tokens (also printed to terminal)</h2>
    <p><strong>Access Token:</strong> <code>{tokens.get('access_token', 'N/A')[:50]}...</code></p>
    <p><strong>Refresh Token:</strong> <code>{tokens.get('refresh_token', 'N/A')[:50] if tokens.get('refresh_token') else 'N/A'}...</code></p>
    <p><strong>Expires In:</strong> {tokens.get('expires_in', 'N/A')} seconds</p>
    <p><strong>Scope:</strong> {tokens.get('scope', 'N/A')}</p>
    
    <p style="margin-top: 30px; color: #666;">You can close this window now.</p>
</body>
</html>"""
        self.wfile.write(html.encode())
    
    def _send_error(self, error):
        self.send_response(400)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        
        html = f"""<!DOCTYPE html>
<html>
<head><title>WHOOP Error</title></head>
<body style="font-family: -apple-system, system-ui, sans-serif; max-width: 600px; margin: 50px auto; padding: 20px;">
    <h1 style="color: red;">❌ Authorization Failed</h1>
    <p><strong>Error:</strong> {error}</p>
    <p style="margin-top: 30px;"><a href="javascript:window.close()">Close Window</a></p>
</body>
</html>"""
        self.wfile.write(html.encode())


def main():
    print("=" * 60)
    print("WHOOP OAuth 2.0 Token Exchange Server")
    print("=" * 60)
    print(f"\nConfiguration:")
    print(f"  Client ID: {CLIENT_ID[:20]}...")
    print(f"  Redirect URI: {REDIRECT_URI}")
    print(f"  Token URL: {TOKEN_URL}")
    print(f"  Profile URL: {PROFILE_URL}")
    print(f"\n🚀 Server listening on http://127.0.0.1:8080")
    print("   Waiting for OAuth callback...\n")
    
    server = HTTPServer(('127.0.0.1', 8080), OAuthCallbackHandler)
    server.handle_request()
    
    print("\n" + "=" * 60)
    print("✅ Done! Server stopped.")
    print("=" * 60)


if __name__ == '__main__':
    main()
