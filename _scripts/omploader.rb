#!/usr/bin/env ruby
#
# $Id$
#
# Copyright 2007 David Shakaryan <omp@gentoo.org>
# Copyright 2007 Brenden Matthews <brenden@rty.ca>
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

ConfigFile = YAML::load(File.open('config'))

Max_upload_count = ConfigFile['limits']['upload_count']
Max_upload_period = ConfigFile['limits']['upload_period'] * 60

Sql = Mysql.init

def db_connect
  db_params = ConfigFile['database']
  db = Sql.real_connect(db_params['host'], db_params['user'], db_params['pass'], db_params['name'])
  query = db.prepare('set time_zone = ?')
  query.execute(db_params['timezone'])
  db.autocommit(false)
  return db
end

def xhtml_pre(title = '')
  xhtml_pre = 
    '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">' + "\n" +
    '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">' + "\n" +
    '  <head>' + "\n" +
    '    <meta http-equiv="Content-Type" content="text/html;charset=utf-8" />' + "\n" +
    '    <link rel="stylesheet" type="text/css" href="_style.css" />' + "\n" +
    '    <link rel="shortcut icon" href="_omploader_icon.png" type="image/x-icon" />' + "\n" +
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
    '      <div id="footer">' + "\n" +
    '        <div class="right"><a href="omploader.xpi">firefox extension</a></div>' + "\n" +
    '        <a href="irc://irc.freenode.net/##otw">otw</a> &#x2503; <a href="http://www.ruby-lang.org/">ruby</a> &#x2503; <a href="http://www.vim.org/">vim</a> &#x2503; <a href="http://svn.omploader.org/">svn</a>' + "\n" + 
    '      </div>' + "\n" +
    '    </div>' + "\n" +
    '  </body>' + "\n" +
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
  visitor_id = query.execute(cgi.remote_addr.to_s).insert_id.to_s
  return visitor_id
end

def run_cron(db)
  q = db.prepare('call cron(?)')
  q.execute(Max_upload_period)
end

def session(cgi, new)
  session = CGI::Session.new(cgi,
    'database_manager' => CGI::Session::PStore,  # use PStore
    'session_key' => '_rb_sess_id',              # custom session key
    'prefix' => 'pstore_sid_',                   # PStore option
    'session_expires' => Time.now + 60*60*24*365,
    'session_path' => '/',
    'new_session' => new
    )
end

def get_owner_id(cgi, db)
  begin
    s = session(cgi, false)
    query = db.prepare('insert into owners (session_id) values (?) on duplicate key update session_id = ?, id = last_insert_id(id)')
    query.execute(s.session_id.to_s, s.session_id.to_s)
    owner_id = query.insert_id.to_s
  rescue ArgumentError
    # need to make new session
    s = session(cgi, true)
    s.close
    begin
      s = session(cgi, false)
      # this is a new owner
      query = db.prepare('insert into owners (session_id) values (?)')
      owner_id = query.execute(s.session_id.to_s).insert_id.to_s
      s['owner_id'] = owner_id
    rescue ArgumentError
      # browser won't allow or doesn't support cookies
    end
  end
  return owner_id
end

class String
  # Convert string to integer to Base36 to chomped Base64.
  def to_b64
    Base64.encode64(self.to_i.to_s(base=36)).chomp.gsub('=', '')
  end
  
  # Convert chomped Base64 to Base36 to integer to string.
  def to_id
    str = self
    while str.length % 4 > 0
      str += '='
    end
    Base64.decode64(str).to_i(base=36).to_s
  end

  # Sanitise HTML code to avoid opening tags.
  def sanitise
    self.gsub('<', '&lt;').gsub('>', '&gt;')
  end
end

# Method for using Vim's syntax highlighting and improving the generated code.
def vimcolour(datum, filetype, title)
  # Store the datum in a temporary file for Vim to open.
  tempfile = Tempfile.new('vimcolour')
  tempfile.close

  # Map the temporary file into memory to avoid unnecessarily using the hard
  # disk.
  mmap = Mmap.new(tempfile.path, 'rw')
  mmap.insert(0, datum)

  # Set terminal colours to 88 to allow us to use the Inkpot theme.
  # The bdelete command is to delete the first buffer, so the generated HTML
  # does not have to be saved to a different file.
  %x{vim -n -e                    \
    -c 'set t_Co=88'              \
    -c 'set filetype=#{filetype}' \
    -c 'syntax on'                \
    -c 'set number'               \
    -c 'colorscheme inkpot'       \
    -c 'let html_use_css = 1'     \
    -c 'let use_xhtml = 1'        \
    -c 'run syntax/2html.vim'     \
    -c 'bdelete 1'                \
    -c 'wq! #{tempfile.path}'     \
    #{tempfile.path}              }

  # Read the temporary file and split it into three parts, splitting from the
  # first <pre> tag and the last </pre> tag. This creates an array consisting
  # of the pre-code HTML, the code HTML, and the post-code HTML.
  datum = File.read(tempfile.path)
  datum = datum.split(/<pre>\n/, 2)
  datum = [ datum[0],
    datum[1].reverse.split(/\n>erp\/</, 2)[1].reverse,
    datum[1].reverse.split(/\n>erp\/</, 2)[0].reverse]

  # Remove the XML declaration so that the datum is seen as HTML rather than
  # XML. Modify the pre-code HTML to change the title, as well as improve the
  # CSS code. Create a container division to ensure proper displaying of the
  # line numbers.
  datum[0].sub!(/^<\?xml.*\?>$\n/, '')
  datum[0].sub!(/^(<title>).*(<\/title>)/, "\\1#{title} (VimColour)\\2")
  datum[0].sub!(/^(pre \{).*;/, '\1 margin: 0;')
  datum[0].sub!(/^(body \{.*background-color: #)....../,
    '\1000000; margin: 0; font-size: 1.2em')
  datum[0].sub!(/^\.lnr( \{.*;)/,
    "div#container { display: table-row; }\n" +
    "div#ln\\1 }\ndiv#ln, div#code { display: table-cell;")
  datum[0].gsub!(/ text-decoration: underline;/, '')
  datum[0] += "<div id=\"container\">\n"

  # Modify the main HTML to separate the number lines and the actual code into
  # separate divisions. This allows for aligning them next to each other via
  # the CSS table-cell display property, while still allowing one to select
  # the code while not selecting the numbers.
  ln   = "<div id=\"ln\">\n"
  code = "<div id=\"code\">\n<pre>\n"
  datum[1] = datum[1].each_line { |str|
    if str =~ /^<span class="lnr">( *\d+ )<\/span>/
      ln   += $1.gsub(' ', '&nbsp;') + "<br />\n"
      code += str.gsub(/^<span class="lnr"> *\d+ <\/span>/, '')
    end
  }
  ln   += "</div>\n"
  code += "</pre>\n</div>\n"
  datum[1] = ln + code

  # Close the container division.
  datum[2] = "</div>\n" + datum[2]

  # Return the modified datum as a string.
  return datum.join
end
