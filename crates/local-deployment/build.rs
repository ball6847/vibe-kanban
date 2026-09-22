use std::path::Path;

fn main() {
    // Load .env from the workspace root
    let workspace_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let env_file = workspace_root.join(".env");
    dotenv::from_path(&env_file).ok();

    if env_file.exists() {
        println!("cargo:rerun-if-changed={}", env_file.display());
    }
}
