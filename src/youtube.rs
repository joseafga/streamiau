use axum::{extract::Path, extract::Query, http::StatusCode};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{io::BufRead, process::Command};
use tracing::instrument;

#[derive(Debug, Serialize, Deserialize)]
struct Thumbnail {
    height: Option<u64>,
    url: Option<String>,
    width: Option<u64>,
}

#[derive(Debug, Serialize, Deserialize)]
struct Entry {
    epoch: u64,
    extractor: String,
    extractor_key: String,
    id: String,
    ie_key: String,
    n_entries: u64,
    original_url: String,
    playlist: String,
    playlist_autonumber: u64,
    playlist_channel: String,
    playlist_channel_id: String,
    playlist_count: u64,
    playlist_id: String,
    playlist_index: u64,
    playlist_title: String,
    playlist_uploader: String,
    playlist_uploader_id: String,
    playlist_webpage_url: String,
    release_year: Value,
    thumbnails: Vec<Thumbnail>,
    title: String,
    url: String,
    view_count: u64,
    webpage_url: String,
    webpage_url_basename: String,
    webpage_url_domain: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Params {
    // Supported language codes (case-sensitive):
    // af, az, id, ms, bs, ca, cs, da, de, et, en-IN, en-GB, en, es, es-419, es-US, eu, fil,
    // fr, fr-CA, gl, hr, zu, is, it, sw, lv, lt, hu, nl, no, uz, pl, pt-PT, pt, ro, sq, sk,
    // sl, sr-Latn, fi, sv, vi, tr, be, bg, ky, kk, mk, mn, ru, sr, uk, el, hy, iw, ur, ar,
    // fa, ne, mr, hi, as, bn, pa, gu, or, ta, te, kn, ml, si, th, lo, my, ka, am, km, zh-CN,
    // zh-TW, zh-HK, ja, ko.
    lang: Option<String>,
}

#[instrument]
pub async fn get_last_video(
    Path(channel): Path<String>,
    Query(params): Query<Params>,
) -> Result<String, StatusCode> {
    tracing::debug!("getting last video from channel={}", channel);
    check_your_mom(&channel).ok_or(StatusCode::UNAUTHORIZED)?;

    let url = format!("https://www.youtube.com/@{channel}/videos");
    let lang = params.lang.as_deref().unwrap_or("en");
    let response = fetch_last_entry(&url, &lang).await;

    match response {
        Ok(entry) => Ok(format!("{} - {}", entry.title, entry.url)),
        Err(e) => {
            tracing::error!("Fetch error: {:#?}", e.to_string());
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

#[instrument]
pub async fn get_last_short(
    Path(channel): Path<String>,
    Query(params): Query<Params>,
) -> Result<String, StatusCode> {
    tracing::debug!("getting last short from channel={}", channel);
    check_your_mom(&channel).ok_or(StatusCode::BAD_REQUEST)?;

    let url = format!("https://www.youtube.com/@{channel}/shorts");
    let lang = params.lang.as_deref().unwrap_or("en");
    let response = fetch_last_entry(&url, &lang).await;

    match response {
        Ok(entry) => Ok(format!("{} - {}", entry.title, entry.url)),
        Err(e) => {
            tracing::error!("Fetch error: {:#?}", e.to_string());
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

async fn fetch_last_entry(url: &str, lang: &str) -> Result<Entry, Box<dyn std::error::Error>> {
    tracing::debug!("running yt-dlp");

    let output = Command::new("yt-dlp")
        .args([
            "--extractor-args",
            &format!("youtube:lang={}", lang),
            "--dump-json",
            "--no-download",
            "--flat-playlist",
            url,
        ])
        .output()
        .expect("Fail on yt-dlp execution.");

    assert!(output.status.success());

    // Yt-dlp return multiples lines with a json each
    let mut lines = output.stdout.lines();
    let line = lines.next().ok_or("Empty output from yt-dlp.")?;
    let json = serde_json::from_str(line.unwrap().as_str())?;

    Ok(json)
}

fn check_your_mom(channel: &String) -> Option<()> {
    match channel.as_str() {
        "raixssa" => Some(()),
        "elakstriker" => Some(()),
        _ => None,
    }
}
