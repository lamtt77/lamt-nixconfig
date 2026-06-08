use std::process::Command;

/// Clean local known_hosts file of entries matching the IP and hostname
pub fn remove_known_host_keys(ip: &str, hostname: &str) -> Result<(), Box<dyn std::error::Error>> {
    let _ = Command::new("ssh-keygen").args(["-R", ip]).output();
    let _ = Command::new("ssh-keygen").args(["-R", hostname]).output();
    Ok(())
}
