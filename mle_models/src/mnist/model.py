"""A small CNN: ~100k parameters, a few seconds per epoch on CPU for the full
60k MNIST train split, ~99% test accuracy after a few epochs."""

import torch
from torch import nn

IMAGE_SIZE = 28
NUM_CLASSES = 10


class MnistCnn(nn.Module):
    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 16, kernel_size=3, padding=1),  # 16 x 28 x 28
            nn.ReLU(),
            nn.MaxPool2d(2),  # 16 x 14 x 14
            nn.Conv2d(16, 32, kernel_size=3, padding=1),  # 32 x 14 x 14
            nn.ReLU(),
            nn.MaxPool2d(2),  # 32 x 7 x 7
        )
        self.classifier = nn.Sequential(
            nn.Flatten(),
            nn.Linear(32 * 7 * 7, 64),
            nn.ReLU(),
            nn.Linear(64, NUM_CLASSES),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """x: (N, 1, 28, 28) floats in [0, 1]. Returns logits (N, 10)."""
        return self.classifier(self.features(x))


def device() -> torch.device:
    """CUDA when there is a real GPU, CPU otherwise: the simulated `gpu` pool
    schedules the pod like a GPU one, but the code runs on CPU."""
    return torch.device("cuda" if torch.cuda.is_available() else "cpu")
