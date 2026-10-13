import gzip
import struct

import numpy as np
import torch

from mnist.idx import parse_idx
from mnist.model import MnistCnn
from mnist.training import TrainConfig, accuracy, predict, to_tensor, train


def synthetic(n: int, seed: int = 0) -> tuple[np.ndarray, np.ndarray]:
    """Digit k is a bright 4x4 square at a position that depends on k, plus noise:
    trivially learnable, so a few epochs on a few hundred images are enough."""
    rng = np.random.default_rng(seed)
    labels = rng.integers(0, 10, size=n).astype(np.uint8)
    images = rng.integers(0, 40, size=(n, 28, 28)).astype(np.uint8)
    for i, k in enumerate(labels):
        row, col = 2 + (k // 5) * 12, 2 + (k % 5) * 5
        images[i, row : row + 4, col : col + 4] = 255
    return images, labels


def test_parse_idx_reads_shape_and_data():
    data = np.arange(2 * 3 * 4, dtype=np.uint8).reshape(2, 3, 4)
    raw = b"\x00\x00\x08\x03" + struct.pack(">III", 2, 3, 4) + data.tobytes()

    assert np.array_equal(parse_idx(gzip.compress(raw)), data)


def test_to_tensor_accepts_flat_and_square_images():
    flat = np.full((2, 784), 255, dtype=np.uint8)

    x = to_tensor(flat)

    assert x.shape == (2, 1, 28, 28)
    assert torch.equal(x, to_tensor(flat.reshape(2, 28, 28)))
    assert x.max().item() == 1.0


def test_model_outputs_logits_for_ten_classes():
    assert MnistCnn()(torch.zeros(3, 1, 28, 28)).shape == (3, 10)


def test_train_learns_and_reports_every_epoch():
    images, labels = synthetic(400)
    losses = []

    model = train(images, labels, TrainConfig(epochs=4, batch_size=32), on_epoch=lambda e, loss: losses.append(loss))

    test_images, test_labels = synthetic(200, seed=1)
    predicted, confidence = predict(model, test_images)
    assert len(losses) == 4 and losses[-1] < losses[0]
    assert accuracy(predicted, test_labels) > 0.9
    assert predicted.dtype == np.uint8 and confidence.dtype == np.float32
    assert ((confidence > 0) & (confidence <= 1)).all()


def test_same_seed_same_model():
    images, labels = synthetic(100)
    config = TrainConfig(epochs=1, batch_size=32)

    a = train(images, labels, config)
    b = train(images, labels, config)

    assert all(torch.equal(p, q) for p, q in zip(a.state_dict().values(), b.state_dict().values()))


def test_digit_report_counts_recognized_and_actual_digits():
    from mnist.report import digit_report, most_biased

    labels = np.array([3, 3, 3, 8, 8, 1], dtype=np.uint8)
    predicted = np.array([3, 8, 8, 8, 8, 1], dtype=np.uint8)  # two 3s read as 8

    rows = digit_report(predicted, labels)

    assert len(rows) == 10 and rows[5].recognized == rows[5].actual == 0
    assert (rows[3].recognized, rows[3].actual) == (1, 3)
    assert (rows[8].recognized, rows[8].actual) == (4, 2)
    over, under = most_biased(rows)
    assert (over.digit, over.bias, under.digit, under.bias) == (8, 2, 3, -2)
