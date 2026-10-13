//! MLflow model registry over its REST API: versions of `mnist-cnn` with the
//! test accuracy and data size of the run that produced each.

use anyhow::Result;
use serde::{Deserialize, Serialize};

pub const MODEL_NAME: &str = "mnist-cnn";
const CHAMPION: &str = "champion";

#[derive(Serialize, Debug, PartialEq)]
pub struct ModelVersion {
    pub version: u32,
    pub accuracy: Option<f64>,
    pub train_samples: Option<u64>,
    pub created_at: u64,
    pub champion: bool,
}

pub struct Mlflow {
    url: String,
    http: reqwest::Client,
}

#[derive(Deserialize)]
struct VersionsResponse {
    #[serde(default)]
    model_versions: Vec<RawVersion>,
}

#[derive(Deserialize)]
struct RawVersion {
    version: String,
    run_id: String,
    creation_timestamp: u64,
}

/// Aliases are only on the registered model: the version search leaves them out.
#[derive(Deserialize)]
struct ModelResponse {
    registered_model: RegisteredModel,
}

#[derive(Deserialize)]
struct RegisteredModel {
    #[serde(default)]
    aliases: Vec<Alias>,
}

#[derive(Deserialize)]
struct Alias {
    alias: String,
    version: String,
}

#[derive(Deserialize)]
struct RunResponse {
    run: Run,
}

#[derive(Deserialize)]
struct Run {
    data: RunData,
}

#[derive(Deserialize, Default)]
struct RunData {
    #[serde(default)]
    metrics: Vec<KeyValue<f64>>,
    #[serde(default)]
    params: Vec<KeyValue<String>>,
}

#[derive(Deserialize)]
struct KeyValue<T> {
    key: String,
    value: T,
}

impl Mlflow {
    pub fn new(url: String) -> Self {
        Self { url: url.trim_end_matches('/').to_owned(), http: reqwest::Client::new() }
    }

    /// All versions, newest first. Empty before the first training.
    pub async fn versions(&self) -> Result<Vec<ModelVersion>> {
        let response: VersionsResponse = self
            .http
            .get(format!("{}/api/2.0/mlflow/model-versions/search", self.url))
            .query(&[("filter", format!("name='{MODEL_NAME}'")), ("max_results", "200".into())])
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;

        let champion = self.champion().await.unwrap_or_default();
        let mut versions = Vec::with_capacity(response.model_versions.len());
        for v in response.model_versions {
            let data = self.run_data(&v.run_id).await.unwrap_or_default();
            versions.push(ModelVersion {
                version: v.version.parse().unwrap_or_default(),
                accuracy: data.metrics.iter().find(|m| m.key == "accuracy").map(|m| m.value),
                train_samples: data.params.iter().find(|p| p.key == "train_samples").and_then(|p| p.value.parse().ok()),
                created_at: v.creation_timestamp / 1000,
                champion: champion.as_deref() == Some(v.version.as_str()),
            });
        }
        versions.sort_by_key(|v| std::cmp::Reverse(v.version));
        Ok(versions)
    }

    /// Version carrying the champion alias, None before the first promotion.
    async fn champion(&self) -> Result<Option<String>> {
        let response: ModelResponse = self
            .http
            .get(format!("{}/api/2.0/mlflow/registered-models/get", self.url))
            .query(&[("name", MODEL_NAME)])
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        Ok(response.registered_model.aliases.into_iter().find(|a| a.alias == CHAMPION).map(|a| a.version))
    }

    async fn run_data(&self, run_id: &str) -> Result<RunData> {
        let response: RunResponse = self
            .http
            .get(format!("{}/api/2.0/mlflow/runs/get", self.url))
            .query(&[("run_id", run_id)])
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        Ok(response.run.data)
    }
}
