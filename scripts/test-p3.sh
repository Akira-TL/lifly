#!/bin/bash
set -e

API="http://localhost:8310/api/v1"

echo "=== 1. Health Check ==="
curl -s "$API/health"

echo -e "\n\n=== 2. 创建上传 URL ==="
UPLOAD_RES=$(curl -s -X POST "$API/assets/create-upload-url" \
  -H "Content-Type: application/json" \
  -d '{"filename":"test.png","mime_type":"image/png","size_bytes":1024,"asset_type":"image"}')
echo "$UPLOAD_RES"
ASSET_ID=$(echo "$UPLOAD_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['asset_id'])")
echo "Asset ID: $ASSET_ID"

echo -e "\n\n=== 3. 列表 Assets ==="
curl -s "$API/assets?limit=5"

echo -e "\n\n=== 4. 获取单个 Asset ==="
curl -s "$API/assets/$ASSET_ID"

echo -e "\n\n=== 5. 获取下载 URL ==="
curl -s "$API/assets/$ASSET_ID/download-url"

echo -e "\n\n=== 6. 上传完成回调 ==="
curl -s -X POST "$API/assets/$ASSET_ID/upload-complete" \
  -H "Content-Type: application/json" \
  -d '{"sha256":"abc123"}'

echo -e "\n\n=== 7. 注册外部链接 ==="
curl -s -X POST "$API/assets/register-external-url" \
  -H "Content-Type: application/json" \
  -d '{"external_url":"https://example.com/doc.pdf", "title":"参考文档", "asset_type":"pdf", "external_provider":"web"}'

echo -e "\n\n=== 8. 删除 Asset ==="
curl -s -X DELETE "$API/assets/$ASSET_ID"

echo -e "\n\n=== 9. 获取不存在的 Asset (应 404) ==="
curl -s "$API/assets/non-existent-id"

echo -e "\n\n=== 全部测试完成 ==="
