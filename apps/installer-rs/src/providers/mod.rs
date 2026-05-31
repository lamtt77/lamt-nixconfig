pub trait VirtualizationProvider {
    fn create(&self) -> Result<(), Box<dyn std::error::Error>>;
    fn destroy(&self) -> Result<(), Box<dyn std::error::Error>>;
    fn get_ip(&self) -> Result<String, Box<dyn std::error::Error>>;
    fn exists(&self) -> bool;
}

pub mod proxmox;
pub mod vmware;
pub mod digitalocean;
