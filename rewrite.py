#!/usr/bin/python -u
#
# returns 'match' if there is a match, otherwise returns ''
#

import sys
import re
from random import choice

f = open(sys.path[0] + '/rewrites.txt', 'r')
rewrites = f.readlines()
regex_s = '('
comment = re.compile('^(.*)(#.*)$')
strip_whitespace = re.compile('\s*(\S*)')
for r in rewrites:
	match = comment.match(r)
	if match and len(match.group(1)) > 0:
		r = match.group(1)
	elif match:
		continue
	match = strip_whitespace.search(r)
	if match and len(match.group()) > 0:
		r = match.group(1)
		regex_s += r.strip('\n') + '|'

if len(regex_s) > 1:
	regex_s = regex_s[:len(regex_s)-1]
regex_s += ')'
regex = re.compile(regex_s, re.IGNORECASE)

lottery = range(1, 5)

while 1:
	line = sys.stdin.readline()
	if line:
		if regex.search(line) and choice(lottery) == 1:
			print 'match'
		else:
			print ''
