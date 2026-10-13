//! MNIST source: the original IDX files from a public mirror.
//!
//! Only the gzipped files (~11 MB) stay in memory; a split is unpacked for
//! the duration of one request.

use std::collections::HashMap;
use std::io::Read;

use anyhow::{Context, Result, bail, ensure};
use bytes::Bytes;
use flate2::read::GzDecoder;
use tokio::sync::Mutex;

/// 28 x 28 grayscale pixels, row by row.
pub const IMAGE_BYTES: usize = 28 * 28;

/// The mirror torchvision uses; the original site is often down.
pub const DEFAULT_MIRROR: &str = "https://ossci-datasets.s3.amazonaws.com/mnist/";

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum SplitKind {
    Train,
    Test,
}

impl SplitKind {
    fn files(self) -> (&'static str, &'static str) {
        match self {
            SplitKind::Train => ("train-images-idx3-ubyte.gz", "train-labels-idx1-ubyte.gz"),
            SplitKind::Test => ("t10k-images-idx3-ubyte.gz", "t10k-labels-idx1-ubyte.gz"),
        }
    }
}

/// One split: `labels.len()` images of `IMAGE_BYTES` each in `images`.
pub struct Split {
    pub images: Vec<u8>,
    pub labels: Vec<u8>,
}

impl Split {
    pub fn len(&self) -> usize {
        self.labels.len()
    }

    pub fn image(&self, i: usize) -> &[u8] {
        &self.images[i * IMAGE_BYTES..(i + 1) * IMAGE_BYTES]
    }
}

/// IDX: 2 zero bytes, a type byte (0x08 = uint8), the number of dimensions,
/// the dimensions as big-endian u32, then the data. Gzipped input is
/// unpacked first. Returns the dimensions and the data.
pub fn parse_idx(raw: &[u8]) -> Result<(Vec<usize>, Vec<u8>)> {
    let mut data = Vec::new();
    if raw.starts_with(&[0x1f, 0x8b]) {
        GzDecoder::new(raw).read_to_end(&mut data).context("gunzip")?;
    } else {
        data = raw.to_vec();
    }
    ensure!(data.len() >= 4 && data[..3] == [0, 0, 0x08], "not an IDX file of uint8");

    let ndim = data[3] as usize;
    let header = 4 + 4 * ndim;
    ensure!(data.len() >= header, "truncated IDX header");
    let dims: Vec<usize> = data[4..header].as_chunks::<4>().0.iter().map(|d| u32::from_be_bytes(*d) as usize).collect();
    ensure!(data.len() - header == dims.iter().product::<usize>(), "IDX size does not match its dimensions");

    data.drain(..header);
    Ok((dims, data))
}

pub fn parse_split(images_raw: &[u8], labels_raw: &[u8]) -> Result<Split> {
    let (image_dims, images) = parse_idx(images_raw).context("images")?;
    let (label_dims, labels) = parse_idx(labels_raw).context("labels")?;
    if image_dims.len() != 3 || image_dims[1] * image_dims[2] != IMAGE_BYTES || label_dims != [image_dims[0]] {
        bail!("unexpected MNIST shapes: images {image_dims:?}, labels {label_dims:?}");
    }
    Ok(Split { images, labels })
}

/// Downloads each file once and keeps it gzipped.
pub struct Source {
    mirror: String,
    http: reqwest::Client,
    /// `Bytes` clones share the buffer: no copy per request.
    files: Mutex<HashMap<&'static str, Bytes>>,
}

impl Source {
    pub fn new(mirror: String) -> Self {
        Self { mirror, http: reqwest::Client::new(), files: Mutex::default() }
    }

    pub async fn split(&self, kind: SplitKind) -> Result<Split> {
        let (images, labels) = kind.files();
        parse_split(&self.file(images).await?, &self.file(labels).await?)
    }

    async fn file(&self, name: &'static str) -> Result<Bytes> {
        let mut files = self.files.lock().await;
        if let Some(raw) = files.get(name) {
            return Ok(raw.clone());
        }
        tracing::info!(file = name, "downloading MNIST file");
        let url = format!("{}{name}", self.mirror);
        let raw = self.http.get(&url).send().await?.error_for_status()?.bytes().await?;
        files.insert(name, raw.clone());
        Ok(raw)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    pub fn idx(dims: &[u32], data: &[u8]) -> Vec<u8> {
        let mut raw = vec![0, 0, 0x08, dims.len() as u8];
        for d in dims {
            raw.extend(d.to_be_bytes());
        }
        raw.extend(data);
        raw
    }

    #[test]
    fn parses_plain_and_gzipped_idx() {
        let raw = idx(&[2, 3], &[1, 2, 3, 4, 5, 6]);
        let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
        std::io::Write::write_all(&mut gz, &raw).unwrap();

        for input in [raw.clone(), gz.finish().unwrap()] {
            assert_eq!(parse_idx(&input).unwrap(), (vec![2, 3], vec![1, 2, 3, 4, 5, 6]));
        }
    }

    #[test]
    fn rejects_size_mismatch() {
        assert!(parse_idx(&idx(&[2, 3], &[1, 2, 3])).is_err());
    }

    #[test]
    fn split_checks_shapes() {
        let images = idx(&[2, 28, 28], &[7; 2 * IMAGE_BYTES]);
        let split = parse_split(&images, &idx(&[2], &[3, 9])).unwrap();
        assert_eq!((split.len(), split.labels.clone(), split.image(1)[0]), (2, vec![3, 9], 7));

        assert!(parse_split(&images, &idx(&[3], &[1, 2, 3])).is_err());
    }
}
