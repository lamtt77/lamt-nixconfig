use crate::process::Logger;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProviderKind {
	Proxmox,
	Vmware,
	DigitalOcean,
	Wsl,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProviderState {
	Missing,
	Present,
	Running,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TargetEndpoint {
	Ssh { host: String, port: u16, proxy_jump: Option<String> },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ProviderCapabilities {
	pub requires_bootstrap_artifact: bool,
	pub supports_recreate: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ProviderSnapshot {
	pub kind: ProviderKind,
	pub state: ProviderState,
	pub capabilities: ProviderCapabilities,
}

pub trait Provider {
	fn kind(&self) -> ProviderKind;
	fn resource_identity(&self) -> String;
	fn create(&self) -> Result<(), Box<dyn std::error::Error>>;
	fn destroy(&self) -> Result<(), Box<dyn std::error::Error>>;
	fn get_ip(&self, poll: bool) -> Result<String, Box<dyn std::error::Error>>;
	fn inspect(&self) -> Result<ProviderState, Box<dyn std::error::Error>>;

	fn capabilities(&self) -> ProviderCapabilities {
		ProviderCapabilities {
			requires_bootstrap_artifact: self.kind() == ProviderKind::Wsl,
			supports_recreate: true,
		}
	}

	fn endpoint(&self, poll: bool) -> Result<TargetEndpoint, Box<dyn std::error::Error>> {
		Ok(TargetEndpoint::Ssh { host: self.get_ip(poll)?, port: 22, proxy_jump: None })
	}
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
	provider: &dyn Provider,
	mode: ProviderIpMode,
) -> Result<String, Box<dyn std::error::Error>> {
	provider.get_ip(mode.should_poll())
}

pub fn inspect_provider(
	provider: &dyn Provider,
) -> Result<ProviderSnapshot, Box<dyn std::error::Error>> {
	Ok(ProviderSnapshot {
		kind: provider.kind(),
		state: provider.inspect()?,
		capabilities: provider.capabilities(),
	})
}

pub fn ensure_instance(
	provider: Option<Box<dyn Provider>>,
	state: Option<ProviderState>,
	redeploy: bool,
	logger: Logger,
) -> Result<Option<Box<dyn Provider>>, Box<dyn std::error::Error>> {
	let Some(ref p) = provider else {
		return Ok(None);
	};

	if redeploy {
		if state != Some(ProviderState::Missing) {
			info!(logger, "Redeploy: Destroying existing instance...");
			p.destroy()?;
		}
		info!(logger, "Redeploy: Re-creating instance...");
		p.create()?;
	} else if state == Some(ProviderState::Missing) {
		info!(logger, "Provider instance does not exist. Creating VM/Droplet...");
		p.create()?;
	}

	Ok(provider)
}

pub fn should_skip_existing_provider_deploy(
	provider_exists: bool,
	redeploy: bool,
	overwrite: bool,
) -> bool {
	provider_exists && !redeploy && !overwrite
}

pub mod digitalocean;
pub mod proxmox;
pub mod proxmox_create;
pub mod proxmox_ip;
pub mod proxmox_preflight;
pub mod vmware;
pub mod wsl;

#[cfg(test)]
mod tests {
	use super::*;
	use std::sync::{Arc, Mutex};

	#[derive(Default)]
	struct MockProviderState {
		exists: bool,
		create_calls: usize,
		destroy_calls: usize,
	}

	struct MockProvider {
		state: Arc<Mutex<MockProviderState>>,
		requested_polls: Arc<Mutex<Vec<bool>>>,
	}

	impl MockProvider {
		fn new(state: Arc<Mutex<MockProviderState>>) -> Self {
			Self { state, requested_polls: Arc::new(Mutex::new(Vec::new())) }
		}

		fn with_poll_recorder(requested_polls: Arc<Mutex<Vec<bool>>>) -> Self {
			Self { state: Arc::new(Mutex::new(MockProviderState::default())), requested_polls }
		}
	}

	impl Provider for MockProvider {
		fn kind(&self) -> ProviderKind {
			ProviderKind::Proxmox
		}
		fn resource_identity(&self) -> String {
			"mock".to_string()
		}
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

		fn inspect(&self) -> Result<ProviderState, Box<dyn std::error::Error>> {
			Ok(if self.state.lock().unwrap().exists {
				ProviderState::Present
			} else {
				ProviderState::Missing
			})
		}
	}

	fn silent_log() -> Logger {
		Logger::silent()
	}

	#[test]
	fn provider_lifecycle_noops_without_provider() {
		ensure_instance(None, None, false, silent_log()).unwrap();
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
		let state = Arc::new(Mutex::new(MockProviderState::default()));
		let provider = MockProvider::new(state.clone());

		ensure_instance(Some(Box::new(provider)), Some(ProviderState::Missing), false, silent_log())
			.unwrap();

		let state = state.lock().unwrap();
		assert!(state.exists);
		assert_eq!(state.create_calls, 1);
		assert_eq!(state.destroy_calls, 0);
	}

	#[test]
	fn provider_lifecycle_noops_existing_provider() {
		let state =
			Arc::new(Mutex::new(MockProviderState { exists: true, ..MockProviderState::default() }));
		let provider = MockProvider::new(state.clone());

		ensure_instance(Some(Box::new(provider)), Some(ProviderState::Present), false, silent_log())
			.unwrap();

		let state = state.lock().unwrap();
		assert!(state.exists);
		assert_eq!(state.create_calls, 0);
		assert_eq!(state.destroy_calls, 0);
	}

	#[test]
	fn provider_lifecycle_redeploys_provider() {
		let state =
			Arc::new(Mutex::new(MockProviderState { exists: true, ..MockProviderState::default() }));
		let provider = MockProvider::new(state.clone());

		ensure_instance(Some(Box::new(provider)), Some(ProviderState::Present), true, silent_log())
			.unwrap();

		let state = state.lock().unwrap();
		assert!(state.exists);
		assert_eq!(state.create_calls, 1);
		assert_eq!(state.destroy_calls, 1);
	}

	#[test]
	fn skips_existing_provider_deploy_by_default() {
		assert!(should_skip_existing_provider_deploy(true, false, false));
	}

	#[test]
	fn does_not_skip_existing_provider_with_explicit_destructive_flags() {
		assert!(!should_skip_existing_provider_deploy(true, true, false));
		assert!(!should_skip_existing_provider_deploy(true, false, true));
		assert!(!should_skip_existing_provider_deploy(false, false, false));
	}
}
