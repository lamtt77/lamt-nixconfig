use super::VirtualizationProvider;
use crate::context::RuntimeContext;
use crate::process::CommandExecutor;
use crate::process::LogTarget;
use crate::log_status;
use std::sync::{Arc, Mutex};

pub struct DigitalOceanProvider {
    hostname: String,
    region: String,
    size: String,
    image: String,
    log_target: Arc<Mutex<LogTarget>>,
}

impl DigitalOceanProvider {
    pub fn new(ctx: &RuntimeContext, log_target: Arc<Mutex<LogTarget>>) -> Self {
        Self {
            hostname: ctx.hostname.clone(),
            region: ctx.deployment.digitalocean.region.clone(),
            size: ctx.deployment.digitalocean.size.clone(),
            image: ctx.deployment.digitalocean.image.clone(),
            log_target,
        }
    }
}

impl VirtualizationProvider for DigitalOceanProvider {
    fn exists(&self) -> bool {
        let check_args = ["compute", "droplet", "get", &self.hostname];
        CommandExecutor::execute("doctl", &check_args, Arc::clone(&self.log_target)).is_ok()
    }

    fn create(&self) -> Result<(), Box<dyn std::error::Error>> {
        println!("Checking if droplet '{}' already exists...", self.hostname);
        
        if self.exists() {
            println!("Droplet '{}' already exists. Reusing instance.", self.hostname);
            return Ok(());
        }

        println!(
            "Provisioning new DigitalOcean droplet '{}' ({}, {})...",
            self.hostname, self.region, self.size
        );
        
        let create_args = [
            "compute",
            "droplet",
            "create",
            &self.hostname,
            "--region",
            &self.region,
            "--size",
            &self.size,
            "--image",
            &self.image,
            "--tag-names",
            "nixos,installer",
            "--wait",
        ];

        CommandExecutor::execute("doctl", &create_args, Arc::clone(&self.log_target))?;
        Ok(())
    }

    fn destroy(&self) -> Result<(), Box<dyn std::error::Error>> {
        println!("Requesting destroy for DigitalOcean droplet '{}'...", self.hostname);
        let delete_args = [
            "compute",
            "droplet",
            "delete",
            &self.hostname,
            "--force",
        ];
        
        CommandExecutor::execute("doctl", &delete_args, Arc::clone(&self.log_target))?;
        Ok(())
    }

    fn get_ip(&self) -> Result<String, Box<dyn std::error::Error>> {
        log_status!(self.log_target, "Resolving public IP for droplet '{}'...", self.hostname);
        let args = [
            "compute",
            "droplet",
            "get",
            &self.hostname,
            "--format",
            "PublicIPv4",
            "--no-header",
        ];
        let silent_log = Arc::new(Mutex::new(LogTarget::Silent));
        let ip_out = CommandExecutor::execute("doctl", &args, silent_log)?;
        let ip = ip_out.trim().to_string();
        
        if ip.is_empty() {
            return Err("DigitalOcean returned empty Public IP".into());
        }
        
        Ok(ip)
    }
}
