use std::io::{self, Read};

use anyhow::{Context, Result};
use lifly_opaque_helper::{default_server_setup_path, handle_json};

fn main() {
    if let Err(error) = run() {
        eprintln!("lifly-opaque-helper: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let mut input = String::new();
    io::stdin()
        .read_to_string(&mut input)
        .context("failed to read helper request")?;
    let setup_path = default_server_setup_path()?;
    let response = handle_json(input.trim(), &setup_path)?;
    println!("{}", serde_json::to_string(&response)?);
    Ok(())
}
