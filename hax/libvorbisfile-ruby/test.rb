#!/usr/bin/env ruby

# test.rb - part of ruby-vorbisfile
#
# Copyright (C) 2001 Rik Hemsley (rikkus) <rik@kde.org>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


require 'iconv'
require 'vorbisfile'

$my_charset = 'iso-8859-1'

if ARGV.empty?
  $stderr.print "Usage: #{File.basename($0)} <filename> ...\n"
  $stderr.print "You probably want to pipe to a program, e.g. aplay -meq\n"
  exit 1
end

ARGV.each do |filename|

  f = File.new(filename, "r")

  if !f
    $stderr.print "Can't open #{filename}\n"
    next
  end

  vf = Ogg::VorbisFile.new

  if !vf.open(f)
    $stderr.print "Can't read vorbis data from #{filename}\n"
    next
  end

  comments = vf.comments(-1)

  artist  = comments["artist"]
  title   = comments["title"]

  begin
    artist = Iconv.iconv($my_charset, 'utf-8', artist)
  rescue
    artist = "Unknown artist"
  end

  begin
    title = Iconv.iconv($my_charset, 'utf-8', title)
  rescue
    title = "Unknown title"
  end

  $stderr.print "#{artist} - #{title}\n"

  buf = ""

  while vf.read(buf, 4096, false, 2, true)
    $stdout.print buf
  end

  vf.close
end
