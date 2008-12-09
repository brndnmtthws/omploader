require 'mkmf'

exit 1 unless have_library("vorbis",      "vorbis_analysis")
exit 1 unless have_library("vorbisfile",  "ov_open_callbacks")

exit 1 unless have_header("vorbis/codec.h")
exit 1 unless have_header("vorbis/vorbisfile.h")

create_makefile("vorbisfile")
