#!/bin/sh
split -a 9 -d -b 65536 hda.bin hda    
for f in hda000000*; do    
    mv $f $f.bin    
done 
