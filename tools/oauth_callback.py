#!/usr/bin/env python3
"""Simple OAuth callback server for WHOOP testing"""
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

class CallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)
        
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        
        if 'code' in params:
            code = params['code'][0]
            state = params.get('state', [''])[0]
            html = f"""
            <html><body style="font-family: system-ui; padding: 40px; text-align: center;">
            <h1>✅ WHOOP Authorization Successful!</h1>
            <p><strong>Authorization Code:</strong></p>
            <code style="background: #f0f0f0; padding: 10px; display: block; word-break: break-all;">{code}</code>
            <p><strong>State:</strong> {state}</p>
            <p style="color: green;">Copy the code above and paste it in VS Code!</p>
            </body></html>
            """
        else:
            error = params.get('error', ['Unknown'])[0]
            html = f"""
            <html><body style="font-family: system-ui; padding: 40px; text-align: center;">
            <h1>❌ Authorization Failed</h1>
            <p>Error: {error}</p>
            </body></html>
            """
        self.wfile.write(html.encode())

if __name__ == '__main__':
    print("Starting OAuth callback server on http://127.0.0.1:8080")
    print("Waiting for WHOOP redirect...")
    server = HTTPServer(('127.0.0.1', 8080), CallbackHandler)
    server.handle_request()  # Handle one request then exit
    print("Done!")
