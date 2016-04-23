# note: we could just write this inline, rather than relying on anyone having it?
TEMP=`mktemp`
cp "$1" "$TEMP"
cat "$TEMP" > "$ORIGINAL" &
cat "$REVISED" > "$1" &
wait
