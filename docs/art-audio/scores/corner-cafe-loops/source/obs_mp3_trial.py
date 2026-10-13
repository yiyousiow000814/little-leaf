"""Listening-only MP3 conversion using the FFmpeg/LAME DLLs already installed by OBS.

No audio filters, resampling, remapping, gain, tempo, or trim operations.
Public ABI declarations follow FFmpeg n8.1.2 headers (frame.h, codec_par.h,
packet.h, avformat.h). Only library-allocated objects are used.
"""
from pathlib import Path
import array
import ctypes as C
import hashlib
import json
import math
import os
import struct

ROOT = Path(__file__).resolve().parent
BIN = Path(r'C:\Program Files\obs-studio\bin\64bit')
dll_directory = os.add_dll_directory(str(BIN))
u = C.CDLL(str(BIN/'avutil-60.dll'))
c = C.CDLL(str(BIN/'avcodec-62.dll'))
f = C.CDLL(str(BIN/'avformat-62.dll'))
P, I, U, I64 = C.c_void_p, C.c_int, C.c_uint, C.c_int64

class Rational(C.Structure):
    _fields_ = [('num', I), ('den', I)]
class LayoutUnion(C.Union):
    _fields_ = [('mask', C.c_uint64), ('map', P)]
class Layout(C.Structure):
    _fields_ = [('order', I), ('nb_channels', I), ('u', LayoutUnion), ('opaque', P)]
class Parameters(C.Structure):
    _fields_ = [('codec_type', I), ('codec_id', I), ('codec_tag', U), ('extradata', P),
        ('extradata_size', I), ('coded_side_data', P), ('nb_coded_side_data', I),
        ('format', I), ('bit_rate', I64), ('bits_per_coded_sample', I), ('bits_per_raw_sample', I),
        ('profile', I), ('level', I), ('width', I), ('height', I),
        ('sample_aspect_ratio', Rational), ('framerate', Rational), ('field_order', I),
        ('color_range', I), ('color_primaries', I), ('color_trc', I), ('color_space', I),
        ('chroma_location', I), ('video_delay', I), ('ch_layout', Layout),
        ('sample_rate', I), ('block_align', I), ('frame_size', I), ('initial_padding', I),
        ('trailing_padding', I), ('seek_preroll', I), ('alpha_mode', I)]
class Packet(C.Structure):
    _fields_ = [('buf', P), ('pts', I64), ('dts', I64), ('data', P), ('size', I),
        ('stream_index', I), ('flags', I), ('side_data', P), ('side_data_elems', I),
        ('duration', I64), ('pos', I64), ('opaque', P), ('opaque_ref', P), ('time_base', Rational)]
class Frame(C.Structure):
    _fields_ = [('data', P*8), ('linesize', I*8), ('extended_data', P),
        ('width', I), ('height', I), ('nb_samples', I), ('format', I), ('pict_type', I),
        ('sample_aspect_ratio', Rational), ('pts', I64), ('pkt_dts', I64), ('time_base', Rational),
        ('quality', I), ('opaque', P), ('repeat_pict', I), ('sample_rate', I), ('buf', P*8),
        ('extended_buf', P), ('nb_extended_buf', I), ('side_data', P), ('nb_side_data', I),
        ('flags', I), ('color_range', I), ('color_primaries', I), ('color_trc', I), ('colorspace', I),
        ('chroma_location', I), ('best_effort_timestamp', I64), ('metadata', P),
        ('decode_error_flags', I), ('hw_frames_ctx', P), ('opaque_ref', P),
        ('crop_top', C.c_size_t), ('crop_bottom', C.c_size_t), ('crop_left', C.c_size_t),
        ('crop_right', C.c_size_t), ('private_ref', P), ('ch_layout', Layout), ('duration', I64), ('alpha_mode', I)]
class Stream(C.Structure):
    # Prefix only: fields after duration are never accessed.
    _fields_ = [('av_class', P), ('index', I), ('id', I), ('codecpar', C.POINTER(Parameters)),
        ('priv_data', P), ('time_base', Rational), ('start_time', I64), ('duration', I64)]
class Format(C.Structure):
    # Prefix only; avformat allocates the full native object.
    _fields_ = [('av_class', P), ('iformat', P), ('oformat', P), ('priv_data', P),
        ('pb', P), ('ctx_flags', I), ('nb_streams', U), ('streams', C.POINTER(C.POINTER(Stream)))]

def bind(lib, name, result, args):
    fn = getattr(lib, name)
    fn.restype, fn.argtypes = result, args
    return fn

version = bind(u, 'av_version_info', C.c_char_p, [])().decode()
assert version == 'n8.1.2', 'Recheck public ABI before another library version'
bind(u, 'av_strerror', I, [I, P, C.c_size_t])
bind(u, 'av_get_sample_fmt', I, [C.c_char_p])
bind(u, 'av_channel_layout_default', None, [C.POINTER(Layout), I])
bind(u, 'av_opt_set', I, [P, C.c_char_p, C.c_char_p, I])
bind(u, 'av_frame_alloc', C.POINTER(Frame), [])
bind(u, 'av_frame_get_buffer', I, [C.POINTER(Frame), I])
bind(u, 'av_frame_make_writable', I, [C.POINTER(Frame)])
bind(u, 'av_frame_unref', None, [C.POINTER(Frame)])
bind(u, 'av_frame_free', None, [C.POINTER(C.POINTER(Frame))])
bind(c, 'avcodec_configuration', C.c_char_p, [])
bind(c, 'avcodec_find_encoder_by_name', P, [C.c_char_p])
bind(c, 'avcodec_find_decoder_by_name', P, [C.c_char_p])
bind(c, 'avcodec_alloc_context3', P, [P])
bind(c, 'avcodec_free_context', None, [C.POINTER(P)])
bind(c, 'avcodec_parameters_alloc', C.POINTER(Parameters), [])
bind(c, 'avcodec_parameters_free', None, [C.POINTER(C.POINTER(Parameters))])
bind(c, 'avcodec_parameters_from_context', I, [C.POINTER(Parameters), P])
bind(c, 'avcodec_parameters_to_context', I, [P, C.POINTER(Parameters)])
bind(c, 'avcodec_open2', I, [P, P, C.POINTER(P)])
bind(c, 'avcodec_send_frame', I, [P, C.POINTER(Frame)])
bind(c, 'avcodec_receive_packet', I, [P, C.POINTER(Packet)])
bind(c, 'avcodec_send_packet', I, [P, C.POINTER(Packet)])
bind(c, 'avcodec_receive_frame', I, [P, C.POINTER(Frame)])
bind(c, 'av_packet_alloc', C.POINTER(Packet), [])
bind(c, 'av_packet_unref', None, [C.POINTER(Packet)])
bind(c, 'av_packet_free', None, [C.POINTER(C.POINTER(Packet))])
bind(c, 'av_packet_rescale_ts', None, [C.POINTER(Packet), Rational, Rational])
bind(f, 'avformat_alloc_output_context2', I, [C.POINTER(C.POINTER(Format)), P, C.c_char_p, C.c_char_p])
bind(f, 'avformat_new_stream', C.POINTER(Stream), [C.POINTER(Format), P])
bind(f, 'avio_open', I, [C.POINTER(P), C.c_char_p, I])
bind(f, 'avio_closep', I, [C.POINTER(P)])
bind(f, 'avformat_write_header', I, [C.POINTER(Format), C.POINTER(P)])
bind(f, 'av_interleaved_write_frame', I, [C.POINTER(Format), C.POINTER(Packet)])
bind(f, 'av_write_trailer', I, [C.POINTER(Format)])
bind(f, 'avformat_free_context', None, [C.POINTER(Format)])
bind(f, 'avformat_open_input', I, [C.POINTER(C.POINTER(Format)), C.c_char_p, P, C.POINTER(P)])
bind(f, 'avformat_find_stream_info', I, [C.POINTER(Format), C.POINTER(P)])
bind(f, 'av_read_frame', I, [C.POINTER(Format), C.POINTER(Packet)])
bind(f, 'avformat_close_input', None, [C.POINTER(C.POINTER(Format))])
FLTP = u.av_get_sample_fmt(b'fltp')
EOF, AGAIN = -541478725, -11

def check(code, label):
    if code < 0:
        message = C.create_string_buffer(256)
        u.av_strerror(code, message, len(message))
        raise RuntimeError(label+': '+message.value.decode())
    return code

def load_wav(path):
    data = path.read_bytes()
    assert data[:4] == b'RIFF' and data[8:12] == b'WAVE'
    pos, chunks = 12, {}
    while pos + 8 <= len(data):
        size = struct.unpack_from('<I', data, pos+4)[0]
        chunks[data[pos:pos+4]] = data[pos+8:pos+8+size]
        pos += 8 + size + size % 2
    assert struct.unpack_from('<HHIIHH', chunks[b'fmt ']) == (3, 2, 48000, 384000, 8, 32)
    samples = array.array('f', chunks[b'data'])
    return [samples[0::2], samples[1::2]]

def encode(planes, target):
    assert not target.exists(), 'Refusing to replace an existing derivative'
    codec = c.avcodec_find_encoder_by_name(b'libmp3lame')
    assert codec
    context = P(c.avcodec_alloc_context3(codec))
    params = c.avcodec_parameters_alloc()
    check(c.avcodec_parameters_from_context(params, context), 'encoder parameters')
    params.contents.format = FLTP
    params.contents.bit_rate = 320000
    params.contents.sample_rate = 48000
    u.av_channel_layout_default(C.byref(params.contents.ch_layout), 2)
    check(c.avcodec_parameters_to_context(context, params), 'configure encoder')
    check(u.av_opt_set(context, b'time_base', b'1/48000', 0), 'encoder time base')
    check(c.avcodec_open2(context, codec, None), 'open LAME encoder')
    check(c.avcodec_parameters_from_context(params, context), 'opened encoder parameters')
    frame_size = params.contents.frame_size
    assert frame_size == 1152 and params.contents.format == FLTP
    output = C.POINTER(Format)()
    check(f.avformat_alloc_output_context2(C.byref(output), None, b'mp3', str(target).encode()), 'MP3 muxer')
    stream = f.avformat_new_stream(output, None)
    assert stream
    check(c.avcodec_parameters_from_context(stream.contents.codecpar, context), 'MP3 stream parameters')
    stream.contents.time_base = Rational(1, 48000)
    io = P()
    check(f.avio_open(C.byref(io), str(target).encode(), 2), 'open derivative file')
    output.contents.pb = io
    check(f.avformat_write_header(output, None), 'MP3 header')
    frame, packet = u.av_frame_alloc(), c.av_packet_alloc()
    frame.contents.nb_samples, frame.contents.format, frame.contents.sample_rate = frame_size, FLTP, 48000
    u.av_channel_layout_default(C.byref(frame.contents.ch_layout), 2)
    check(u.av_frame_get_buffer(frame, 0), 'allocate audio frame')
    def drain():
        while True:
            status = c.avcodec_receive_packet(context, packet)
            if status in (AGAIN, EOF):
                return
            check(status, 'encode MP3 packet')
            packet.contents.stream_index = stream.contents.index
            c.av_packet_rescale_ts(packet, Rational(1, 48000), stream.contents.time_base)
            check(f.av_interleaved_write_frame(output, packet), 'write MP3 packet')
            c.av_packet_unref(packet)
    for offset in range(0, len(planes[0]), frame_size):
        count = min(frame_size, len(planes[0])-offset)
        frame.contents.nb_samples, frame.contents.pts = count, offset
        check(u.av_frame_make_writable(frame), 'writable audio frame')
        for channel in range(2):
            C.memmove(frame.contents.data[channel], planes[channel].buffer_info()[0]+offset*4, count*4)
        check(c.avcodec_send_frame(context, frame), 'submit unchanged source samples')
        drain()
    check(c.avcodec_send_frame(context, None), 'flush LAME')
    drain()
    check(f.av_write_trailer(output), 'finalize MP3 gapless metadata')
    check(f.avio_closep(C.byref(io)), 'close MP3')
    u.av_frame_free(C.byref(frame)); c.av_packet_free(C.byref(packet))
    c.avcodec_parameters_free(C.byref(params)); c.avcodec_free_context(C.byref(context))
    f.avformat_free_context(output)

def decode(target):
    source = C.POINTER(Format)()
    check(f.avformat_open_input(C.byref(source), str(target).encode(), None, None), 'open encoded MP3')
    check(f.avformat_find_stream_info(source, None), 'read MP3 stream info')
    assert source.contents.nb_streams == 1
    stream = source.contents.streams[0]
    assert stream.contents.codecpar.contents.sample_rate == 48000
    assert stream.contents.codecpar.contents.ch_layout.nb_channels == 2
    codec = c.avcodec_find_decoder_by_name(b'mp3float')
    assert codec
    context = P(c.avcodec_alloc_context3(codec))
    check(c.avcodec_parameters_to_context(context, stream.contents.codecpar), 'decoder parameters')
    check(c.avcodec_open2(context, codec, None), 'open MP3 decoder')
    frame, packet = u.av_frame_alloc(), c.av_packet_alloc()
    planes = [array.array('f'), array.array('f')]
    def drain():
        while True:
            status = c.avcodec_receive_frame(context, frame)
            if status in (AGAIN, EOF):
                return
            check(status, 'decode MP3 frame')
            assert frame.contents.format == FLTP and frame.contents.sample_rate == 48000
            assert frame.contents.ch_layout.nb_channels == 2
            for channel in range(2):
                planes[channel].frombytes(C.string_at(frame.contents.data[channel], frame.contents.nb_samples*4))
            u.av_frame_unref(frame)
    while True:
        status = f.av_read_frame(source, packet)
        if status == EOF:
            break
        check(status, 'read MP3 packet')
        check(c.avcodec_send_packet(context, packet), 'submit MP3 packet')
        c.av_packet_unref(packet)
        drain()
    check(c.avcodec_send_packet(context, None), 'flush MP3 decoder')
    drain()
    u.av_frame_free(C.byref(frame)); c.av_packet_free(C.byref(packet))
    c.avcodec_free_context(C.byref(context)); f.avformat_close_input(C.byref(source))
    return planes

