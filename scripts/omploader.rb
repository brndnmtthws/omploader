#!/usr/bin/env ruby
#
# $Id$
#
# Copyright 2007-2008 David Shakaryan <omp@gentoo.org>
# Copyright 2007-2008 Brenden Matthews <brenden@rty.ca>
#
# Distributed under the terms of the GNU General Public License v3
#

require 'base64'
require 'fcgi'
require 'cgi/session'
require 'cgi/session/pstore'
require 'mysql'
require 'yaml'
require 'mmap'
require 'tempfile'
require 'logger'
require 'find'
require 'memcache'

ConfigFile = YAML::load(File.open('config'))

Max_upload_count = ConfigFile['limits']['upload_count']
Max_upload_period = ConfigFile['limits']['upload_period'] * 60
Max_rand = ConfigFile['limits']['max_random_rows'] * 5
Vote_expiry = ConfigFile['limits']['vote_expiry'] * 86400
Visitor_expiry = ConfigFile['limits']['visitor_expiry'] * 86400
Thumbnail_expiry = ConfigFile['limits']['thumbnail_expiry'] * 86400
Owner_expiry = ConfigFile['limits']['owner_expiry'] * 86400

Pub_key = ConfigFile['captcha']['pub_key']
Priv_key = ConfigFile['captcha']['priv_key']

Debug = ConfigFile['debug']['enabled']

Paths = ConfigFile['paths']

Sql = Mysql.init

def db_connect
	db_params = ConfigFile['database']
	db = Sql.real_connect(db_params['host'], db_params['user'], db_params['pass'], db_params['name'])
	query = db.prepare('set time_zone = ?')
	stmt = query.execute(db_params['timezone'])
	stmt.close
	db.autocommit(false)
	return db
end

def xhtml_pre(title = '', search = '', showsearch = true)
	xhtml_pre = 
		'<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">' + "\n" +
		'<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">' + "\n" +
		"\t" + '<head>' + "\n" +
		"\t\t" + '<meta http-equiv="Content-Type" content="text/html;charset=utf-8" />' + "\n" +
		"\t\t" + '<link rel="stylesheet" type="text/css" href="style.css" />' + "\n" +
		"\t\t" + '<link rel="shortcut icon" href="omploader_icon.png" type="image/x-icon" />' + "\n" +
		"\t\t" + '<title>omploader' + title + '</title>' + "\n" +
		"\t" + '</head>' + "\n" +
		"\t" + '<body>' + "\n" +
		"\t\t" + '<div id="container">' + "\n" +
		"\t\t\t" + '<div id="header">' + "\n" +
		"\t\t\t\t" + '<div id="title"><a href="/"><img src="omploader.png" alt="omploader" /></a></div>'  + "\n" +
		"\t\t\t\t" + '<form enctype="multipart/form-data" action="l" method="post">' + "\n"
	if showsearch
		xhtml_pre +=
			"\t\t\t\t\t" + '<div id="search">' + "\n" +
			"\t\t\t\t\t\t" + '<input name="search_post" size="20" class="field" type="text" value="' + search.gsub(/\\/, '\\') + '" /><input value="search" class="button" type="submit" />' + "\n" +
			"\t\t\t\t\t" + '</div>' + "\n"
	end
	xhtml_pre +=
		"\t\t\t\t" + '</form>' + "\n" +
		"\t\t\t" + '</div>' + "\n"
end

def xhtml_post
	xhtml_post =
		"\t\t\t" + '<div id="footer">' + "\n" +
		"\t\t\t\t" + '<div class="right"><a href="https://addons.mozilla.org/en-US/firefox/addon/5638">firefox extension</a></div>' + "\n" +
		"\t\t\t\t" + '<a href="irc://irc.freenode.net/##pink">pink</a> <span class="separator">&#x2503;</span> <a href="http://www.ruby-lang.org/">ruby</a> <span class="separator">&#x2503;</span> <a href="http://www.vim.org/">vim</a> <span class="separator">&#x2503;</span> <a href="http://svn.omploader.org/">svn</a> <span class="separator">&#x2503;</span> <a href="faq.xhtml">faq</a>' + "\n" + 
		"\t\t\t" + '</div>' + "\n" +
		"\t\t" + '</div>' + "\n" +
		"\t" + '</body>' + "\n" +
		'</html>'
end

# Reconnect to database if connection is dropped.
def db_check(db)
	begin
		db.ping
	rescue Mysql::Error => err
		db = db_connect
	ensure
		raise Sql.error() if db.nil?
	end
end

# Update visitors table in database.
def register_visit(cgi, db)
	query = db.prepare('insert into visitors (address) values (?) on duplicate key update last_visit = current_timestamp, id = last_insert_id(id)')
	stmt = query.execute(cgi.remote_addr.to_s)
	visitor_id = stmt.insert_id.to_s
	stmt.close
	return visitor_id
end

def run_cron(db)
	q = db.prepare('delete from votes where unix_timestamp(date) < unix_timestamp(current_timestamp) - ?')
	q.execute(Vote_expiry)
	q = db.prepare('delete from visitors where unix_timestamp(last_visit) < unix_timestamp(current_timestamp) - ?')
	q.execute(Visitor_expiry)
	q = db.prepare('select metadata.id from metadata inner join thumbnails on metadata.thumbnail_id = thumbnails.id where unix_timestamp(thumbnails.last_accessed) < unix_timestamp(current_timestamp) - ?')
	stmt = q.execute(Thumbnail_expiry)
	num_rows = stmt.num_rows
	num_rows.times do
		id = stmt.fetch.to_s
		File.unlink(Paths['thumbnails'] + '/' + id.to_b64) if File.exist?(Paths['thumbnails'] + '/' + id.to_b64)
	end
	stmt.close
	q = db.prepare('update metadata inner join thumbnails on thumbnails.id = metadata.thumbnail_id set metadata.thumbnail_id = null where unix_timestamp(thumbnails.last_accessed) < unix_timestamp(current_timestamp) - ?')
	q.execute(Thumbnail_expiry)
	q = db.prepare('delete from thumbnails where unix_timestamp(last_accessed) < unix_timestamp(current_timestamp) - ?')
	q.execute(Thumbnail_expiry)
	q = db.prepare('update metadata inner join owners on owners.id = metadata.owner_id set metadata.owner_id = null where unix_timestamp(owners.last_accessed) < unix_timestamp(current_timestamp) - ?')
	q.execute(Owner_expiry)
	q = db.prepare('delete from owners where unix_timestamp(last_accessed) < unix_timestamp(current_timestamp) - ?')
	q.execute(Owner_expiry)
	q.close
end

def session(cgi, new)
	session = CGI::Session.new(cgi,
		'database_manager' => CGI::Session::PStore,  # use PStore
		'session_key' => '_rb_sess_id',              # custom session key
		'prefix' => 'pstore_sid_',                   # PStore option
		'session_expires' => Time.now + 60*60*24*365,
		'session_path' => '/',
		'new_session' => new)
end

def session_id(cgi)
	begin
		s = session(cgi, false)
		return s.session_id.to_s
	rescue ArgumentError
		return ''
	end
end

def get_owner_id(cgi, db)
	begin
		s = session(cgi, false)
		query = db.prepare('insert into owners (session_id) values (?) on duplicate key update session_id = ?, id = last_insert_id(id)')
		stmt = query.execute(s.session_id.to_s, s.session_id.to_s)
		owner_id = query.insert_id.to_s
		stmt.close
	rescue ArgumentError
		# need to make new session
		s = session(cgi, true)
		s.close
		begin
			s = session(cgi, false)
			# this is a new owner
			query = db.prepare('insert into owners (session_id) values (?)')
			stmt = query.execute(s.session_id.to_s)
			owner_id = stmt.insert_id.to_s
			s['owner_id'] = owner_id
		rescue ArgumentError
			# browser won't allow or doesn't support cookies
		end
	end
	return owner_id
end

class String
	# Convert string to integer to Base36 to modified Base64.
	def to_b64
		str = self
		str.gsub!('/', '-/')
		str.gsub!('_', '/')
		str = str.to_i.to_s(base=36)
		str = Base64.encode64(str)
		str.chomp!
		str.gsub!('=', '')
		return str
	end

	# Convert modified Base64 to Base36 to integer to string.
	def to_id
		str = self
		while str.length % 4 > 0
			str += '='
		end
		str = Base64.decode64(str)
		str = str.to_i(base=36).to_s
		str.gsub!('/', '_')
		return str
	end

	# Sanitise HTML code to avoid opening tags.
	def sanitise
		self.gsub('<', '&lt;').gsub('>', '&gt;')
	end
end

Cache = MemCache::new(:debug => false,
							 :c_threshold => 100_000,
							 :namespace => ConfigFile['memcached']['namespace'])

Cache.servers += ConfigFile['memcached']['servers']

Default_cache_expiry_long = ConfigFile['memcached']['expiry_long']
Default_cache_expiry_short = ConfigFile['memcached']['expiry_short']
