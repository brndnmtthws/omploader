#!/usr/bin/env ruby
#
# Copyright 2007 David Shakaryan <omp@gentoo.org>
# Copyright 2007 Brenden Matthews <brenden@rty.ca>
#
# Distributed under the terms of the GNU General Public License v3

require 'base64'
require 'fcgi'
require 'cgi/session'
require 'cgi/session/pstore'
require 'mysql'
require 'yaml'

ConfigFile = YAML::load(File.open('config'))

Max_upload_count = ConfigFile['limits']['upload_count']
Max_upload_period = ConfigFile['limits']['upload_period']

def db_connect
  db_params = ConfigFile['database']
  db = Mysql.real_connect(db_params['host'], db_params['user'], db_params['pass'], db_params['name'])
  return db
end

def xhtml_pre(title = '')
  xhtml_pre = 
    '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">' + "\n" +
    '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">' + "\n" +
    '  <head>' + "\n" +
    '    <meta http-equiv="Content-Type" content="text/html;charset=utf-8" />' + "\n" +
    '    <link rel="stylesheet" type="text/css" href="_style.css" />' + "\n" +
    '    <link rel="shortcut icon" href="_omploader.ico" type="image/x-icon" />' + "\n" +
    '    <title>omploader' + title + '</title>' + "\n" +
    '  </head>' + "\n" +
    '  <body>' + "\n" +
    '    <div id="container">' + "\n" +
    '      <div id="header">' + "\n" +
    '      <div id="title"><a href="/"><img src="_omploader.png" alt="omploader" /></a></div>'  + "\n" +
    '        <form enctype="multipart/form-data" action="l" method="post">' + "\n" +
    '          <div id="search">' + "\n" +
    '            <input name="search_post" size="20" class="field" type="text" /><input value="search" class="button" type="submit" />' + "\n" +
    '          </div>' + "\n" +
    '        </form>' + "\n" +
    '      </div>' + "\n"
end

def xhtml_post
  xhtml_post =
    '      <div id="footer">an <a href="irc://irc.freenode.net/##otw">##otw</a> collaboration</div>' + "\n" +
    '    </div>' + "\n" +
    '  </body>' + "\n" +
    '</html>'
end

# Reconnect to database if connection is dropped.
def db_check(db)
  begin
    db.ping
  rescue Mysql::Error => e
    db = db_connect
  end
end

# Update visitors table in database.
def register_visit(cgi, db)
  query = db.prepare('insert into visitors (address) values (?) on duplicate key update last_visit = current_timestamp, id = last_insert_id(id)')
  visitor_id = query.execute(cgi.remote_addr.to_s).insert_id.to_s
  return visitor_id
end

def run_cron(db)
  q = db.prepare('call cron(?)')
  q.execute(Max_upload_period)
end

# Convert string to integer to Base36 to chomped Base64.
def to_b64(str)
  str = Base64.encode64(str.to_i.to_s(base=36)).chomp.gsub('=', '')
  return str
end

# Convert chomped Base64 to Base36 to integer to string.
def from_b64(str)
  while str.length % 4 > 0
    str += '='
  end

  str = Base64.decode64(str).to_i(base=36).to_s
  return str
end

def get_owner_id(cgi, db)
  session = CGI::Session.new(cgi,
    'database_manager' => CGI::Session::PStore,  # use PStore
    'session_key' => '_rb_sess_id',              # custom session key
    'prefix' => 'pstore_sid_',                   # PStore option
    'session_expires' => Time.now + 60*60*24*365,
    'session_path' => '/'
    )
  if session.new_session
    # this is a new owner
    query = db.prepare('insert into owners (session_id) values (?)')
    owner_id = query.execute(session.session_id.to_s).insert_id.to_s
    session['owner_id'] = owner_id
  else
    query = db.prepare('insert into owners (session_id) values (?) on duplicate key update session_id = ?, id = last_insert_id(id)')
    query.execute(session.session_id.to_s, session.session_id.to_s)
    owner_id = query.insert_id.to_s
  end
  session.close
  return owner_id
end

