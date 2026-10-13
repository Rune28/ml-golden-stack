//! Add data: the next MNIST train examples become one batch in ClickHouse.

use serde::Serialize;

use crate::mnist::{Split, SplitKind};
use crate::store::SampleStore;

/// The whole test split goes in once, under this batch id.
pub const TEST_BATCH_ID: &str = "mnist-test";

#[derive(Serialize, Debug, PartialEq, Eq)]
pub struct IngestResult {
    pub batch_id: String,
    pub added: u64,
    /// Position of the first example in the MNIST train split.
    pub first_idx: u64,
    pub train_total: u64,
    pub test_total: u64,
}

#[derive(Debug)]
pub enum IngestError {
    /// Every train example is already in some batch.
    Exhausted(u64),
    Store(anyhow::Error),
}

impl From<anyhow::Error> for IngestError {
    fn from(e: anyhow::Error) -> Self {
        IngestError::Store(e)
    }
}

/// Adds the next `count` train examples as batch `batch_id`.
///
/// Safe to retry with the same `batch_id`: a complete batch is left as is, a
/// partial one (the previous attempt died mid-insert) is deleted and written
/// again. The offset is `count()` of the train split without this batch, so a
/// retry starts where the first attempt did. Concurrent calls must be
/// serialized by the caller: two of them would read the same offset.
pub async fn ingest<S: SampleStore>(
    store: &S,
    train: &Split,
    test: &Split,
    batch_id: &str,
    count: u64,
) -> Result<IngestResult, IngestError> {
    write_batch(store, TEST_BATCH_ID, SplitKind::Test, test, 0..test.len()).await?;

    let offset = store.split_rows(SplitKind::Train, batch_id).await?;
    let end = (offset + count).min(train.len() as u64);
    if offset >= end {
        return Err(IngestError::Exhausted(train.len() as u64));
    }
    write_batch(store, batch_id, SplitKind::Train, train, offset as usize..end as usize).await?;

    Ok(IngestResult {
        batch_id: batch_id.to_owned(),
        added: end - offset,
        first_idx: offset,
        train_total: end,
        test_total: store.split_rows(SplitKind::Test, "").await?,
    })
}

/// Writes the batch unless it is already complete; a partial one is replaced.
async fn write_batch<S: SampleStore>(
    store: &S,
    batch_id: &str,
    split: SplitKind,
    data: &Split,
    rows: std::ops::Range<usize>,
) -> anyhow::Result<()> {
    let existing = store.batch_rows(batch_id).await?;
    if existing == rows.len() as u64 {
        return Ok(());
    }
    if existing > 0 {
        tracing::warn!(batch_id, existing, expected = rows.len(), "partial batch, rewriting");
        store.delete_batch(batch_id).await?;
    }
    store.insert(batch_id, split, data, rows).await
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use super::*;
    use crate::mnist::IMAGE_BYTES;

    /// In-memory `samples`: (batch_id, split, idx) per row.
    #[derive(Default)]
    struct FakeStore {
        rows: Mutex<Vec<(String, SplitKind, usize)>>,
    }

    impl FakeStore {
        fn idx_of(&self, batch_id: &str) -> Vec<usize> {
            let mut idx: Vec<_> = self.rows.lock().unwrap().iter().filter(|r| r.0 == batch_id).map(|r| r.2).collect();
            idx.sort();
            idx
        }
    }

    impl SampleStore for FakeStore {
        async fn batch_rows(&self, batch_id: &str) -> anyhow::Result<u64> {
            Ok(self.rows.lock().unwrap().iter().filter(|r| r.0 == batch_id).count() as u64)
        }
        async fn split_rows(&self, split: SplitKind, exclude_batch: &str) -> anyhow::Result<u64> {
            Ok(self.rows.lock().unwrap().iter().filter(|r| r.1 == split && r.0 != exclude_batch).count() as u64)
        }
        async fn delete_batch(&self, batch_id: &str) -> anyhow::Result<()> {
            self.rows.lock().unwrap().retain(|r| r.0 != batch_id);
            Ok(())
        }
        async fn insert(
            &self,
            batch_id: &str,
            split: SplitKind,
            _: &Split,
            rows: std::ops::Range<usize>,
        ) -> anyhow::Result<()> {
            self.rows.lock().unwrap().extend(rows.map(|i| (batch_id.to_owned(), split, i)));
            Ok(())
        }
    }

    fn split(n: usize) -> Split {
        Split { images: vec![0; n * IMAGE_BYTES], labels: (0..n).map(|i| (i % 10) as u8).collect() }
    }

    async fn add(store: &FakeStore, batch_id: &str, count: u64) -> Result<IngestResult, IngestError> {
        ingest(store, &split(100), &split(20), batch_id, count).await
    }

    #[tokio::test]
    async fn first_batch_loads_test_split_and_first_examples() {
        let store = FakeStore::default();

        let result = add(&store, "b1", 30).await.unwrap();

        assert_eq!(
            result,
            IngestResult { batch_id: "b1".into(), added: 30, first_idx: 0, train_total: 30, test_total: 20 }
        );
        assert_eq!(store.idx_of(TEST_BATCH_ID), (0..20).collect::<Vec<_>>());
        assert_eq!(store.idx_of("b1"), (0..30).collect::<Vec<_>>());
    }

    #[tokio::test]
    async fn next_batch_continues_after_previous() {
        let store = FakeStore::default();
        add(&store, "b1", 30).await.unwrap();

        let result = add(&store, "b2", 30).await.unwrap();

        assert_eq!(store.idx_of("b2"), (30..60).collect::<Vec<_>>());
        assert_eq!(result.train_total, 60);
        assert_eq!(store.idx_of(TEST_BATCH_ID).len(), 20); // not loaded twice
    }

    #[tokio::test]
    async fn retry_of_complete_batch_changes_nothing() {
        let store = FakeStore::default();
        add(&store, "b1", 30).await.unwrap();
        let before = store.rows.lock().unwrap().clone();

        let result = add(&store, "b1", 30).await.unwrap();

        assert_eq!(*store.rows.lock().unwrap(), before);
        assert_eq!(result.added, 30);
    }

    #[tokio::test]
    async fn retry_of_partial_batch_rewrites_it() {
        let store = FakeStore::default();
        add(&store, "b1", 30).await.unwrap();
        // The previous attempt of b2 died after 10 of 30 rows.
        store.insert("b2", SplitKind::Train, &split(100), 30..40).await.unwrap();

        add(&store, "b2", 30).await.unwrap();

        assert_eq!(store.idx_of("b2"), (30..60).collect::<Vec<_>>());
    }

    #[tokio::test]
    async fn partial_test_split_is_rewritten() {
        let store = FakeStore::default();
        store.insert(TEST_BATCH_ID, SplitKind::Test, &split(20), 0..5).await.unwrap();

        add(&store, "b1", 30).await.unwrap();

        assert_eq!(store.idx_of(TEST_BATCH_ID), (0..20).collect::<Vec<_>>());
    }

    #[tokio::test]
    async fn last_batch_is_cut_at_the_end_of_the_dataset() {
        let store = FakeStore::default();
        add(&store, "b1", 90).await.unwrap();

        assert_eq!(add(&store, "b2", 30).await.unwrap().added, 10);
        assert!(matches!(add(&store, "b3", 30).await, Err(IngestError::Exhausted(100))));
    }
}
