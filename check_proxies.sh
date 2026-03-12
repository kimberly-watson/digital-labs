#!/bin/bash
echo "=== LISTENING PORTS ==="
ss -tlnp | sort
echo "=== CURL 8082 (Nexus proxy) ==="
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8082/ && echo " OK"
echo "=== CURL 8072 (IQ proxy) ==="
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8072/ && echo " OK"
echo "=== WIDGET JS ==="
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8082/lab-tutor-widget.js && echo " widget OK"
