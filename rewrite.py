#!/usr/bin/python -u
#
# returns '' if no match for rewrite
#

import sys
import re

f = open(sys.path[0] + '/rewrites.txt', 'r')
rewrites = f.readlines()
regex_s = '('
comment = re.compile('^(.*)(#.*)$')
strip_whitespace = re.compile('\S*')
for r in rewrites:
	match = comment.match(r)
	if match and len(match.group(1)) > 0:
		r = match.group(1)
	elif match:
		continue
	match = strip_whitespace.match(r)
	if match and len(match.group()) > 0:
		r = match.group()
	regex_s += r.strip('\n') + '|'

regex_s = regex_s[:len(regex_s)-1]
regex_s += ')'
regex = re.compile(regex_s, re.IGNORECASE)

while 1:
	line = sys.stdin.readline()
	if line:
		if regex.search(line):
			print 'match'
		else:
			print ''
