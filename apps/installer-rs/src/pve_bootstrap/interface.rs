use std::fs;
use std::process::Command;

pub fn validate_interface(
    interface: &str,
    listen_ip: &str,
    force: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    // 1. Check if interface exists
    let sys_path = format!("/sys/class/net/{}", interface);
    if !fs::metadata(&sys_path).is_ok() {
        return Err(format!("Interface '{}' does not exist", interface).into());
    }

    // 2. Reject wireless unless forced
    let is_wireless = fs::metadata(format!("{}/wireless", sys_path)).is_ok()
        || fs::metadata(format!("{}/phy80211", sys_path)).is_ok();
    if is_wireless && !force {
        return Err(format!(
            "Interface '{}' is a wireless interface. Reinstalling over Wi-Fi is unsafe. Use --force to override.",
            interface
        )
        .into());
    }

    // 3. Reject default route interface unless forced
    if is_default_route_interface(interface) && !force {
        return Err(format!(
            "Interface '{}' is the default route interface. Binding bootstrap services here could conflict with active production networks. Use --force to override.",
            interface
        )
        .into());
    }

    // 4. Verify listen IP exists on the interface
    if !has_ip_address(interface, listen_ip)? {
        return Err(format!(
            "IP address '{}' is not configured on interface '{}'",
            listen_ip, interface
        )
        .into());
    }

    Ok(())
}

fn is_default_route_interface(interface: &str) -> bool {
    if let Ok(route_content) = fs::read_to_string("/proc/net/route") {
        for line in route_content.lines().skip(1) {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 8 {
                let iface = parts[0];
                let dest = parts[1];
                let mask = parts[7];
                // Destination 00000000 and Mask 00000000 means default route
                if iface == interface && dest == "00000000" && mask == "00000000" {
                    return true;
                }
            }
        }
    }
    false
}

fn has_ip_address(interface: &str, ip: &str) -> Result<bool, Box<dyn std::error::Error>> {
    let output = Command::new("ip")
        .args(["addr", "show", "dev", interface])
        .output()?;

    if !output.status.success() {
        return Err(format!(
            "Failed to execute 'ip addr' command: {}",
            String::from_utf8_lossy(&output.stderr)
        )
        .into());
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    Ok(stdout.contains(ip))
}
