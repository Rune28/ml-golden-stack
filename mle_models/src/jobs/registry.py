"""MLflow model registry: model `mnist-cnn`, the serving version carries the
alias `champion`. MLFLOW_TRACKING_URI comes from the environment."""

from mlflow import MlflowClient
from mlflow.exceptions import MlflowException

MODEL_NAME = "mnist-cnn"
CHAMPION = "champion"
EXPERIMENT = "mnist"


def champion() -> dict | None:
    """Version and test accuracy of the current champion, None before the first promote."""
    client = MlflowClient()
    try:
        version = client.get_model_version_by_alias(MODEL_NAME, CHAMPION)
    except MlflowException:
        return None
    run = client.get_run(version.run_id)
    return {"version": version.version, "accuracy": run.data.metrics.get("accuracy")}


def resolve(model: str) -> str:
    """'champion' (or any alias) or a version number -> version number."""
    if model.isdigit():
        return model
    return MlflowClient().get_model_version_by_alias(MODEL_NAME, model).version


def set_champion(version: str) -> None:
    MlflowClient().set_registered_model_alias(MODEL_NAME, CHAMPION, version)
