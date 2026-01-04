#!/bin/bash
# generate_cert_pins.sh
# 
# Generate SHA-256 SPKI pins for TLS certificate pinning
# These pins can be used in CertificatePinning.swift
#
# Usage:
#   ./generate_cert_pins.sh api.dosetap.com
#   ./generate_cert_pins.sh https://api.dosetap.com
#   ./generate_cert_pins.sh cert.pem  # From local file

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to generate pin from PEM certificate
generate_pin_from_pem() {
    local cert_file="$1"
    local pin
    
    # Extract public key and generate SHA-256 hash
    pin=$(openssl x509 -in "$cert_file" -pubkey -noout 2>/dev/null | \
          openssl pkey -pubin -outform DER 2>/dev/null | \
          openssl dgst -sha256 -binary | \
          base64)
    
    echo "sha256/$pin"
}

# Function to fetch certificate chain from server
fetch_and_pin() {
    local host="$1"
    local port="${2:-443}"
    
    echo -e "${GREEN}Fetching certificate chain from ${host}:${port}${NC}"
    echo ""
    
    # Create temp directory for certificates
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Fetch the certificate chain
    echo | openssl s_client -connect "${host}:${port}" -servername "${host}" \
           -showcerts 2>/dev/null | \
    awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' > "$temp_dir/chain.pem"
    
    # Split the chain into individual certificates
    csplit -f "$temp_dir/cert-" -b "%02d.pem" "$temp_dir/chain.pem" \
           '/-----BEGIN CERTIFICATE-----/' '{*}' 2>/dev/null || true
    
    # Remove empty first file if it exists
    rm -f "$temp_dir/cert-00.pem" 2>/dev/null
    
    # Generate pins for each certificate in the chain
    local cert_num=0
    local pins=()
    
    for cert_file in "$temp_dir"/cert-*.pem; do
        [ -f "$cert_file" ] || continue
        
        # Get certificate subject
        local subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | \
                       sed 's/subject=//')
        
        # Get expiration date
        local expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | \
                      sed 's/notAfter=//')
        
        # Generate pin
        local pin=$(generate_pin_from_pem "$cert_file")
        pins+=("$pin")
        
        echo -e "${YELLOW}Certificate $cert_num:${NC}"
        echo "  Subject: $subject"
        echo "  Expires: $expiry"
        echo -e "  Pin:     ${GREEN}$pin${NC}"
        echo ""
        
        ((cert_num++))
    done
    
    # Output Swift code
    echo ""
    echo -e "${GREEN}Swift code for CertificatePinning.swift:${NC}"
    echo ""
    echo "    public static func forDoseTapAPI() -> CertificatePinning {"
    echo "        let pins = ["
    for i in "${!pins[@]}"; do
        local comment=""
        if [ $i -eq 0 ]; then
            comment=" // Leaf certificate"
        elif [ $i -eq 1 ]; then
            comment=" // Intermediate CA"
        else
            comment=" // Root CA"
        fi
        echo "            \"${pins[$i]}\",$comment"
    done
    echo "        ]"
    echo ""
    echo "        return CertificatePinning("
    echo "            pins: pins,"
    echo "            domains: [\"$host\"],"
    echo "            allowFallback: false"
    echo "        )"
    echo "    }"
}

# Function to generate pin from local PEM file
pin_from_file() {
    local cert_file="$1"
    
    if [ ! -f "$cert_file" ]; then
        echo -e "${RED}Error: File not found: $cert_file${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Generating pin from: $cert_file${NC}"
    echo ""
    
    local subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | \
                   sed 's/subject=//')
    local expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | \
                  sed 's/notAfter=//')
    local pin=$(generate_pin_from_pem "$cert_file")
    
    echo "Subject: $subject"
    echo "Expires: $expiry"
    echo -e "Pin:     ${GREEN}$pin${NC}"
}

# Main
if [ $# -eq 0 ]; then
    echo "Usage: $0 <hostname|cert.pem>"
    echo ""
    echo "Examples:"
    echo "  $0 api.dosetap.com           # Fetch from server"
    echo "  $0 auth.dosetap.com:443      # With explicit port"
    echo "  $0 certificate.pem           # From local file"
    exit 1
fi

input="$1"

# Check if input is a file
if [ -f "$input" ]; then
    pin_from_file "$input"
    exit 0
fi

# Parse hostname and port
host=$(echo "$input" | sed 's|https://||' | sed 's|/.*||')
port=$(echo "$host" | grep -o ':[0-9]*' | sed 's/://' || echo "443")
host=$(echo "$host" | sed 's/:[0-9]*//')

fetch_and_pin "$host" "$port"
