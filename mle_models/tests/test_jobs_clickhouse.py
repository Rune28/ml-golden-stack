import struct

import numpy as np
import pytest

from jobs.clickhouse import parse_samples, write_predictions


def row_binary(idx: int, label: int, pixels: bytes) -> bytes:
    # varint length: 784 -> 0x90 0x06
    n, varint = len(pixels), b""
    while True:
        byte, n = n & 0x7F, n >> 7
        varint += bytes([byte | (0x80 if n else 0)])
        if not n:
            break
    return struct.pack("<IB", idx, label) + varint + pixels


def test_parse_samples_reads_fixed_width_rows():
    raw = row_binary(7, 3, bytes(range(256)) * 3 + bytes(16)) + row_binary(8, 9, bytes(784))

    idx, labels, images = parse_samples(raw)

    assert idx.tolist() == [7, 8] and labels.tolist() == [3, 9]
    assert images.shape == (2, 784) and images[0, 255] == 255 and not images[1].any()


def test_parse_samples_rejects_other_image_sizes():
    with pytest.raises(ValueError):
        parse_samples(row_binary(1, 1, bytes(100)))


class FakeClient:
    def __init__(self, rows=0):
        self.rows, self.deleted, self.inserted = rows, False, 0

    def query(self, sql, parameters):
        return type("Result", (), {"result_rows": [[self.rows]]})

    def command(self, sql, parameters):
        self.deleted, self.rows = True, 0

    def insert(self, table, data, column_names, column_oriented):
        self.inserted += len(data[0])
        self.rows += len(data[0])


def predictions(n=12):
    a = np.arange(n)
    return a.astype(np.uint32), (a % 10).astype(np.uint8), (a % 10).astype(np.uint8), np.ones(n, np.float32)


@pytest.mark.parametrize(
    "existing, deleted, inserted",
    [(0, False, 12), (12, False, 0), (5, True, 12)],
    ids=["new run", "complete run is kept", "partial run is rewritten"],
)
def test_write_predictions_is_idempotent_per_run(existing, deleted, inserted):
    client = FakeClient(rows=existing)

    write_predictions(client, "run-1", "3", *predictions())

    assert (client.deleted, client.inserted, client.rows) == (deleted, inserted, 12)
