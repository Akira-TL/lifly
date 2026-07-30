# PowerSync Web 运行资源

这些文件是 Flutter Web 本地数据库运行时的一部分：

```text
sqlite3.wasm
powersync_db.worker.js
powersync_sync.worker.js
```

当前来源：`powersync 1.18.0` 官方 Release。

生成命令：

```bash
flutter pub get
dart run powersync:setup_web
```

更新 `powersync` 依赖后必须重新执行生成命令，并同步更新 `powersync-assets.sha256`。缺少这些文件时，Flutter Web Server 会把 `/sqlite3.wasm` 回退为 `index.html`，浏览器随后因 `text/html` MIME 类型拒绝编译 WebAssembly，Local Core 页面也会连锁加载失败。
