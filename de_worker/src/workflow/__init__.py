"""Workflows of the `de` task queue and their activity."""

from .run import RunWorkflow
from .train import TrainWorkflow

TASK_QUEUE = "de"

__all__ = ["TASK_QUEUE", "RunWorkflow", "TrainWorkflow"]
