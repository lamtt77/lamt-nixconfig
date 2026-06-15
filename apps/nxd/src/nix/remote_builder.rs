pub fn check_builder_compatible(builder_ssh: &str, target_system: &str) -> bool {
	let Some(stdout) = crate::remote::ssh::probe_stdout(builder_ssh, "uname -m", 2) else {
		return false;
	};

	let builder_system = match stdout.trim() {
		"x86_64" => "x86_64-linux",
		"aarch64" | "arm64" => "aarch64-linux",
		_ => "",
	};

	builder_system == target_system
}
