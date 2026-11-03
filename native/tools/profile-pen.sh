#!/bin/bash
# Records 20 s of the main thread while writing on the pen page (Time Profiler) into ~/Desktop/pen.trace.
# Usage: bash native/tools/profile-pen.sh
DEVICE=00008027-000A78590122002E
OUT="$HOME/Desktop/pen.trace"
rm -rf "$OUT"
echo "Recording starts in 3 seconds and lasts 20. Open the pen page and WRITE (pauses of 2-3 s between words)."
sleep 3
xcrun xctrace record --template "Time Profiler" --device "$DEVICE" --output "$OUT" --time-limit 20s --launch -- com.bulletlife.notebook
echo "Done: $OUT"
