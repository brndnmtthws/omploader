#!/usr/bin/env ruby
#
# Copyright 2007-2009 David Shakaryan <omp@gentoo.org>
# Copyright 2007-2009 Brenden Matthews <brenden@diddyinc.com>
#
# Distributed under the terms of the GNU General Public License v3
#

require 'rubygems'
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
require 'pathname'

path = Pathname.new(__FILE__).dirname

Slogans = [
	'free, lean and mean image &amp; file hosting',
	'thanks for coming',
	'Omploader Recommends Windows Vista',
	'Nobody Does it Like Omp',
	'Made in Taiwan',
	'I Saw Omp and I Thought of You',
	'Omp Tested, Mother Approved',
	'You\'ve Got Questions. We\'ve got Omp',
	'~ ~ ~ ~ ~ ~',
	'<em>Yes We Can!</em>',
	'Beta since 2004',
	'Hey!!',
	'An Omp is Forever',
	'I\'m Lovin\' Omp',
	'Bigger. Better. Omploader.',
	'What Happens in Omp, Stays in Omp',
	'Don\'t Just Cover Up Bad Odors. Get Omp!',
	'Smile! You\'re on Omp!',
	'Smile! You\'re an Omp!',
	'Omp, now 100% Certified Organic.',
	'Omp. Not for Everyone.',
	'Next Time Ask for Omploader',
	'Omp Therefore I am',
	'Serving You Since You Got Here',
	'Omp: Service You Can Trust',
	'Excellent Source of Whole Grains',
	'50% Uptime Guaranteed, or Your Money Back!',
	'<a href="donate.html">Keep omploader alive</a>',
	'<a href="donate.html">omploader needs you</a>',
	'<a href="donate.html">freeloaders need not apply</a>',
	'<a href="donate.html">Omploader doesn\'t want to vanish</a>',
	'omp there it is',
]
Slogan = Slogans[rand(Slogans.size)]

ConfigFile = YAML::load(File.open(path + 'config'))

Max_upload_count = ConfigFile['limits']['upload_count']
Max_upload_period = ConfigFile['limits']['upload_period'] * 60
Max_rand = ConfigFile['limits']['max_random_rows'] * 5
Vote_expiry = ConfigFile['limits']['vote_expiry'] * 86400
Visitor_expiry = ConfigFile['limits']['visitor_expiry'] * 86400
Thumbnail_expiry = ConfigFile['limits']['thumbnail_expiry'] * 86400
Owner_expiry = ConfigFile['limits']['owner_expiry'] * 86400
Max_file_size = ConfigFile['limits']['max_file_size']
Xsendfile = ConfigFile['httpd']['xsendfile']

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

def html_pre(title = '', search = '', showsearch = true)
	html_pre =
		'<!DOCTYPE html>' + "\n" +
		'<html xml:lang="en" lang="en">' + "\n" +
		"\t" + '<head>' + "\n" +
		"\t\t" + '<meta http-equiv="Content-Type" content="text/html;charset=utf-8" />' + "\n" +
		"\t\t" + '<link rel="stylesheet" type="text/css" href="/style12.css" />' + "\n" +
		"\t\t" + '<link rel="shortcut icon" href="/omploader_icon2.png" type="image/x-icon" />' + "\n"
	html_pre +=
		"\t\t" + '<title>omploader' + title + '</title>' + "\n" +
		"\t" + '</head>' + "\n"
	html_pre += "\t" + '<body>' + "\n"
	html_pre +=
		"\t\t" + '<div id="container">' + "\n" +
		"\t\t\t" + '<div id="header">' + "\n" +
		"\t\t\t\t" + '<div id="title"><a href="/"><img src="/omploader2.png" alt="omploader" /></a></div>'  + "\n" +
		"\t\t\t\t" + '<div id="slogan"><h1>' + Slogan + '™</h1></div>'  + "\n"
	if showsearch
		html_pre +=
			"\t\t\t\t" + '<form enctype="multipart/form-data" action="l" method="post">' + "\n" +
			"\t\t\t\t\t" + '<div id="search">' + "\n" +
			"\t\t\t\t\t\t" + '<input name="search_post" size="20" class="field" type="text" value="' + search.gsub(/\\/, '\\') + '" /><input value="search" class="button" type="submit" />' + "\n" +
			"\t\t\t\t\t" + '</div>' + "\n" +
			"\t\t\t\t" + '</form>' + "\n"
	end
	html_pre +=
		"\t\t\t" + '</div>' + "\n"
end

def html_post()
	html_post = ''
	html_post += "\t\t\t" + '<div id="footer">' + "\n" +
		"\t\t\t\t" + '<div class="right"><a href="https://addons.mozilla.org/en-US/firefox/addon/5638">firefox extension</a> <span class="separator">&#x2503;</span> <a href="https://chrome.google.com/extensions/detail/ofkoppnbjeilgpkghfcjaconpmnbpckk?hl=en">chrome extension</a></div>' + "\n" +
		"\t\t\t\t" + '<a href="irc://irc.freenode.net/##bikes">bikes</a> <span class="separator">&#x2503;</span> <a href="http://www.ruby-lang.org/">ruby</a> <span class="separator">&#x2503;</span> <a href="http://www.vim.org/">vim</a> <span class="separator">&#x2503;</span> <a href="http://git.omp.am/?p=omploader.git">git</a> <span class="separator">&#x2503;</span> <a href="about.html">about/faq</a> <span class="separator">&#x2503;</span> <a href="donate.html">donate</a>' + "\n" +
		"\t\t\t" + '</div>' + "\n" +
		"\t\t" + '</div>' + "\n"
	html_post +=
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
def get_visitor_id(cgi, db)
	query = db.prepare('insert into visitors (address) values (?) on duplicate key update last_visit = current_timestamp, id = last_insert_id(id)')
	stmt = query.execute(cgi.remote_addr.to_s)
	visitor_id = stmt.insert_id.to_s
	stmt.close
	return visitor_id
end

def run_cron(db)
	q = db.prepare('delete from votes where id in (select id from votes where unix_timestamp(date) < unix_timestamp(current_timestamp) - ? order by id) q')
	q.execute(Vote_expiry).close
	q = db.prepare('select address from visitors where unix_timestamp(last_visit) < unix_timestamp(current_timestamp) - ?')
	stmt = q.execute(Visitor_expiry)
	num_rows = stmt.num_rows
	num_rows.times do
		addr = stmt.fetch.to_s
		Cache.delete('visitor_id' + addr)
	end
	stmt.close
	q = db.prepare('delete from visitors where id in (select from visitors where unix_timestamp(last_visit) < unix_timestamp(current_timestamp) - ? order by id) q')
	q.execute(Visitor_expiry).close
	q = db.prepare('select metadata.id from metadata inner join thumbnails on metadata.thumbnail_id = thumbnails.id where unix_timestamp(thumbnails.last_accessed) < unix_timestamp(current_timestamp) - ?')
	stmt = q.execute(Thumbnail_expiry)
	num_rows = stmt.num_rows
	num_rows.times do
		id = stmt.fetch.to_s
		File.unlink(Paths['thumbnails'] + '/' + id.to_b64.get_subdir + '/' + id.to_b64) if File.exist?(Paths['thumbnails'] + '/' + id.to_b64.get_subdir + '/' + id.to_b64)
	end
	stmt.close
	q = db.prepare('update metadata inner join thumbnails on thumbnails.id = metadata.thumbnail_id set metadata.thumbnail_id = null where unix_timestamp(thumbnails.last_accessed) < unix_timestamp(current_timestamp) - ?')
	q.execute(Thumbnail_expiry).close
	q = db.prepare('delete from thumbnails where id in (select id from thumbnails where unix_timestamp(last_accessed) < unix_timestamp(current_timestamp) - ? order by id) q')
	q.execute(Thumbnail_expiry).close
	q = db.prepare('update metadata inner join owners on owners.id = metadata.owner_id set metadata.owner_id = null where unix_timestamp(owners.last_accessed) < unix_timestamp(current_timestamp) - ?')
	q.execute(Owner_expiry).close
	q = db.prepare('delete from owners where id in (select id from owners where unix_timestamp(last_accessed) < unix_timestamp(current_timestamp) - ? order by id) q')
	q.execute(Owner_expiry).close
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

def session_info(cgi)
	begin
		s = session(cgi, false)
		return [s['owner_id'].to_s, s.session_id.to_s]
	rescue ArgumentError
	end
end

def get_owner_id(cgi, db)
	begin
		# need to make new session
		s1 = session(cgi, false)
		s1.delete
	rescue ArgumentError
		# browser won't allow or doesn't support cookies
	end
	begin
		s2 = session(cgi, true)
		# this is a new owner
		query = db.prepare('delete from owners where session_id = ?')
		stmt = query.execute(s2.session_id.to_s)
		query = db.prepare('insert into owners (session_id) values (?)')
		stmt = query.execute(s2.session_id.to_s)
		owner_id = stmt.insert_id.to_s
		s2['owner_id'] = owner_id
		s2.close
		return [owner_id, s2.session_id.to_s]
	rescue ArgumentError
		# browser won't allow or doesn't support cookies
	end
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

	# Get data subdirectory from on b64 id.
	def get_subdir
		return self[0..1]
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

def get_cached_visitor_id(cgi, db)
	visitor_id = Cache.get('visitor_id' + cgi.remote_addr.to_s)
	if visitor_id.nil?
		db_check(db)
		visitor_id = get_visitor_id(cgi, db)
		Cache.set('visitor_id' + cgi.remote_addr.to_s,
				  Base64.encode64(Marshal.dump(visitor_id)),
				  Default_cache_expiry_long)
	else
		visitor_id = Marshal.load(Base64.decode64(visitor_id))
	end
	return visitor_id
end

def get_cached_owner_id(cgi, db)
	sinfo = session_info(cgi)
	return sinfo[0] unless sinfo.nil?
	db_check(db)
	sinfo = get_owner_id(cgi, db)
	return sinfo[0]
end

def to_readable_bytes(bytes)
	kibyte = 1024.0
	suffixes = ['Byte(s)', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB']
	index = 0
	while bytes > kibyte ** (index + 1) and index + 1 < suffixes.size
		index += 1
	end
	return '%.2f ' % (bytes / kibyte ** index) + suffixes[index]
end

