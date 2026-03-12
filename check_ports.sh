#!/bin/bash
nginx -t 2>&1
echo "---PORTS---"
ss -tlnp | grep -E '80[0-9][0-9]' | sort
