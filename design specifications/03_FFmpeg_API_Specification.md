# FFmpeg API — specification sheet

Contract 1.1 • 22 October 2026 • Proposed REST interface

## Transport, identity and versioning

Base URL: `http://ffmpeg:8080/v1` on the private media network. All /v1 endpoints require `Authorization: Bearer <key>`. Use at least 256 bits of random key material per consumer, hashed for comparison. A key maps to a stable consumer ID so rotation preserves job access. Never accept keys in URLs. All job reads/mutations are scoped to that identity; another consumer's ID returns 404.

This private HTTP deployment assumes a trusted Docker host/network. Any deployment across untrusted machines requires authenticated TLS at the transport boundary. No CORS access is enabled. No remote URL input, callback URL or webhook is accepted.

Breaking changes use /v2. Within /v1, response fields and asynchronous error codes may be added; clients ignore unknown response fields and treat unknown error codes as non-retryable failures. Request fields and enums are strict: unknown inputs fail validation. UTC times use RFC 3339, sizes are integer bytes, IDs are opaque random identifiers with at least 128 bits of entropy.

## Endpoints

| Method / path | Success | Contract |
|---|---|---|
| GET /health/live | 200 | Unauthenticated minimal process status |
| GET /health/ready | 200 / 503 | Minimal readiness; no secrets or detailed paths |
| GET /v1/capabilities | 200 JSON | Installed operations, formats, limits, API version and instance_id |
| POST /v1/jobs | 202 JSON | Accept one streamed upload plus processing request |
| GET /v1/jobs/{id} | 200 JSON or HTML | Current resource state, including failed jobs |
| GET /v1/jobs/{id}/download | 200 / 206 binary | Completed result; no automatic deletion |
| DELETE /v1/jobs/{id} | 202 or 204 | Cancel if running, remove files and leave a deleted tombstone |

Every authenticated response includes X-Request-ID and Cache-Control: no-store. Polling responses provide Retry-After: 2 while pending. Use ETag on status to permit If-None-Match / 304; because status supports JSON and HTML representations, status responses include `Vary: Accept` and the ETag differs per representation. An expired or deleted tombstone returns 410 to GET; unknown IDs and IDs from a lost registry return 404.

## Create request

`POST /v1/jobs` uses streaming multipart/form-data with exactly two parts, in this order:

1. `request`: application/json, at most 16 KiB.
2. `file`: uploaded bytes, at most the advertised maximum.

No multiple inputs in v1. User filenames are display metadata only and bounded to 255 characters. Validate file structure in the sandbox; filename and Content-Type do not establish format.

Required header: `Idempotency-Key`, 16–128 printable ASCII characters. The request includes exact input size and SHA-256, available from the caller's stored asset:

```json
{
  "operation": "transcode",
  "input": {
    "size_bytes": 10485760,
    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "parameters": {
    "width": 1280,
    "height": 720,
    "fit": "contain",
    "quality": 23,
    "audio_bitrate_kbps": 128
  },
  "output_format": "mp4"
}
```

The hash above is illustrative, not the checksum of a supplied file. The server validates the `request` part before reading the file part, so schema errors and oversize declarations are rejected without consuming the upload. It then streams and hashes the complete input before returning 202. A disconnected or incomplete upload creates no accepted job. Release its storage reservation. Client cancellation during upload is by closing the request.

### Idempotency

Idempotency scope is (consumer_id, key). Compare a fingerprint of canonical request parameters, declared size and checksum.

- **Replay of an accepted request** with a matching fingerprint: the server reads and hashes the file part without storing it or reserving storage, then returns the original 202 resource without a second execution. If the replayed bytes do not match the declared checksum, it returns 400 checksum_mismatch and the original job is unaffected.
- **Conflicting fingerprint**: 409 idempotency_conflict, returned after the `request` part, without reading the file.
- **Simultaneous use** while the first upload is incomplete: 409 idempotency_in_progress with Retry-After.

Clients that already hold a job ID should poll `GET /v1/jobs/{id}` rather than replay the upload. Preserve the key until tombstone expiry; restart resets it. The server must verify the first accepted upload's declared size/hash, not trust client claims.

## Validation phases

Validation happens in two phases. Errors from the first phase are HTTP errors on POST; errors from the second are reported in the job's `error` field with status `failed`.

| Phase | When | Checks |
|---|---|---|
| Synchronous | Before 202 | Multipart structure, part order and sizes; JSON schema, types, enums and ranges; even video dimensions; width × height within MAX_PIXELS; declared size within limits; operation/output format combination; received size and SHA-256 match the declaration |
| Asynchronous | After probing in the sandbox | Detected media format; stream presence; probed duration and dimensions within limits; whether the request would upscale; trim range and thumbnail timestamp within the probed duration; output size and timeouts |

The server does not inspect media content before 202, so it never returns 415 for media format; unsupported or malformed media is reported asynchronously.

## Operation schemas

All operations reject unknown fields. Integers must be integers, finite decimals must be finite, and zero/negative dimensions or durations are invalid. A format/codec matrix is returned by capabilities and validated before processing.

| Operation | Parameters | Allowed output and meaning |
|---|---|---|
| transcode | width/height optional pair; fit contain or cover; quality 18–35 default 23; audio_bitrate_kbps 64–320 default 128 | mp4: H.264/AAC; webm: VP9/Opus |
| resize | width/height required; fit contain or cover; jpeg_quality 50–95 default 85 (jpg only) | jpg or png; still images only |
| thumbnail | timestamp_seconds ≥ 0, width/height required, fit contain or cover; jpeg_quality 50–95 default 85 (jpg only) | jpg or png; one video frame |
| extract_audio | audio_bitrate_kbps 64–320; channels 1 or 2 default 2 | m4a/AAC, mp3 or opus/Ogg |
| trim | start_seconds ≥ 0; duration_seconds > 0; optional quality 18–35 | mp4 or webm; re-encode for requested boundaries |
| remux | No parameters | mp4 or webm; stream-copy only when codecs are compatible |
| metadata | No parameters; output_format must be json | Sanitized metadata JSON as result file |

Width and height range 16–4096, product within MAX_PIXELS; video dimensions must be even. Requested size cannot exceed service limits. contain preserves aspect ratio and pads to the box; cover scales and center-crops. No upscale by default; a request that would upscale fails asynchronously with `upscale_not_allowed`. Apply orientation before geometry for re-encoding operations. Remux cannot change geometry, so it preserves the source's rotation as display metadata. Strip location and other source metadata by default; retain only essential encoding/color/rotation information. For transcode, select first video and optional first audio track; exclude subtitle/data tracks. Audio extraction requires an audio track. Remux rejects incompatible streams rather than silently transcoding. MP4 and M4A results are written with the index before the media data (faststart).

Trim must remain within probed duration and service duration limit. Thumbnail timestamp must identify an available frame. Animated images (including animated GIF, APNG and animated WebP) are rejected with `unsupported_media`; animated image processing and multi-output jobs are out of v1 scope. Unsupported input formats, playlists, archives, SVG/HTML and files referencing external resources are rejected.

## Job representation

```json
{
  "api_version": "1",
  "instance_id": "boot_7c98",
  "job_id": "032f50ba9fda42b0bf5cb26d798d1ae2",
  "status": "completed",
  "created_at": "2026-10-22T14:00:00Z",
  "completed_at": "2026-10-22T14:00:09Z",
  "expires_at": "2026-10-22T14:15:09Z",
  "status_url": "/v1/jobs/032f50ba9fda42b0bf5cb26d798d1ae2",
  "download_url": "/v1/jobs/032f50ba9fda42b0bf5cb26d798d1ae2/download",
  "result": {
    "content_type": "video/mp4",
    "size_bytes": 4567890,
    "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  },
  "error": null
}
```

202 responses use status queued, null completed_at/expires_at/download_url/result/error, plus a Location header for the status resource. Processing has no guaranteed percentage estimate. Optional progress is null when unknown, never a fabricated percentage.

### Lifecycle

| From | Event | To |
|---|---|---|
| queued | Processing starts | processing |
| processing | Success / failure | completed / failed |
| queued or processing | DELETE | cancelling → deleted |
| queued or processing | Server shutdown or drain | cancelled |
| completed, failed or cancelled | Retention elapses | expired |
| completed, failed or cancelled | DELETE | deleted |

`cancelled` is only reached when the server itself stops a job; a client DELETE always ends in `deleted`.

### DELETE responses

| Current state | Response |
|---|---|
| queued or processing | 202; job moves to cancelling, then deleted once the process group is killed and files removed |
| cancelling | 202 |
| completed, failed or cancelled | 204 once files are removed; 202 if an active download pin delays unlink |
| deleted or expired tombstone | 204 (idempotent; nothing left to remove) |
| unknown or lost | 404 |

Failed/cancelled jobs release files immediately and retain status for 900 seconds. Completed jobs retain output for 900 seconds. Expired/deleted tombstones then remain another 900 seconds. Terminal status does not imply immediate deletion of successful output.

GET status returns HTTP 200 even when processing failed: fetching the resource succeeded. The body contains the processing error. Request/protocol failures use the HTTP errors below.

## Error model

```json
{
  "error": {
    "code": "invalid_parameter",
    "message": "Width must be an even integer between 16 and 4096.",
    "field": "parameters.width",
    "retryable": false,
    "request_id": "req_93c1"
  }
}
```

### Synchronous HTTP errors

| HTTP | Codes / conditions |
|---|---|
| 400 | malformed_request, missing_part, checksum_mismatch |
| 401 | invalid_authentication |
| 404 | job_not_found, including ownership mismatch |
| 406 | unsupported Accept representation |
| 409 | idempotency_conflict, idempotency_in_progress, result_not_ready, result_unavailable |
| 410 | job_expired or job_deleted while tombstone retained (GET only) |
| 413 | upload_too_large |
| 415 | unsupported request Content-Type or part Content-Type |
| 422 | invalid_parameter, unsupported_operation, incompatible_output |
| 429 | consumer concurrency/rate limit; Retry-After included |
| 503 | global capacity exhausted or processor unavailable; Retry-After included |
| 500 | sanitized internal_error |

### Asynchronous job errors

| Code | Meaning | `field` | Retryable |
|---|---|---|---|
| invalid_media | Malformed or truncated media | null | false |
| unsupported_media | Unsupported format, animated image or external references | null | false |
| no_audio_track | Audio required but absent | null | false |
| incompatible_output | Streams cannot be remuxed into the requested container | output_format | false |
| upscale_not_allowed | Requested size exceeds source dimensions | parameters.width / height | false |
| duration_exceeded | Probed duration above service limit | null | false |
| dimensions_exceeded | Probed source dimensions above MAX_PIXELS | null | false |
| range_out_of_bounds | Trim range or thumbnail timestamp beyond probed duration | parameters.start_seconds / duration_seconds / timestamp_seconds | false |
| processing_timeout | Computed processing timeout exceeded | null | true |
| output_too_large | Result above output maximum | null | false |
| resource_limit | Memory or file-size limit reached | null | true |
| processing_failed | Other sanitized processing failure | null | true |

Do not leak FFmpeg stderr, commands, paths or source metadata into error text. Retryable means resubmission may work; clients still apply bounded backoff and inspect the cause.

## Download, HTML and deletion

Download supports one HTTP byte range: 206 and Content-Range for valid ranges; 416 for invalid/multiple ranges. Include Content-Length, authoritative Content-Type, Accept-Ranges: bytes, ETag derived from checksum and Content-Disposition: attachment with a service-generated filename. Set X-Content-Type-Options: nosniff. Authenticate every download, including resumed ranges.

Use Accept: text/html on the status endpoint for a small escaped page showing state, timestamps, sanitized error code and download link. JSON is the default for */*; other unsupported representations return 406.

HTML does not bypass bearer authentication. Its intended consumer is Rails or another authorized backend, which can fetch and relay content under its own user session. An ordinary browser navigation cannot add a bearer header automatically. Do not create an unauthenticated direct-browser mode or put API keys in links; Rails normally renders its own job view.

A download pins the result until that response finishes, with a 120-second transfer deadline. Expiry blocks new downloads and defers file unlink until pins release. DELETE cancels active transfers, kills any process group, then removes files (see DELETE responses). GET never deletes content: the caller verifies checksum and commits durable storage before DELETE.

## Client recovery and contract tests

Poll every 2 seconds initially with jitter and a bounded overall deadline derived from the job's computed processing timeout. Recheck capabilities after instance_id changes. On 404 after a processor restart, resubmit from the original PostgreSQL asset under the caller's durable processing record. Processing may execute more than once; application asset finalization is deduplicated by request ID and source revision. On restart, the client deletes any remote jobs it no longer needs.

Test multipart order/size, rejected unknown fields, sync versus async validation, idempotency races and replays, cross-consumer denial, all operation schemas, checksum mismatch, Accept negotiation and Vary, range resumption, delete/download races, every DELETE state, resource saturation, token rotation and restart recovery. Generate an OpenAPI 3.1 contract and matching test fixtures during implementation from this sheet; this document itself is not a validated OpenAPI file.

Reference: [FFmpeg protocol documentation](https://ffmpeg.org/ffmpeg-protocols.html). The HTTP contract above is project-defined.

## Changes in 1.1

- Split validation into synchronous and asynchronous phases; added async codes for upscale, duration, dimensions and range errors; 415 no longer covers media format.
- Clarified idempotent replay: the body is hashed without storage, and conflicts are reported before reading the file.
- Rewrote the lifecycle: client DELETE always ends in `deleted`; `cancelled` is server-initiated; defined DELETE responses for every state, including tombstones.
- Added `Vary: Accept` on status responses.
- Added optional `jpeg_quality` to resize and thumbnail so callers can meet provider image caps (for example Instagram JPEG-only and Bluesky size limits); sending it with png output is invalid_parameter.
- Animated images are rejected explicitly; remux preserves rotation; MP4/M4A use faststart.
