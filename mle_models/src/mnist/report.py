"""What the recognized digits add up to: the distribution of the model's
answers next to the true one. Pure: arrays in, rows out."""

from dataclasses import dataclass

import numpy as np

from mnist.model import NUM_CLASSES


@dataclass(frozen=True)
class DigitCount:
    digit: int
    recognized: int
    actual: int

    @property
    def bias(self) -> int:
        """Positive: the model sees this digit more often than it is there."""
        return self.recognized - self.actual


def digit_report(predicted: np.ndarray, labels: np.ndarray) -> list[DigitCount]:
    """One row per digit 0-9, digits never seen included."""
    if len(predicted) != len(labels):
        raise ValueError(f"{len(predicted)} predictions for {len(labels)} labels")
    recognized = np.bincount(predicted.astype(np.int64), minlength=NUM_CLASSES)
    actual = np.bincount(labels.astype(np.int64), minlength=NUM_CLASSES)
    return [DigitCount(d, int(recognized[d]), int(actual[d])) for d in range(NUM_CLASSES)]


def most_biased(report: list[DigitCount]) -> tuple[DigitCount, DigitCount]:
    """The most over-recognized and the most under-recognized digit."""
    return max(report, key=lambda r: r.bias), min(report, key=lambda r: r.bias)
