# 1. Make a FIFO at $READ, which perl will write to.
mkfifo $READ
# 2. Write the filename to the $WRITE FIFO.
echo $1 > $WRITE
# 3. Block until $READ is written, then delete both, and recreate $WRITE
cat $READ > /dev/null
rm -f $READ $WRITE
mkfifo $WRITE
