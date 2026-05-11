#!/usr/bin/env bash
# Mock gate that WOULD pass; tests assert this is never invoked when enabled:false.
echo "OK (but this should NEVER run when disabled)"
exit 0
