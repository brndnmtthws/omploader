/*
  vorbisfile.c - part of ruby-vorbisfile

  Copyright (C) 2001 Rik Hemsley (rikkus) <rik@kde.org>

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to
  deal in the Software without restriction, including without limitation the
  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
  sell copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
  AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
  ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
  WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#include <stdio.h>
#include <ctype.h>
#include <string.h>

#include <ruby.h>
#include <rubysig.h>

#include <vorbis/codec.h>
#include <vorbis/vorbisfile.h>

#define LONG2FIX INT2FIX /* Ruby 1.6 :( */

static VALUE cOgg;
static VALUE cVorbisFile;

  static size_t
vf_fread(ptr, size, n, stream)
  void * ptr;
  size_t size;
  size_t n;
  void * stream;
{
  VALUE io  = (VALUE)stream;
  VALUE buf;
  VALUE count = INT2FIX(size * n);
  buf = rb_funcall3(io, rb_intern("read"), 1, &count);

  if (Qnil == buf)
  {
/*  fprintf(stderr, "io.read returned nil\n"); */
    return 0;
  }

/* fprintf(stderr, "io.read returned a buf of size %d\n", RSTRING(buf)->len); */

  memcpy(ptr, RSTRING(buf)->ptr, RSTRING(buf)->len);
  return RSTRING(buf)->len;
}

  static int
vf_fseek(stream, offset, whence)
  void    * stream; 
  int64_t   offset;
  int       whence;
{
  VALUE io  = (VALUE)stream;
  int   ret = 0;

  VALUE args[2];

  args[0] = LONG2FIX(offset);
  args[1] = INT2FIX(whence);

  ret = FIX2INT(rb_funcall3(io, rb_intern("seek"), 2, args));

/*fprintf(stderr, "io.seek(%d, %d) returned %d\n", offset, whence, ret);*/

  return ret;
}

  static int
vf_fclose(stream)
  void * stream; 
{
  VALUE io  = (VALUE)stream;
  (void) rb_funcall3(io, rb_intern("close"), 0, 0);
  return 1;
}

  static long
vf_ftell(stream)
  void * stream; 
{
  VALUE io  = (VALUE)stream;
  long ret = 0;
  ret = FIX2LONG(rb_funcall3(io, rb_intern("pos"), 0, 0));

/*fprintf(stderr, "io.pos == %d\n", ret);*/
  return ret;
}

  static void
vf_delete(vf)
  void * vf;
{
  ov_clear((OggVorbis_File *)vf);
  free(vf);
}

  static VALUE
vf_s_new(argc, argv, klass)
  int     argc;
  VALUE * argv;
  VALUE   klass;
{
  VALUE obj = Data_Wrap_Struct(klass, 0, vf_delete, 0);
  rb_obj_call_init(obj, argc, argv);
  return obj;
}

  static VALUE
vf_initialize(argc, argv, obj)
  int     argc;
  VALUE * argv;
  VALUE   obj;
{
  struct OggVorbis_File * vf = 0;

  vf = ALLOC(struct OggVorbis_File);
  DATA_PTR(obj) = vf;
  return obj;
}

  static VALUE
vf_open(obj, io)
  VALUE obj;
  VALUE io;
{
  OggVorbis_File * vf  = 0;
  ov_callbacks callbacks;

  Data_Get_Struct(obj, OggVorbis_File, vf);

  rb_iv_set(obj, "io", io);

  if (Qnil == io)
    return Qfalse;

  callbacks.read_func   = vf_fread;
  callbacks.seek_func   = vf_fseek;
  callbacks.close_func  = vf_fclose;
  callbacks.tell_func   = vf_ftell;

  if
    (
      ov_open_callbacks
      ((void *)io, vf, NULL, 0, callbacks) < 0
    )
  {
/*  fprintf(stderr, "ov_open_callbacks failed\n"); */
    return Qfalse;
  }

/*  fprintf(stderr, "ov_open_callbacks succeded\n"); */
  return Qtrue;
}

  static VALUE
vf_read(obj, str, count, big_endian, word_size, sgned)
  VALUE obj;
  VALUE str;
  VALUE count;
  VALUE big_endian;
  VALUE word_size;
  VALUE sgned;
{
  OggVorbis_File  * vf              = 0;
  char            * buf             = 0;
  long              bytes_read      = 0;
  int               vorbisSection   = 0;
  VALUE             ret;

  Data_Get_Struct(obj, OggVorbis_File, vf);

  Check_Type(str, T_STRING);

  rb_str_resize(str, count);

  buf = RSTRING(str)->ptr;

  bytes_read =
    ov_read
    (
      vf,
      buf,
      count,
      (Qtrue == big_endian) ? 1 : 0,
      NUM2INT(word_size),
      (Qtrue == sgned) ? 1 : 0,
      &vorbisSection
    );

  if (bytes_read > 0)
  {
    rb_str_resize(str, bytes_read);
    return INT2NUM(bytes_read);
  }
  else
  {
    rb_str_resize(str, 0);
    return Qnil;
  }
}

  static VALUE
vf_close(obj)
  VALUE obj;
{
  OggVorbis_File  * vf  = 0;
  Data_Get_Struct(obj, OggVorbis_File, vf);
/*  fprintf(stderr, "About to ov_clear %p\n", vf); */
  return INT2FIX(ov_clear(vf));
}

  static VALUE
vf_raw_seek(obj, pos)
  VALUE obj;
  VALUE pos;
{
  OggVorbis_File  * vf  = 0;
  Data_Get_Struct(obj, OggVorbis_File, vf);
  return INT2FIX(ov_raw_seek(vf, NUM2LONG(pos)));
}

  static VALUE
vf_pcm_seek(obj, pos, fast)
  VALUE obj;
  VALUE pos;
  VALUE fast;
{
  OggVorbis_File  * vf  = 0;

  Data_Get_Struct(obj, OggVorbis_File, vf);

  if (NUM2INT(fast))
    return INT2FIX(ov_pcm_seek_page(vf, NUM2LONG(pos)));
  else
    return INT2FIX(ov_pcm_seek(vf, NUM2LONG(pos)));
}

  static VALUE
vf_time_seek(obj, pos, fast)
  VALUE obj;
  VALUE pos;
  VALUE fast;
{
  OggVorbis_File  * vf  = 0;

  Data_Get_Struct(obj, OggVorbis_File, vf);

  if (NUM2INT(fast))
    return INT2FIX(ov_time_seek_page(vf, NUM2DBL(pos)));
  else
    return INT2FIX(ov_time_seek(vf, NUM2DBL(pos)));
}

  static VALUE
vf_raw_tell(obj, pos)
  VALUE obj;
  VALUE pos;
{
  OggVorbis_File  * vf  = 0;
  Data_Get_Struct(obj, OggVorbis_File, vf);
  return LONG2FIX(ov_raw_tell(vf));
}

  static VALUE
vf_pcm_tell(obj, pos)
  VALUE obj;
  VALUE pos;
{
  OggVorbis_File  * vf  = 0;
  Data_Get_Struct(obj, OggVorbis_File, vf);
  return LONG2FIX(ov_pcm_tell(vf));
}

  static VALUE
vf_time_tell(obj, pos)
  VALUE obj;
  VALUE pos;
{
  OggVorbis_File  * vf  = 0;
  Data_Get_Struct(obj, OggVorbis_File, vf);
  return rb_float_new(ov_time_tell(vf));
}

  static VALUE
vf_raw_total(obj, link)
  VALUE obj;
  VALUE link;
{
  OggVorbis_File  * vf  = 0;
  Data_Get_Struct(obj, OggVorbis_File, vf);
  return LONG2FIX(ov_raw_total(vf, NUM2INT(link)));
}

  static VALUE
vf_pcm_total(obj, link)
  VALUE obj;
  VALUE link;
{
  OggVorbis_File  * vf  = 0;
  Data_Get_Struct(obj, OggVorbis_File, vf);
  return LONG2FIX(ov_pcm_total(vf, NUM2INT(link)));
}

  static VALUE
vf_time_total(obj, link)
  VALUE obj;
  VALUE link;
{
  OggVorbis_File  * vf  = 0;
  Data_Get_Struct(obj, OggVorbis_File, vf);
  return rb_float_new(ov_time_total(vf, NUM2INT(link)));
}

  static VALUE
vf_channels(obj, link)
  VALUE obj;
  VALUE link;
{
  vorbis_info     * vi = 0;
  OggVorbis_File  * vf = 0;
  Data_Get_Struct(obj, OggVorbis_File, vf);
  vi = ov_info(vf, NUM2INT(link));
  return INT2FIX(vi->channels);
}

  static VALUE
vf_sample_rate(obj, link)
  VALUE obj;
  VALUE link;
{
  vorbis_info     * vi  = 0;
  OggVorbis_File  * vf  = 0;
  Data_Get_Struct(obj, OggVorbis_File, vf);
  vi = ov_info(vf, NUM2INT(link));
  return INT2FIX(vi->rate);
}

  static VALUE
vf_comments(obj, link)
  VALUE obj;
  VALUE link;
{
  vorbis_comment  * vc    = 0;
  OggVorbis_File  * vf    = 0;
  VALUE             hash  = rb_hash_new();
  char           ** ptr   = 0;
  VALUE             key;
  VALUE             value;

  Data_Get_Struct(obj, OggVorbis_File, vf);

  ptr = ov_comment(vf, NUM2INT(link))->user_comments;

  while (0 != *ptr)
  {
    char * s = *ptr;

    char * equals_pos = strchr(s, '=');

    if (0 != equals_pos)
    {
      /*
         Vorbis comment keys are latin-1 (or ascii ?) and case-insensitive,
         so let's do tolower() here. Why ? Well, otherwise people won't
         be able to look up values in the hash.
       */

      int i = 0;

      for (; i < equals_pos - s; i++)
        s[i] = tolower(s[i]);

      key   = rb_str_new(s, equals_pos - s);
      value = rb_str_new(equals_pos + 1, strlen(equals_pos + 1));

      rb_hash_aset(hash, key, value);
    }

    ++ptr;
  }

  return hash;
}

  static VALUE
vf_streams(obj)
  VALUE obj;
{
  OggVorbis_File  * vf  = 0;
  Data_Get_Struct(obj, OggVorbis_File, vf);
  return LONG2FIX(ov_streams(vf));
}

  static VALUE
vf_bitrate(obj, link)
  VALUE obj;
  VALUE link;
{
  OggVorbis_File  * vf  = 0;
  Data_Get_Struct(obj, OggVorbis_File, vf);
  return LONG2FIX(ov_bitrate(vf, NUM2INT(link)));
}

  static VALUE
vf_bitrate_i(obj)
  VALUE obj;
{
  OggVorbis_File  * vf  = 0;
  Data_Get_Struct(obj, OggVorbis_File, vf);

  return LONG2FIX(ov_bitrate_instant(vf));
}

  static VALUE
vf_seekable(obj)
  VALUE obj;
{
  OggVorbis_File  * vf  = 0;
  Data_Get_Struct(obj, OggVorbis_File, vf);

  return (1 == ov_seekable(vf)) ? Qtrue : Qfalse;
}

  static VALUE
vf_serial_number(obj, link)
  VALUE obj;
  VALUE link;
{
  OggVorbis_File  * vf  = 0;
  Data_Get_Struct(obj, OggVorbis_File, vf);

  return LONG2FIX(ov_serialnumber(vf, link));
}

  void
Init_vorbisfile()
{
  cOgg = rb_define_module("Ogg");

  cVorbisFile = rb_define_class_under(cOgg, "VorbisFile", rb_cObject);

  rb_define_singleton_method(cVorbisFile, "new",    vf_s_new,        -1);

  rb_define_method(cVorbisFile, "initialize",       vf_initialize,   -1);
  rb_define_method(cVorbisFile, "open",             vf_open,          1);
  rb_define_method(cVorbisFile, "read",             vf_read,          5);
  rb_define_method(cVorbisFile, "close",            vf_close,         0);
  rb_define_method(cVorbisFile, "raw_total",        vf_raw_total,     1);
  rb_define_method(cVorbisFile, "pcm_total",        vf_pcm_total,     1);
  rb_define_method(cVorbisFile, "time_total",       vf_time_total,    1);
  rb_define_method(cVorbisFile, "raw_seek",         vf_raw_seek,      2);
  rb_define_method(cVorbisFile, "pcm_seek",         vf_pcm_seek,      2);
  rb_define_method(cVorbisFile, "time_seek",        vf_time_seek,     2);
  rb_define_method(cVorbisFile, "raw_tell",         vf_raw_tell,      1);
  rb_define_method(cVorbisFile, "pcm_tell",         vf_pcm_tell,      1);
  rb_define_method(cVorbisFile, "time_tell",        vf_time_tell,     1);
  rb_define_method(cVorbisFile, "channels",         vf_channels,      1);
  rb_define_method(cVorbisFile, "sample_rate",      vf_sample_rate,   1);
  rb_define_method(cVorbisFile, "comments",         vf_comments,      1);
  rb_define_method(cVorbisFile, "streams",          vf_streams,       0);
  rb_define_method(cVorbisFile, "bitrate",          vf_bitrate,       1);
  rb_define_method(cVorbisFile, "bitrate_instant",  vf_bitrate_i,     0);
  rb_define_method(cVorbisFile, "seekable",         vf_seekable,      0);
  rb_define_method(cVorbisFile, "serial_number",    vf_serial_number, 1);
}

