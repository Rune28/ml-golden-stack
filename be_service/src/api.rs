//! HTTP API for the pipeline page.

use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{Html, IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tokio::sync::Mutex;

use crate::ingest::{self, IngestError, IngestResult, TEST_BATCH_ID};
use crate::mlflow::{Mlflow, ModelVersion};
use crate::mnist::{Source, SplitKind};
use crate::store::{Batch, ClickHouse, ConfusionCell, DigitAccuracy, PredictionRun, Stats};
use crate::temporal::{Pipeline, StartError, Started, Status, Temporal};

/// Upper bound of one Add data: the whole MNIST train split.
const MAX_BATCH: u64 = 60_000;

pub struct AppState {
    pub store: ClickHouse,
    pub mnist: Source,
    pub temporal: Temporal,
    pub mlflow: Mlflow,
    /// Add data reads the offset, then writes: two at once would take the
    /// same examples. Enough while be_service runs one replica.
    pub ingest_lock: Mutex<()>,
}

pub fn router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/", get(|| async { Html(include_str!("../static/index.html")) }))
        .route("/api/batches", post(add_data))
        .route("/api/train", post(train))
        .route("/api/run", post(run))
        .route("/api/stats", get(stats))
        .route("/api/state", get(page_state))
        .route("/api/runs/{run_id}/examples", get(examples))
        .route("/api/runs/{run_id}/confusion", get(confusion))
        .route("/healthz", get(|| async { "ok" }))
        .with_state(state)
}

#[derive(Deserialize)]
struct AddData {
    count: u64,
    /// Optional: a client that retries a request sends the same id and
    /// gets the same batch instead of a second one.
    batch_id: Option<String>,
}

async fn add_data(
    State(state): State<Arc<AppState>>,
    Json(req): Json<AddData>,
) -> Result<Json<IngestResult>, ApiError> {
    if !(1..=MAX_BATCH).contains(&req.count) {
        return Err(ApiError::BadRequest(format!("count must be between 1 and {MAX_BATCH}")));
    }
    let batch_id = match req.batch_id {
        Some(id) => validate_batch_id(id)?,
        // v7 is ordered by time, so new batches go to the end of the
        // ORDER BY (batch_id, idx) key.
        None => uuid::Uuid::now_v7().to_string(),
    };

    let _guard = state.ingest_lock.lock().await;
    let train = state.mnist.split(SplitKind::Train).await?;
    let test = state.mnist.split(SplitKind::Test).await?;
    let result = ingest::ingest(&state.store, &train, &test, &batch_id, req.count).await?;
    tracing::info!(batch_id = %result.batch_id, added = result.added, train_total = result.train_total, "batch added");
    Ok(Json(result))
}

async fn stats(State(state): State<Arc<AppState>>) -> Result<Json<Stats>, ApiError> {
    Ok(Json(state.store.stats().await?))
}

#[derive(Deserialize)]
struct TrainRequest {
    #[serde(default = "default_pool")]
    pool: String,
    #[serde(default = "default_epochs")]
    epochs: u32,
}

fn default_pool() -> String {
    "gpu".into()
}

fn default_epochs() -> u32 {
    3
}

/// Starts the Train workflow. The run_id is generated here, like batch_id:
/// it names the Jobs, the MLflow run and the result objects.
async fn train(State(state): State<Arc<AppState>>, Json(req): Json<TrainRequest>) -> Result<Json<Started>, ApiError> {
    if !["cpu", "gpu"].contains(&req.pool.as_str()) || !(1..=20).contains(&req.epochs) {
        return Err(ApiError::BadRequest("pool: cpu or gpu, epochs: 1-20".into()));
    }
    let input = json!({ "run_id": uuid::Uuid::now_v7().to_string(), "pool": req.pool, "epochs": req.epochs });
    start(&state, Pipeline::Train, input).await
}

#[derive(Deserialize)]
struct RunRequest {
    #[serde(default = "default_model")]
    model: String,
}

fn default_model() -> String {
    "champion".into()
}

async fn run(State(state): State<Arc<AppState>>, Json(req): Json<RunRequest>) -> Result<Json<Started>, ApiError> {
    let model_ok = !req.model.is_empty() && req.model.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-');
    if !model_ok {
        return Err(ApiError::BadRequest("model: a version number or an alias".into()));
    }
    let input = json!({ "run_id": uuid::Uuid::now_v7().to_string(), "model": req.model, "pool": "cpu" });
    start(&state, Pipeline::Run, input).await
}

async fn start(state: &AppState, pipeline: Pipeline, input: Value) -> Result<Json<Started>, ApiError> {
    match state.temporal.start(pipeline, input).await {
        Ok(started) => {
            tracing::info!(workflow_id = %started.workflow_id, run_id = %started.run_id, "workflow started");
            Ok(Json(started))
        }
        Err(StartError::AlreadyRunning) => {
            Err(ApiError::Conflict(format!("{} is already running", pipeline.workflow_type())))
        }
        Err(StartError::Other(e)) => Err(ApiError::Internal(e)),
    }
}

#[derive(Deserialize)]
struct ExamplesQuery {
    #[serde(default)]
    mistakes: bool,
    #[serde(default = "default_examples")]
    limit: u64,
}

fn default_examples() -> u64 {
    24
}

#[derive(Serialize)]
struct ExampleView {
    idx: u32,
    label: u8,
    predicted: u8,
    confidence: f32,
    /// 784 grayscale bytes, base64: ~1 KB per image instead of ~3 KB of JSON numbers.
    pixels: String,
}

async fn examples(
    State(state): State<Arc<AppState>>,
    Path(run_id): Path<String>,
    Query(q): Query<ExamplesQuery>,
) -> Result<Json<Vec<ExampleView>>, ApiError> {
    use base64::Engine;
    let rows = state.store.examples(&run_id, q.mistakes, q.limit.min(100)).await?;
    Ok(Json(
        rows.into_iter()
            .map(|e| ExampleView {
                idx: e.idx,
                label: e.label,
                predicted: e.predicted,
                confidence: e.confidence,
                pixels: base64::engine::general_purpose::STANDARD.encode(&e.pixels),
            })
            .collect(),
    ))
}

async fn confusion(
    State(state): State<Arc<AppState>>,
    Path(run_id): Path<String>,
) -> Result<Json<Vec<ConfusionCell>>, ApiError> {
    Ok(Json(state.store.confusion(&run_id).await?))
}

/// Everything the page shows, in one call it polls. Each part fails on its
/// own: with MLflow down the page still shows the data and the workflows.
#[derive(Serialize)]
struct PageState {
    stats: Option<Stats>,
    batches: Option<Vec<Batch>>,
    workflows: Value,
    models: Option<Vec<ModelVersion>>,
    predictions: Option<Vec<PredictionRun>>,
    digits: Option<Vec<DigitAccuracy>>,
    errors: Vec<String>,
}

/// The value of one part of the page state, or None and a note in `errors`.
fn part<T>(errors: &mut Vec<String>, name: &str, result: anyhow::Result<T>) -> Option<T> {
    result
        .map_err(|e| {
            tracing::warn!(part = name, error = format!("{e:#}"), "page state");
            errors.push(format!("{name}: unavailable"));
        })
        .ok()
}

async fn page_state(State(state): State<Arc<AppState>>) -> Json<PageState> {
    let mut errors = Vec::new();
    let (stats, batches, models, predictions, train, run) = tokio::join!(
        state.store.stats(),
        state.store.batches(),
        state.mlflow.versions(),
        state.store.prediction_runs(10),
        state.temporal.status(Pipeline::Train),
        state.temporal.status(Pipeline::Run),
    );
    let stats = part(&mut errors, "data", stats);
    let batches = part(&mut errors, "data", batches);
    let models = part(&mut errors, "models", models);
    let predictions = part(&mut errors, "predictions", predictions);
    let train: Option<Option<Status>> = part(&mut errors, "temporal", train);
    let run: Option<Option<Status>> = part(&mut errors, "temporal", run);

    let latest = predictions.as_ref().and_then(|p| p.first()).map(|p| p.run_id.clone());
    let digits = match latest {
        Some(run_id) => part(&mut errors, "predictions", state.store.digit_accuracy(&run_id).await),
        None => None,
    };
    errors.dedup();

    Json(PageState {
        stats,
        batches,
        workflows: json!({ "train": train.flatten(), "run": run.flatten() }),
        models,
        predictions,
        digits,
        errors,
    })
}

fn validate_batch_id(id: String) -> Result<String, ApiError> {
    let well_formed =
        (1..=64).contains(&id.len()) && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_');
    if !well_formed || id == TEST_BATCH_ID {
        return Err(ApiError::BadRequest(
            "batch_id: 1-64 letters, digits, '-' or '_', and not the reserved test batch id".into(),
        ));
    }
    Ok(id)
}

pub enum ApiError {
    BadRequest(String),
    Conflict(String),
    Internal(anyhow::Error),
}

impl From<anyhow::Error> for ApiError {
    fn from(e: anyhow::Error) -> Self {
        ApiError::Internal(e)
    }
}

impl From<IngestError> for ApiError {
    fn from(e: IngestError) -> Self {
        match e {
            IngestError::Exhausted(n) => ApiError::Conflict(format!("all {n} MNIST train examples are already added")),
            IngestError::Store(e) => ApiError::Internal(e),
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            ApiError::BadRequest(m) => (StatusCode::BAD_REQUEST, m),
            ApiError::Conflict(m) => (StatusCode::CONFLICT, m),
            ApiError::Internal(e) => {
                tracing::error!(error = format!("{e:#}"), "request failed");
                (StatusCode::INTERNAL_SERVER_ERROR, "internal error".to_owned())
            }
        };
        (status, Json(json!({ "error": message }))).into_response()
    }
}

#[cfg(test)]
mod tests {
    use axum::body::Body;
    use axum::http::Request;
    use tower::ServiceExt;

    use super::*;

    /// Validation fails before any I/O, so nothing listens behind these.
    fn app() -> Router {
        router(Arc::new(AppState {
            store: ClickHouse::new(clickhouse::Client::default().with_url("http://127.0.0.1:9")),
            mnist: Source::new("http://127.0.0.1:9/".into()),
            temporal: Temporal::new("http://127.0.0.1:9".into(), "default".into()),
            mlflow: Mlflow::new("http://127.0.0.1:9".into()),
            ingest_lock: Mutex::default(),
        }))
    }

    async fn post(body: &str) -> StatusCode {
        let req =
            Request::post("/api/batches").header("content-type", "application/json").body(Body::from(body.to_owned()));
        app().oneshot(req.unwrap()).await.unwrap().status()
    }

    #[tokio::test]
    async fn rejects_bad_requests_before_touching_storage() {
        assert_eq!(post(r#"{"count": 0}"#).await, StatusCode::BAD_REQUEST);
        assert_eq!(post(r#"{"count": 60001}"#).await, StatusCode::BAD_REQUEST);
        assert_eq!(post(r#"{"count": 10, "batch_id": "mnist-test"}"#).await, StatusCode::BAD_REQUEST);
        assert_eq!(post(r#"{"count": 10, "batch_id": "a b"}"#).await, StatusCode::BAD_REQUEST);
        assert_eq!(post(r#"{"batch_id": "x"}"#).await, StatusCode::UNPROCESSABLE_ENTITY);
    }

    #[tokio::test]
    async fn healthz_answers() {
        let res = app().oneshot(Request::get("/healthz").body(Body::empty()).unwrap()).await.unwrap();
        assert_eq!(res.status(), StatusCode::OK);
    }
}
