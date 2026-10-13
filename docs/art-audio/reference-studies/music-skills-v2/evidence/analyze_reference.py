#!/usr/bin/env python3
"""Read-only tempo evidence; not instrument recognition or a musical-quality grader.

Requires existing numpy, scipy, librosa and soundfile. No network or installations.
Example:
  python analyze_reference.py --input 'reference.mp3' --output result.json --repeat-search 32
The repeat search is explicitly supplied; it is not assumed for every recording.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
from scipy.signal import correlate, find_peaks
import librosa
import soundfile as sf


def analyze(path: Path, window_seconds: float, repeat_search: float | None) -> dict:
    info = sf.info(path)
    if not 2 <= info.duration <= 600:
        raise ValueError('Use a bounded 2-600 second excerpt and record its original offset.')
    y, sr = librosa.load(path, sr=22050, mono=True)
    if not np.isfinite(y).all() or np.max(np.abs(y)) < 1e-7:
        raise ValueError('Audio is non-finite or effectively silent; no tempo claim is possible.')
    hop = 220
    onset = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop)
    duration = len(y) / sr
    windows = []
    start = 0.0
    while start < duration:
        end = min(start + window_seconds, duration)
        if end - start >= 8:
            windows.append((start, end))
        start = end
    if len(windows) > 1:
        windows.append((0.0, duration))
    results = []
    for start, end in windows:
        env = onset[int(start*sr/hop):int(end*sr/hop)]
        tempo, beats = librosa.beat.beat_track(
            onset_envelope=env, sr=sr, hop_length=hop, units='time')
        ac = librosa.autocorrelate(env, max_size=int(2*sr/hop))
        peaks, _ = find_peaks(ac)
        candidates = [
            {'bpm':float(60*sr/(hop*k)), 'normalized_autocorrelation':float(ac[k]/ac[0])}
            for k in peaks if ac[0] > 0 and 45 <= 60*sr/(hop*k) <= 220
        ]
        candidates.sort(key=lambda item:item['normalized_autocorrelation'],reverse=True)
        results.append({'start_seconds':start,'end_seconds':end,
                        'tracker_grid_bpm':float(np.atleast_1d(tempo)[0]),
                        'beat_count':len(beats),'candidate_pulses':candidates[:8]})
    repeats = []
    if repeat_search is not None:
        template = y[sr:5*sr]
        for multiplier in (1,2,3):
            target = multiplier * repeat_search
            if target + 6.5 > duration:
                continue
            start = max(0.0,target-.5)
            segment = y[int(start*sr):int((target+6.5)*sr)]
            cc = correlate(segment,template,mode='valid',method='fft')
            lag = int(np.argmax(cc))
            repeats.append({'search_center_seconds':target,
                            'lag_seconds':start+lag/sr-1,
                            'template_correlation':float(np.corrcoef(template,segment[lag:lag+len(template)])[0,1])})
    return {'input_name':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'decoded_duration_seconds':duration,'source_rate':info.samplerate,'channels':info.channels,
            'librosa_version':librosa.__version__,'analysis_rate':sr,'hop_length':hop,
            'windows':results,'repeat_matches':repeats,
            'limits':['Grid BPM is quantized, not authored tempo. Check half/double time and phrase alignment.',
                      'Autocorrelation coefficients do not measure musical quality.',
                      'This script does not listen, identify exact instruments, transcribe a score or approve use.']}


def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--window-seconds',type=float,default=32)
    parser.add_argument('--repeat-search',type=float)
    args=parser.parse_args()
    if not args.input.is_file():parser.error('Input file does not exist.')
    if args.output.exists():parser.error('Output exists; select a new path to retain prior evidence.')
    if not 8 <= args.window_seconds <= 120:parser.error('Choose a window between 8 and 120 seconds.')
    if args.repeat_search is not None and args.repeat_search < 8:parser.error('Repeat-search must be at least 8 seconds.')
    try:
        result=analyze(args.input,args.window_seconds,args.repeat_search)
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    except (ValueError,RuntimeError,OSError) as exc:
        print(f'Analysis failed: {exc}',file=sys.stderr)
        return 1
    print(f"Saved {len(result['windows'])} tempo windows; no listening approval claimed.")
    return 0

if __name__=='__main__':
    raise SystemExit(main())
