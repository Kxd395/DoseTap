#!/usr/bin/env python3
"""
WHOOP Data Fetcher - Saves tokens and fetches sleep/recovery data
Tokens are saved to ~/.dosetap_whoop_tokens.json
"""
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import subprocess
import json
import os
from datetime import datetime, timedelta

CLIENT_ID = "edf2495a-adff-4b87-b845-9529051a7b39"
CLIENT_SECRET = "0aca5c56ec53b210260d85ac24cf57ced13dc4b4e77cbf7cf2ca20b7d3a9ed9e"
REDIRECT_URI = "http://127.0.0.1:8888/callback"
BASE_URL = "https://api.prod.whoop.com"
TOKEN_FILE = os.path.expanduser("~/.dosetap_whoop_tokens.json")

def curl_get(url, token):
    """Make GET request using curl"""
    result = subprocess.run([
        'curl', '-s', url,
        '-H', f'Authorization: Bearer {token}'
    ], capture_output=True, text=True)
    return result.stdout

def curl_post(url, data):
    """Make POST request using curl"""
    args = ['curl', '-s', '-X', 'POST', url, '-H', 'Content-Type: application/x-www-form-urlencoded']
    for k, v in data.items():
        args.extend(['-d', f'{k}={v}'])
    result = subprocess.run(args, capture_output=True, text=True)
    return result.stdout

def save_tokens(access_token, refresh_token, expires_in):
    """Save tokens to file"""
    data = {
        'access_token': access_token,
        'refresh_token': refresh_token,
        'expires_at': (datetime.now() + timedelta(seconds=expires_in)).isoformat(),
        'saved_at': datetime.now().isoformat()
    }
    with open(TOKEN_FILE, 'w') as f:
        json.dump(data, f, indent=2)
    print(f">>> Tokens saved to {TOKEN_FILE}")

def load_tokens():
    """Load tokens from file"""
    if os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE) as f:
            return json.load(f)
    return None

def fetch_whoop_data(token):
    """Fetch sleep, recovery, and cycle data"""
    print("\n" + "="*60)
    print("FETCHING YOUR WHOOP DATA")
    print("="*60)
    
    # Get recent sleep
    print("\n📊 Recent Sleep (last 7 days):")
    sleep_data = json.loads(curl_get(f"{BASE_URL}/developer/v1/activity/sleep?limit=7", token))
    if 'records' in sleep_data:
        for s in sleep_data['records'][:3]:
            score = s.get('score', {})
            print(f"  - {s.get('start', 'N/A')[:10]}: {score.get('sleep_performance_percentage', 'N/A')}% performance, "
                  f"{score.get('stage_summary', {}).get('total_in_bed_time_milli', 0)//3600000}h in bed")
    else:
        print(f"  Response: {sleep_data}")
    
    # Get recent recovery
    print("\n💚 Recent Recovery:")
    recovery_data = json.loads(curl_get(f"{BASE_URL}/developer/v1/recovery?limit=7", token))
    if 'records' in recovery_data:
        for r in recovery_data['records'][:3]:
            score = r.get('score', {})
            print(f"  - Recovery: {score.get('recovery_score', 'N/A')}%, "
                  f"HRV: {score.get('hrv_rmssd_milli', 'N/A'):.1f}ms, "
                  f"RHR: {score.get('resting_heart_rate', 'N/A')} bpm")
    else:
        print(f"  Response: {recovery_data}")
    
    # Get recent cycles
    print("\n🔄 Recent Cycles:")
    cycle_data = json.loads(curl_get(f"{BASE_URL}/developer/v1/cycle?limit=3", token))
    if 'records' in cycle_data:
        for c in cycle_data['records'][:3]:
            score = c.get('score', {})
            print(f"  - {c.get('start', 'N/A')[:10]}: Strain {score.get('strain', 'N/A'):.1f}, "
                  f"Avg HR: {score.get('average_heart_rate', 'N/A')} bpm")
    else:
        print(f"  Response: {cycle_data}")
    
    # Get body measurements
    print("\n📏 Body Measurements:")
    body_data = json.loads(curl_get(f"{BASE_URL}/developer/v1/user/measurement/body", token))
    if 'height_meter' in body_data:
        print(f"  Height: {body_data.get('height_meter', 0)*100:.0f} cm")
        print(f"  Weight: {body_data.get('weight_kilogram', 0):.1f} kg")
        print(f"  Max HR: {body_data.get('max_heart_rate', 'N/A')} bpm")
    else:
        print(f"  Response: {body_data}")
    
    print("\n" + "="*60)
    return sleep_data, recovery_data, cycle_data

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    
    def do_GET(self):
        query = parse_qs(urlparse(self.path).query)
        if 'code' not in query:
            self.respond("<h1>No code</h1>")
            return
        
        code = query['code'][0]
        print(f"\n>>> Got authorization code")
        print(">>> Exchanging for token...")
        
        token_response = curl_post(f"{BASE_URL}/oauth/oauth2/token", {
            'grant_type': 'authorization_code',
            'code': code,
            'redirect_uri': REDIRECT_URI,
            'client_id': CLIENT_ID,
            'client_secret': CLIENT_SECRET
        })
        
        token_data = json.loads(token_response)
        
        if 'error' in token_data:
            self.respond(f"<h1>Error</h1><pre>{json.dumps(token_data, indent=2)}</pre>")
            return
        
        access_token = token_data.get('access_token', '')
        refresh_token = token_data.get('refresh_token', '')
        expires_in = token_data.get('expires_in', 3600)
        
        print(f">>> Got access token: {access_token[:40]}...")
        
        # SAVE tokens so we don't lose them!
        save_tokens(access_token, refresh_token, expires_in)
        
        # Fetch WHOOP data
        sleep_data, recovery_data, cycle_data = fetch_whoop_data(access_token)
        
        # Build response
        html = f"""<html><head><title>WHOOP Data</title></head>
        <body style="font-family:system-ui;padding:40px;max-width:800px;margin:auto;">
        <h1 style="color:green">✅ WHOOP Connected & Data Fetched!</h1>
        
        <h2>📊 Recent Sleep</h2>
        <pre style="background:#f0f0f0;padding:15px;border-radius:8px;overflow:auto;font-size:12px">{json.dumps(sleep_data.get('records', [])[:2], indent=2)}</pre>
        
        <h2>💚 Recent Recovery</h2>
        <pre style="background:#f0f0f0;padding:15px;border-radius:8px;overflow:auto;font-size:12px">{json.dumps(recovery_data.get('records', [])[:2], indent=2)}</pre>
        
        <h2>🔄 Recent Cycles</h2>
        <pre style="background:#f0f0f0;padding:15px;border-radius:8px;overflow:auto;font-size:12px">{json.dumps(cycle_data.get('records', [])[:2], indent=2)}</pre>
        
        <p style="color:#666">Tokens saved to <code>{TOKEN_FILE}</code></p>
        <p style="color:#666">Token expires in {expires_in} seconds. Refresh token saved for renewal.</p>
        </body></html>"""
        
        self.respond(html)
    
    def respond(self, html):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(html.encode())

if __name__ == '__main__':
    # Check for existing tokens
    tokens = load_tokens()
    if tokens:
        print(f"Found saved tokens from {tokens.get('saved_at', 'unknown')}")
        expires = datetime.fromisoformat(tokens['expires_at'])
        if expires > datetime.now():
            print("Token still valid! Fetching data...")
            fetch_whoop_data(tokens['access_token'])
            exit(0)
        else:
            print("Token expired, need to re-authorize")
    
    print("="*60)
    print("WHOOP OAuth + Data Fetcher (port 8888)")
    print("="*60)
    print("Waiting for authorization callback...")
    print("Tokens will be saved to:", TOKEN_FILE)
    HTTPServer(('127.0.0.1', 8888), Handler).handle_request()
    print("\nDone!")
