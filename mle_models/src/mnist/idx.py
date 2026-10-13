"""Reader of the IDX format the original MNIST files use."""

import gzip

import numpy as np


def parse_idx(raw: bytes) -> np.ndarray:
    """IDX: 2 zero bytes, a type byte (0x08 = uint8), the number of
    dimensions, the dimensions as big-endian uint32, then the data.
    Gzipped input is unpacked first."""
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    if raw[0] != 0 or raw[1] != 0 or raw[2] != 0x08:
        raise ValueError("not an IDX file of uint8")
    ndim = raw[3]
    shape = tuple(int(d) for d in np.frombuffer(raw, dtype=">u4", count=ndim, offset=4))
    return np.frombuffer(raw, dtype=np.uint8, offset=4 + 4 * ndim).reshape(shape)
