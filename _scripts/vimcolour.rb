#!/usr/bin/env ruby
#
# Copyright 2007 David Shakaryan <omp@gentoo.org>
# Distributed under the terms of the GNU General Public License v3
#
# TEMPORARILY PUTTING THIS HERE UNTIL I WRITE AN ACTUAL EBUILD FOR THIS PEE.
# TEMPORARILY PUTTING THIS HERE UNTIL I WRITE AN ACTUAL EBUILD FOR THIS PEE.
# TEMPORARILY PUTTING THIS HERE UNTIL I WRITE AN ACTUAL EBUILD FOR THIS PEE.

# Require any libraries that are used.
require 'mmap'
require 'tempfile'

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
