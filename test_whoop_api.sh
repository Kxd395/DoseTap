#!/bin/bash

# DoseTap WHOOP API Test Script
# This script demonstrates what API calls DoseTap would make

echo "🌙 DoseTap WHOOP API Test"
echo "=========================="
echo ""

# Your actual credentials (from WHOOP Developer Dashboard)
CLIENT_ID="6b7c7936-ecfc-489f-8b80-0cffb303af9e"
CLIENT_SECRET="7f0faa286293acd22d17256281eaf98e7873a7be36e88d83c8fb149a52ae191b"

echo "🔑 Your WHOOP App Credentials:"
echo "Client ID: $CLIENT_ID"
echo "Client Secret: [HIDDEN]"
echo ""

echo "📡 API Endpoints DoseTap Uses:"
echo "1. Authorization: https://api.prod.whoop.com/oauth/oauth2/auth"
echo "2. Token Exchange: https://api.prod.whoop.com/oauth/oauth2/token"
echo "3. Sleep Data: https://api.prod.whoop.com/v2/activity/sleep"
echo ""

echo "🔐 OAuth Flow Simulation:"
echo "Step 1: User clicks 'Connect WHOOP'"
echo "Step 2: Browser opens WHOOP authorization page"
echo "Step 3: User logs in and grants permission"
echo "Step 4: WHOOP redirects to: dosetap://oauth/callback"
echo "Step 5: App receives authorization code"
echo "Step 6: App exchanges code for access token"
echo ""

echo "📊 What Data Would Be Retrieved:"
echo "- Sleep start and end times"
echo "- Sleep stage information (awake periods)"
echo "- Time from sleep start to first wake (TTFW)"
echo "- Used to calculate safe medication timing (150-240 min window)"
echo ""

echo "🛡️ Privacy & Security:"
echo "- Only 'read:sleep' permission requested"
echo "- Data processed locally on device"
echo "- No sleep data stored permanently"
echo "- Access tokens automatically refreshed"
echo ""

echo "🧪 To Test Real Integration:"
echo "1. Build and run DoseTap app"
echo "2. Tap 'Connect WHOOP'"
echo "3. Log in with your WHOOP credentials"
echo "4. Grant sleep data permission"
echo "5. App will fetch your recent sleep data"
echo ""

echo "⚠️  Note: You have 10 test users remaining in development mode"
