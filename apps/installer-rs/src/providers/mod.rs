use crate::process::Logger;

pub trait VirtualizationProvider {
    fn create(&self) -> Result<(), Box<dyn std::error::Error>>;
    fn destroy(&self) -> Result<(), Box<dyn std::error::Error>>;
    fn get_ip(&self, poll: bool) -> Result<String, Box<dyn std::error::Error>>;
    fn exists(&self) -> bool;
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProviderIpMode {
    NonPolling,
    PollUntilReady,
}

impl ProviderIpMode {
    fn should_poll(self) -> bool {
        matches!(self, Self::PollUntilReady)
    }
}

pub fn get_provider_ip(
    provider: &dyn VirtualizationProvider,
    mode: ProviderIpMode,
) -> Result<String, Box<dyn std::error::Error>> {
    provider.get_ip(mode.should_poll())
}

pub fn ensure_instance(
    provider: Option<Box<dyn VirtualizationProvider>>,
    redeploy: bool,
    logger: Logger,
) -> Result<Option<Box<dyn VirtualizationProvider>>, Box<dyn std::error::Error>> {
    let Some(ref p) = provider else {
        return Ok(None);
    };

    if redeploy {
        info!(logger, "Redeploy: Destroying existing instance...");
        let _ = p.destroy();
        info!(logger, "Redeploy: Re-creating instance...");
        p.create()?;
    } else if !p.exists() {
        info!(
            logger,
            "Provider instance does not exist. Creating VM/Droplet..."
        );
        p.create()?;
    }

    Ok(provider)
}

pub fn should_skip_existing_provider_deploy(
    provider_exists: bool,
    redeploy: bool,
    overwrite: bool,
    convert_to: bool,
) -> bool {
    provider_exists && !redeploy && !overwrite && !convert_to
}

pub mod digitalocean;
pub mod proxmox;
pub mod vmware;

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[derive(Default)]
    struct ProviderState {
        exists: bool,
        create_calls: usize,
        destroy_calls: usize,
    }

    struct MockProvider {
        state: Arc<Mutex<ProviderState>>,
        requested_polls: Arc<Mutex<Vec<bool>>>,
    }

    impl MockProvider {
        fn new(state: Arc<Mutex<ProviderState>>) -> Self {
            Self {
                state,
                requested_polls: Arc::new(Mutex::new(Vec::new())),
            }
        }

        fn with_poll_recorder(requested_polls: Arc<Mutex<Vec<bool>>>) -> Self {
            Self {
                state: Arc::new(Mutex::new(ProviderState::default())),
                requested_polls,
            }
        }
    }

    impl VirtualizationProvider for MockProvider {
        fn create(&self) -> Result<(), Box<dyn std::error::Error>> {
            let mut state = self.state.lock().unwrap();
            state.create_calls += 1;
            state.exists = true;
            Ok(())
        }

        fn destroy(&self) -> Result<(), Box<dyn std::error::Error>> {
            let mut state = self.state.lock().unwrap();
            state.destroy_calls += 1;
            state.exists = false;
            Ok(())
        }

        fn get_ip(&self, poll: bool) -> Result<String, Box<dyn std::error::Error>> {
            self.requested_polls.lock().unwrap().push(poll);
            Ok(String::new())
        }

        fn exists(&self) -> bool {
            self.state.lock().unwrap().exists
        }
    }

    fn silent_log() -> Logger {
        Logger::silent()
    }

    #[test]
    fn provider_lifecycle_noops_without_provider() {
        ensure_instance(None, false, silent_log()).unwrap();
    }

    #[test]
    fn provider_ip_modes_pass_expected_poll_flags() {
        let requested_polls = Arc::new(Mutex::new(Vec::new()));
        let provider = MockProvider::with_poll_recorder(requested_polls.clone());

        get_provider_ip(&provider, ProviderIpMode::NonPolling).unwrap();
        get_provider_ip(&provider, ProviderIpMode::PollUntilReady).unwrap();

        assert_eq!(*requested_polls.lock().unwrap(), vec![false, true]);
    }

    #[test]
    fn provider_lifecycle_creates_missing_provider() {
        let state = Arc::new(Mutex::new(ProviderState::default()));
        let provider = MockProvider::new(state.clone());

        ensure_instance(Some(Box::new(provider)), false, silent_log()).unwrap();

        let state = state.lock().unwrap();
        assert!(state.exists);
        assert_eq!(state.create_calls, 1);
        assert_eq!(state.destroy_calls, 0);
    }

    #[test]
    fn provider_lifecycle_noops_existing_provider() {
        let state = Arc::new(Mutex::new(ProviderState {
            exists: true,
            ..ProviderState::default()
        }));
        let provider = MockProvider::new(state.clone());

        ensure_instance(Some(Box::new(provider)), false, silent_log()).unwrap();

        let state = state.lock().unwrap();
        assert!(state.exists);
        assert_eq!(state.create_calls, 0);
        assert_eq!(state.destroy_calls, 0);
    }

    #[test]
    fn provider_lifecycle_redeploys_provider() {
        let state = Arc::new(Mutex::new(ProviderState {
            exists: true,
            ..ProviderState::default()
        }));
        let provider = MockProvider::new(state.clone());

        ensure_instance(Some(Box::new(provider)), true, silent_log()).unwrap();

        let state = state.lock().unwrap();
        assert!(state.exists);
        assert_eq!(state.create_calls, 1);
        assert_eq!(state.destroy_calls, 1);
    }

    #[test]
    fn skips_existing_provider_deploy_by_default() {
        assert!(should_skip_existing_provider_deploy(
            true, false, false, false
        ));
    }

    #[test]
    fn does_not_skip_existing_provider_with_explicit_destructive_flags() {
        assert!(!should_skip_existing_provider_deploy(
            true, true, false, false
        ));
        assert!(!should_skip_existing_provider_deploy(
            true, false, true, false
        ));
        assert!(!should_skip_existing_provider_deploy(
            true, false, false, true
        ));
        assert!(!should_skip_existing_provider_deploy(
            false, false, false, false
        ));
    }
}
