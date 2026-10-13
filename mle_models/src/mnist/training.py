"""Training and inference on numpy arrays. Progress goes out through a
callback, so the caller decides where metrics are logged."""

from dataclasses import dataclass
from typing import Callable

import numpy as np
import torch
from torch import nn

from mnist.model import IMAGE_SIZE, MnistCnn, device


@dataclass(frozen=True)
class TrainConfig:
    epochs: int = 3
    batch_size: int = 128
    learning_rate: float = 1e-3
    seed: int = 0


def to_tensor(images: np.ndarray) -> torch.Tensor:
    """uint8 images, (N, 784) or (N, 28, 28) -> float (N, 1, 28, 28) in [0, 1].
    Copies: arrays from parse_idx are read-only views of the file bytes."""
    x = torch.from_numpy(np.array(images, dtype=np.uint8))
    return x.reshape(-1, 1, IMAGE_SIZE, IMAGE_SIZE).float().div_(255.0)


def train(
    images: np.ndarray,
    labels: np.ndarray,
    config: TrainConfig = TrainConfig(),
    on_epoch: Callable[[int, float], None] | None = None,
) -> MnistCnn:
    """Train a new model. `on_epoch(epoch, mean_loss)` is called after each epoch."""
    if len(images) != len(labels) or len(images) == 0:
        raise ValueError(f"need the same non-zero number of images and labels, got {len(images)} and {len(labels)}")

    torch.manual_seed(config.seed)
    dev = device()
    model = MnistCnn().to(dev)
    optimizer = torch.optim.Adam(model.parameters(), lr=config.learning_rate)
    loss_fn = nn.CrossEntropyLoss()

    x = to_tensor(images)
    y = torch.from_numpy(np.asarray(labels, dtype=np.int64))
    generator = torch.Generator().manual_seed(config.seed)

    model.train()
    for epoch in range(1, config.epochs + 1):
        order = torch.randperm(len(x), generator=generator)
        total_loss = 0.0
        for start in range(0, len(x), config.batch_size):
            batch = order[start : start + config.batch_size]
            xb, yb = x[batch].to(dev), y[batch].to(dev)
            optimizer.zero_grad()
            loss = loss_fn(model(xb), yb)
            loss.backward()
            optimizer.step()
            total_loss += loss.item() * len(batch)
        if on_epoch:
            on_epoch(epoch, total_loss / len(x))

    return model.cpu().eval()


@torch.no_grad()
def predict(
    model: Callable[[torch.Tensor], torch.Tensor], images: np.ndarray, batch_size: int = 1024
) -> tuple[np.ndarray, np.ndarray]:
    """Predicted digit (uint8) and its probability (float32) for every image.

    `model` is anything that maps images to logits: a MnistCnn from train()
    (already in eval mode) or a model loaded from MLflow, which is a
    torch.export graph without train/eval modes."""
    predicted, confidence = [], []
    for start in range(0, len(images), batch_size):
        probs = torch.softmax(model(to_tensor(images[start : start + batch_size])), dim=1)
        prob, digit = probs.max(dim=1)
        predicted.append(digit.numpy().astype(np.uint8))
        confidence.append(prob.numpy().astype(np.float32))
    return np.concatenate(predicted), np.concatenate(confidence)


def accuracy(predicted: np.ndarray, labels: np.ndarray) -> float:
    return float(np.mean(predicted == labels))
