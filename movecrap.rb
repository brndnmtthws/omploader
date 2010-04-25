#!/usr/bin/env ruby

require 'fileutils'

# Move data.
Dir.mkdir 'data.new'
dir = Dir.new 'data'
files = dir.entries
files.delete('..')
files.delete('.')

files.each do |file|
	subdir = file[0..1]
	FileUtils.mkdir('data.new/' + subdir) if not File.directory?('data.new/' + subdir)
	FileUtils.mv('data/' + file, 'data.new/' + subdir + '/' + file)
end

# Move thumbnails.
Dir.mkdir 'thumbnails.new'
dir = Dir.new 'thumbnails'
files = dir.entries
files.delete('..')
files.delete('.')

files.each do |file|
	subdir = file[0..1]
	FileUtils.mkdir('thumbnails.new/' + subdir) if not File.directory?('thumbnails.new/' + subdir)
	FileUtils.mv('thumbnails/' + file, 'thumbnails.new/' + subdir + '/' + file)
end
