//! be_service: backend of the pipeline page.
//!
//! Serves the page and its API: Add data (MNIST batches into ClickHouse),
//! Train and Run (Temporal workflows executed by de_worker), and the state the
//! page shows: data, workflows, model versions (MLflow), predictions.

mod api;
mod ingest;
mod mlflow;
mod mnist;
mod store;
mod temporal;

use std::sync::Arc;

use anyhow::{Context, Result};
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;

fn env_or(name: &str, default: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| default.to_owned())
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();

    // The client connects lazily: the service starts even before ClickHouse.
    let clickhouse = clickhouse::Client::default()
        .with_url(env_or("CLICKHOUSE_URL", "http://127.0.0.1:8123"))
        .with_user(env_or("CLICKHOUSE_USER", "default"))
        .with_password(std::env::var("CLICKHOUSE_PASSWORD").unwrap_or_default())
        .with_database(env_or("CLICKHOUSE_DATABASE", "ml_data"));

    let state = Arc::new(api::AppState {
        store: store::ClickHouse::new(clickhouse),
        mnist: mnist::Source::new(env_or("MNIST_MIRROR", mnist::DEFAULT_MIRROR)),
        temporal: temporal::Temporal::new(
            env_or("TEMPORAL_ADDRESS", "http://127.0.0.1:7233"),
            env_or("TEMPORAL_NAMESPACE", "default"),
        ),
        mlflow: mlflow::Mlflow::new(env_or("MLFLOW_URL", "http://127.0.0.1:5000")),
        ingest_lock: Default::default(),
    });

    let addr = env_or("LISTEN_ADDR", "0.0.0.0:8080");
    let listener = TcpListener::bind(&addr).await.with_context(|| format!("bind {addr}"))?;
    tracing::info!(%addr, "listening");
    axum::serve(listener, api::router(state)).with_graceful_shutdown(shutdown()).await?;
    Ok(())
}

/// Kubernetes stops a pod with SIGTERM: finish requests in flight, then exit.
async fn shutdown() {
    let ctrl_c = async { tokio::signal::ctrl_c().await.ok() };
    let term = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).expect("SIGTERM handler").recv().await
    };
    tokio::select! {
        _ = ctrl_c => {}
        _ = term => {}
    }
    tracing::info!("shutting down");
}
