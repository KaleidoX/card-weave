pub struct AppHost {
    inner: card_weave_app_host::Host,
}
impl AppHost {
    #[flutter_rust_bridge::frb(sync)]
    pub fn new() -> Self {
        Self {
            inner: card_weave_app_host::Host::new(),
        }
    }
    pub fn initialize(&self, path: String, create: bool, dataset: Option<String>) -> String {
        self.inner.initialize(path, create, dataset)
    }
    pub fn execute(&self, request: String) -> String {
        self.inner.execute(request)
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn begin_sync(&self) -> bool {
        self.inner.begin_sync()
    }
    pub fn synchronize(&self, configuration: String) -> String {
        self.inner.synchronize(configuration)
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.inner.cancel();
    }
}
