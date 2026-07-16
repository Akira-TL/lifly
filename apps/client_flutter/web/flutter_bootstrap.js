{{flutter_js}}
{{flutter_build_config}}

(() => {
  const startup = globalThis.liflyStartup;
  const mark = (name, detail) => startup?.mark(name, detail);
  const setStatus = (message) => startup?.setStatus(message);

  setStatus('正在加载应用入口');
  _flutter.loader.load({
    onEntrypointLoaded: async (engineInitializer) => {
      mark('lifly-entrypoint-loaded');
      setStatus('正在初始化核心引擎');
      try {
        const appRunner = await engineInitializer.initializeEngine();
        mark('lifly-engine-initialized');
        setStatus('正在显示核心界面');
        await appRunner.runApp();
        mark('lifly-run-app-resolved');
      } catch (error) {
        mark('lifly-bootstrap-failed', { message: String(error) });
        setStatus('启动失败，请刷新页面重试');
        throw error;
      }
    },
  });
})();
