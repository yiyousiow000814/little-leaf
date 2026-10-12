# Verification correction

The first check correctly found that independently writing float PCM into WAV and FLAC produced a one-step (1.1920929e-7) 24-bit quantization difference. The final renderer now derives WAV from the quantized FLAC master, so both lossless containers decode to exactly equal PCM. The strict equality assertion is retained and passes. The OGG, listening files, score, timbres and music were not changed by this correction.
