#!/bin/bash
echo "=== Widget file first 5 lines ==="
head -5 /var/www/html/lab-tutor-widget.js

echo ""
echo "=== Does Nexus HTML have defer on widget script? ==="
curl -s http://127.0.0.1:8082/ | grep "lab-tutor-widget"

echo ""
echo "=== Does Nexus body have any child elements? ==="
curl -s http://127.0.0.1:8082/ | grep -i "<body"
