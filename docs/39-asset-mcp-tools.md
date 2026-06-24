# 39. Asset MCP Tools Slice

## Status

Validated implementation guide for Issue #20 / PR branch `agent/asset-mcp-tools`.

This slice implements the frozen MCP asset tools:

- `asset_create_upload_url`
- `asset_register_external_url`

It does not implement MCP `upload-complete`, memo-asset linking, or binary upload itself.

## Runtime Path

### MCP internal asset upload URL

```text
POST /api/v1/mcp/asset/create-upload-url
    ↓
AssetCreateUploadUrl validation
    ↓
create_internal_asset_upload_record(...)
    ↓
assets metadata row
    ↓
audit_logs row, tool_name=asset_create_upload_url
    ↓
return asset_id / storage_key / upload_url / asset
```

### MCP external URL registration

```text
POST /api/v1/mcp/asset/register-external-url
    ↓
AssetRegisterExternalUrl validation
    ↓
register_external_asset_record(...)
    ↓
assets metadata row, kind=external
    ↓
audit_logs row, tool_name=asset_register_external_url
    ↓
return asset
```

## Asset Type Contract

The TypeScript protocol package must stay aligned with Python runtime validation:

```text
asset_create_upload_url:
  image | pdf | ppt | mindmap | file | audio | video

asset_register_external_url:
  image | pdf | ppt | mindmap | file | audio | video | link | embed
```

Important notes:

- Use `ppt`, not `slide`, because the Python runtime currently validates `ppt`.
- Do not allow `link` or `embed` for internal upload URLs.
- Allow `link` and `embed` only for external URL asset registration.

## Local Validation

Start the API:

```bash
cd services/api
uv run uvicorn app.main:app --reload --port 8310
```

### 1. Normal API regression: create upload URL

```bash
curl -X POST http://localhost:8310/api/v1/assets/create-upload-url \
  -H 'Content-Type: application/json' \
  -d '{"filename":"normal-api-asset.txt","mime_type":"text/plain","size_bytes":12,"asset_type":"file"}'
```

Expected:

```text
success=true
asset_id is present
upload_url is present
asset.kind=internal
asset.sync_status=pending
```

### 2. Normal API regression: register external URL

```bash
curl -X POST http://localhost:8310/api/v1/assets/register-external-url \
  -H 'Content-Type: application/json' \
  -d '{"external_url":"https://example.com/normal-api-link","title":"Normal API external link","asset_type":"link"}'
```

Expected:

```text
success=true
asset.kind=external
asset.external_url=https://example.com/normal-api-link
asset.sync_status=synced
```

### 3. MCP asset_create_upload_url smoke test

```bash
curl -X POST http://localhost:8310/api/v1/mcp/asset/create-upload-url \
  -H 'Content-Type: application/json' \
  -d '{"filename":"mcp-asset.txt","mime_type":"text/plain","size_bytes":12,"asset_type":"file"}'
```

Expected:

```text
asset_id is present
storage_key starts with attachments/local-dev/
upload_url is present
asset.kind=internal
asset.sync_status=pending
```

### 4. MCP asset_register_external_url smoke test

```bash
curl -X POST http://localhost:8310/api/v1/mcp/asset/register-external-url \
  -H 'Content-Type: application/json' \
  -d '{"external_url":"https://example.com/mcp-link","title":"MCP external link","asset_type":"link"}'
```

Expected:

```text
asset.kind=external
asset.external_url=https://example.com/mcp-link
asset.sync_status=synced
```

### 5. Invalid asset_type validation

```bash
curl -i -X POST http://localhost:8310/api/v1/mcp/asset/create-upload-url \
  -H 'Content-Type: application/json' \
  -d '{"filename":"bad.txt","asset_type":"invalid"}'
```

Expected:

```text
HTTP/1.1 422 Unprocessable Entity
```

## Protocol Validation

Run protocol tests after enum changes:

```bash
pnpm --filter @lifly/protocol test
```
