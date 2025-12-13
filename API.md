# API

This Worker currently exposes:

- `GET /`
- `GET /health`
- `POST /api/channels`
- `POST /api/channels/register`
- `POST /api/videos/query`

No auth is implemented yet. All responses include permissive CORS headers.

## Base URL

Start locally:

```sh
npm run dev
```

Local (Wrangler dev default): `http://127.0.0.1:8787`

Examples below assume:

```sh
BASE_URL=http://127.0.0.1:8787
```

## Response conventions

- JSON responses use `content-type: application/json; charset=utf-8`.
- Error responses are JSON: `{"error":"..."}`.
- Unmatched routes return `404` with plain text body `not found`.
- Paths are matched exactly (no trailing-slash normalization).

## CORS / preflight

The Worker responds to any `OPTIONS` request with `204` and:

- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Headers: Content-Type`
- `Access-Control-Allow-Methods: GET,POST,OPTIONS`

```sh
curl -i -X OPTIONS "$BASE_URL/api/channels/register"
```

## GET /

Returns `200` with a plain text service description.

```sh
curl -i "$BASE_URL/"
```

## GET /health

Returns `200` with plain text body `ok`.

```sh
curl -i "$BASE_URL/health"
```

## POST /api/channels/register

Registers channel IDs in the global `channels` table (idempotent).

Request JSON:

```json
{ "channelIds": ["UC_x5XG1OV2P6uZZ5FSM9Ttw", "..."] }
```

Validation/normalization:

- `channelIds` must be a non-empty array of strings (max `500`)
- each value is trimmed, then filtered to IDs matching `/^[A-Za-z0-9_-]+$/` and length `10..128`
- duplicates are removed after trimming
- invalid-looking IDs are ignored; if none remain: `400 {"error":"no valid channel IDs"}`

Success response `200`:

```json
{
	"requested": 1,
	"inserted": 1,
	"alreadyPresent": 0,
	"totalChannels": 1
}
```

```sh
curl -i -X POST "$BASE_URL/api/channels/register" \
  -H 'content-type: application/json' \
  -d '{"channelIds":[" UC_x5XG1OV2P6uZZ5FSM9Ttw ","UC_x5XG1OV2P6uZZ5FSM9Ttw","invalid id"]}'
```

Error example (empty list):

```sh
curl -i -X POST "$BASE_URL/api/channels/register" \
  -H 'content-type: application/json' \
  -d '{"channelIds":[]}'
```

## POST /api/channels

Lists all channels in the database with their current titles (nullable). Titles are updated during feed ingestion (cron).

Request: no body required.

Response `200`:

```json
{
	"channels": [
		{
			"channelId": "UC_x5XG1OV2P6uZZ5FSM9Ttw",
			"title": "Example Channel"
		}
	]
}
```

```sh
curl -i -X POST "$BASE_URL/api/channels"
```

## POST /api/videos/query

Queries videos, returning only rows with `seq > afterSeq`. `channelIds` can be used to filter results.

Request JSON:

```json
{ "channelIds": ["UC_x5XG1OV2P6uZZ5FSM9Ttw"], "afterSeq": 0, "limit": 200 }
```

Notes:

- `seq` is a single, global autoincrement across all channels (not per-channel).
- `afterSeq` is a global watermark; using `afterSeq = maxSeqReturned` fetches only newer inserts.
- The Worker keeps only the most recent ~100 videos per channel; older rows are trimmed during scheduled updates.

Validation/normalization:

- if `channelIds` is omitted or `[]`, results include videos from all channels
- if provided and non-empty: `channelIds` must be an array of strings (max `300`), trimmed + de-duplicated + plausibility-filtered
- `afterSeq` defaults to `0` and must be a non-negative integer
- `limit` defaults to `200` and must be an integer `1..500`

Response `200`:

```json
{
	"videos": [
		{
			"seq": 12346,
			"videoId": "abcd",
			"channelId": "UC_x5XG1OV2P6uZZ5FSM9Ttw",
			"publishedAt": "2025-12-10T18:11:22Z",
			"title": "Example",
			"url": "https://www.youtube.com/watch?v=abcd"
		}
	],
	"maxSeqReturned": 12346
}
```

```sh
curl -i -X POST "$BASE_URL/api/videos/query" \
  -H 'content-type: application/json' \
  -d '{"channelIds":["UC_x5XG1OV2P6uZZ5FSM9Ttw"],"afterSeq":0,"limit":50}'
```

Query all channels (omit `channelIds`):

```sh
curl -i -X POST "$BASE_URL/api/videos/query" \
  -H 'content-type: application/json' \
  -d '{"afterSeq":0,"limit":50}'
```
