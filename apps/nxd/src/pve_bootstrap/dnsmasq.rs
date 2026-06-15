use std::fs;
use std::net::{TcpListener, UdpSocket};
use std::path::Path;
use std::process::{Child, Command, Stdio};

pub fn check_ports_available(listen_ip: &str) -> Result<(), Box<dyn std::error::Error>> {
	if UdpSocket::bind((listen_ip, 67)).is_err() {
		return Err(format!("UDP port 67 (DHCP) is already occupied on {}", listen_ip).into());
	}
	if UdpSocket::bind((listen_ip, 69)).is_err() {
		return Err(format!("UDP port 69 (TFTP) is already occupied on {}", listen_ip).into());
	}
	if TcpListener::bind((listen_ip, 80)).is_err() {
		return Err(format!("TCP port 80 (HTTP) is already occupied on {}", listen_ip).into());
	}
	Ok(())
}

pub fn start_dnsmasq(
	interface: &str,
	listen_ip: &str,
	dhcp_range: &str,
	assets_dir: &str,
	workdir: &Path,
) -> Result<Child, Box<dyn std::error::Error>> {
	let config_path = workdir.join("dnsmasq.conf");
	let dhcp_range_param = if dhcp_range.contains(',') {
		format!("{},12h", dhcp_range)
	} else {
		return Err("Invalid DHCP range format. Expected 'start,end'".into());
	};

	let config_content = format!(
		"interface={}\n\
         bind-interfaces\n\
         port=0\n\
         dhcp-range={}\n\
         dhcp-option=option:router,{}\n\
         dhcp-option=option:dns-server,{}\n\
         enable-tftp\n\
         tftp-root={}\n\
         dhcp-boot=tag:pxe,ipxe/undionly.kpxe\n\
         dhcp-boot=tag:efi,ipxe/ipxe.efi\n\
         dhcp-boot=autoexec.ipxe\n\
         dhcp-match=set:efi,option:client-arch,7\n\
         dhcp-match=set:efi,option:client-arch,9\n\
         dhcp-match=set:efi,option:client-arch,11\n\
         dhcp-match=set:pxe,option:client-arch,0\n\
         log-dhcp\n",
		interface, dhcp_range_param, listen_ip, listen_ip, assets_dir
	);

	fs::write(&config_path, config_content)?;

	println!("Starting dnsmasq process...");
	let child = Command::new("dnsmasq")
        .arg("-C")
        .arg(config_path)
        .arg("-d") // Keep in foreground
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;

	Ok(child)
}
