#!/usr/bin/python3
#
# rotate.py
# Rotate lines from stdin

import sys

# how much to rotate
n = int(sys.argv[1])

# read all lines into array
lines = sys.stdin.readlines();

# rotate the list
rotated = lines[n:] + lines[:n]

for line in rotated:
	print (line, end='')
