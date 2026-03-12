#!/bin/bash
echo "=== Does Nexus HTML contain widget injection? ==="
curl -s http://127.0.0.1:8082/ | grep -c "sn-bubble\|lab-tutor-widget" || echo "0 matches"
curl -s http://127.0.0.1:8082/ | grep "lab-tutor-widget" || echo "NOT FOUND in HTML"

echo ""
echo "=== Does Nexus response have </body>? ==="
curl -s http://127.0.0.1:8082/ | grep -i "</body>" || echo "NO </body> TAG FOUND"

echo ""
echo "=== Content-Encoding header (must be empty for sub_filter) ==="
curl -sI http://127.0.0.1:8082/ | grep -i "content-encoding" || echo "No content-encoding (good)"

echo ""
echo "=== Widget JS reachable? ==="
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8082/lab-tutor-widget.js
echo ""

echo ""
echo "=== First 50 lines of Nexus root HTML ==="
curl -s http://127.0.0.1:8082/ | head -50
