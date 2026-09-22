use std::{path::Path, sync::Arc};

use async_trait::async_trait;
use derivative::Derivative;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use ts_rs::TS;
use workspace_utils::msg_store::MsgStore;

use crate::{
    approvals::ExecutorApprovalService,
    command::{CmdOverrides, CommandBuildError, CommandBuilder, apply_overrides},
    env::ExecutionEnv,
    executor_discovery::ExecutorDiscoveredOptions,
    executors::{
        AppendPrompt, AvailabilityInfo, BaseCodingAgent, ExecutorError, SlashCommandDescription,
        SpawnedChild, StandardCodingAgentExecutor, gemini::AcpAgentHarness,
    },
    logs::utils::patch,
    model_selector::{
        ModelInfo, ModelProvider, ModelSelectorConfig, PermissionPolicy, ReasoningOption,
    },
    profile::ExecutorConfig,
};

/// pi applies its model and thinking level through ACP **session config options** (`model`, `thought_level`), which the
/// pinned `agent-client-protocol` 0.8 cannot send. The adapter we ship ([`PI_ACP_PACKAGE`]) accepts the legacy
/// `session/set_model` request this client does send and translates it into those options, splitting the `:<level>` suffix
/// off the model id, so a choice made in the UI reaches pi. Keep this `true` only while the pinned fork carries that shim.
const MODEL_SELECTION_SUPPORTED: bool = true;

/// Pinned `pi-acp` (ACP adapter for the `pi` coding agent), taken from our fork at a release tag.
///
/// The fork adds a compatibility shim for the legacy `session/set_model` request: upstream adapters built on current ACP
/// SDKs only dispatch `session/set_config_option`, which the pinned `agent-client-protocol` 0.8 cannot send, so a model
/// choice would otherwise be silently dropped. See `docs/agents/pi.mdx`.
const PI_ACP_PACKAGE: &str = "github:ball6847/pi-acp#v0.0.34";

#[derive(Derivative, Clone, Serialize, Deserialize, TS, JsonSchema)]
#[derivative(Debug, PartialEq)]
pub struct Pi {
    #[serde(default)]
    pub append_prompt: AppendPrompt,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    /// pi thinking level (`minimal`, `low`, `medium`, `high`). Applied as the `:<level>` suffix of the
    /// model id handed to pi over ACP.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reasoning: Option<String>,
    /// Skip approval prompts (pi asks the client for tool permissions, so this is enforced
    /// client-side via [`AcpAgentHarness`] rather than a CLI flag).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub yolo: Option<bool>,
    #[serde(flatten)]
    pub cmd: CmdOverrides,
    #[serde(skip)]
    #[ts(skip)]
    #[derivative(Debug = "ignore", PartialEq = "ignore")]
    pub approvals: Option<Arc<dyn ExecutorApprovalService>>,
}

impl Pi {
    /// Thinking levels every pi model accepts, in pi's own order (`pi --thinking <level>`: off, minimal, low,
    /// medium, high, xhigh, max — `xhigh`/`max` only where the model's `thinkingLevelMap` declares them).
    const THINKING_LEVELS: [&'static str; 5] = ["off", "minimal", "low", "medium", "high"];

    fn build_command_builder(&self) -> Result<CommandBuilder, CommandBuildError> {
        // No ACP or model flags: `pi-acp` takes none, and the model is applied over ACP
        // (`session/set_session_model` via `AcpAgentHarness::with_model`).
        let builder = CommandBuilder::new(format!("npx -y {PI_ACP_PACKAGE}"));

        apply_overrides(builder, &self.cmd)
    }

    /// Effective model id for pi: `provider/model` plus the optional `:<thinking>` suffix.
    ///
    /// When only a thinking level is chosen, pi's own configured default model is used as the base so the
    /// level is not silently dropped (the ACP harness only sets a model when one is supplied).
    fn effective_model(&self) -> Option<String> {
        let model = match self.model.clone() {
            Some(model) => model,
            None => default_model_from_settings()?,
        };
        Some(match self.reasoning.as_deref() {
            Some(level) if !level.is_empty() => format!("{model}:{level}"),
            _ => model,
        })
    }

    /// Path of pi's downloaded model catalogue (provider -> models).
    fn model_catalogue_path() -> Option<std::path::PathBuf> {
        pi_agent_dir().map(|dir| dir.join("models-store.json"))
    }
}

/// pi's agent directory (`~/.pi/agent`), where its settings, auth and model catalogue live.
fn pi_agent_dir() -> Option<std::path::PathBuf> {
    dirs::home_dir().map(|home| home.join(".pi").join("agent"))
}

/// Classify pi's installation state: an authenticated install reports `LoginDetected`, an install without
/// credentials reports `InstallationFound`, and nothing present reports `NotFound` (mirrors codex).
fn availability_info(agent_dir: Option<&Path>) -> AvailabilityInfo {
    let Some(dir) = agent_dir else {
        return AvailabilityInfo::NotFound;
    };

    let auth_timestamp = std::fs::metadata(dir.join("auth.json"))
        .ok()
        .and_then(|metadata| metadata.modified().ok())
        .and_then(|modified| modified.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|duration| duration.as_secs() as i64);

    if let Some(last_auth_timestamp) = auth_timestamp {
        return AvailabilityInfo::LoginDetected {
            last_auth_timestamp,
        };
    }

    if dir.join("settings.json").exists() {
        AvailabilityInfo::InstallationFound
    } else {
        AvailabilityInfo::NotFound
    }
}

/// Split a provider-qualified model id (`zenmux/deepseek/deepseek-v4.1-flash`) into provider and model id.
///
/// Vibe Kanban composes `provider_id` and `id` itself when it hands a selection back (`(provider)/(id)`), so the model
/// entries must carry the model id **without** its provider prefix.
fn split_provider(model_id: &str) -> (Option<String>, String) {
    match model_id.split_once('/') {
        Some((provider, rest)) if !provider.is_empty() && !rest.is_empty() => {
            (Some(provider.to_string()), rest.to_string())
        }
        _ => (None, model_id.to_string()),
    }
}

/// The provider-qualified form the UI compares against `default_model`.
fn full_model_id(model: &ModelInfo) -> String {
    match model.provider_id.as_deref() {
        Some(provider) => format!("{provider}/{}", model.id),
        None => model.id.clone(),
    }
}

/// Prepend pi's configured default model when the downloaded catalogue does not contain it, so the model picker
/// can show (and select) the model pi will actually use.
fn with_configured_default(models: Vec<ModelInfo>, default_model: Option<&str>) -> Vec<ModelInfo> {
    let Some(default_model) = default_model else {
        return models;
    };
    if models
        .iter()
        .any(|model| full_model_id(model) == default_model)
    {
        return models;
    }

    let (provider_id, id) = split_provider(default_model);
    let mut with_default = vec![ModelInfo {
        name: default_model.to_string(),
        id,
        provider_id,
        reasoning_options: Vec::new(),
    }];
    with_default.extend(models);
    with_default
}

/// Parse `pi --list-models` output: a header row followed by
/// `provider  model  context  max-out  thinking  images` columns.
///
/// This is pi's own, **auth-filtered** view of what the user can actually run, so it is preferred over the downloaded
/// catalogue (which lists every provider's models, including ones without credentials).
fn models_from_list_models_output(
    output: &str,
    extras: &std::collections::HashMap<String, Vec<String>>,
) -> Vec<ModelInfo> {
    let mut models = Vec::new();
    for line in output.lines().skip(1) {
        let columns: Vec<&str> = line.split_whitespace().collect();
        if columns.len() < 6 {
            continue;
        }
        let (provider, id) = (columns[0], columns[1]);
        let thinking = columns[4].eq_ignore_ascii_case("yes");
        models.push(ModelInfo {
            id: id.to_string(),
            name: id.to_string(),
            provider_id: Some(provider.to_string()),
            reasoning_options: if thinking {
                let mut options = base_reasoning_options();
                if let Some(extra_levels) = extras.get(&format!("{provider}/{id}")) {
                    let mut labels: Vec<String> = Pi::THINKING_LEVELS
                        .iter()
                        .map(|l| (*l).to_string())
                        .collect();
                    labels.extend(extra_levels.iter().cloned());
                    options = ReasoningOption::from_names(labels);
                    options.sort_by_key(|option| {
                        Pi::THINKING_LEVELS
                            .iter()
                            .position(|level| *level == option.id)
                            .unwrap_or(usize::MAX)
                    });
                }
                options
            } else {
                Vec::new()
            },
        });
    }
    models.sort_by(|a, b| full_model_id(a).cmp(&full_model_id(b)));
    models.dedup_by(|a, b| full_model_id(a) == full_model_id(b));
    models
}

/// Ask pi for the models this installation can actually use (`pi --list-models`). Returns `None` when the binary is
/// unavailable or produces no rows, in which case discovery falls back to the downloaded catalogue.
fn read_models_from_cli(catalogue: Option<&serde_json::Value>) -> Option<Vec<ModelInfo>> {
    let output = std::process::Command::new("pi")
        .arg("--list-models")
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let extras = catalogue_extras(catalogue);
    let models = models_from_list_models_output(&String::from_utf8_lossy(&output.stdout), &extras);
    if models.is_empty() {
        None
    } else {
        Some(models)
    }
}

/// pi's base thinking levels in pi's own order, with `high` marked as the default.
fn base_reasoning_options() -> Vec<ReasoningOption> {
    let mut options = ReasoningOption::from_names(Pi::THINKING_LEVELS.map(String::from));
    options.sort_by_key(|option| {
        Pi::THINKING_LEVELS
            .iter()
            .position(|level| *level == option.id)
            .unwrap_or(usize::MAX)
    });
    options
}

/// Extra thinking levels a specific model declares in the catalogue (`thinkingLevelMap`), in a stable order.
fn catalogue_extras(
    catalogue: Option<&serde_json::Value>,
) -> std::collections::HashMap<String, Vec<String>> {
    let mut extras = std::collections::HashMap::new();
    let Some(catalogue) = catalogue else {
        return extras;
    };
    let Some(providers) = catalogue.as_object() else {
        return extras;
    };
    for (provider_id, provider) in providers {
        let Some(entries) = provider.get("models").and_then(|value| value.as_array()) else {
            continue;
        };
        for entry in entries {
            let Some(id) = entry.get("id").and_then(|value| value.as_str()) else {
                continue;
            };
            let Some(map) = entry
                .get("thinkingLevelMap")
                .and_then(|value| value.as_object())
            else {
                continue;
            };
            let extra: Vec<String> = map
                .keys()
                .filter(|level| !Pi::THINKING_LEVELS.contains(&level.as_str()))
                .cloned()
                .collect();
            if !extra.is_empty() {
                extras.insert(format!("{provider_id}/{id}"), extra);
            }
        }
    }
    extras
}

/// Reasoning options for one catalogue entry: none when pi reports `reasoning: false`, otherwise pi's
/// standard levels plus any extra levels the model declares in `thinkingLevelMap` (e.g. `off`, `xhigh`).
fn reasoning_options_for_entry(entry: &serde_json::Value) -> Vec<ReasoningOption> {
    if !entry
        .get("reasoning")
        .and_then(|value| value.as_bool())
        .unwrap_or(false)
    {
        return Vec::new();
    }

    let mut levels: Vec<String> = Pi::THINKING_LEVELS
        .iter()
        .map(|l| (*l).to_string())
        .collect();
    if let Some(map) = entry
        .get("thinkingLevelMap")
        .and_then(|value| value.as_object())
    {
        for level in map.keys() {
            if !levels.iter().any(|existing| existing == level) {
                levels.push(level.clone());
            }
        }
    }

    let mut options = ReasoningOption::from_names(levels);
    options.sort_by_key(|option| {
        Pi::THINKING_LEVELS
            .iter()
            .position(|level| *level == option.id)
            .unwrap_or(usize::MAX)
    });
    options
}

/// Build the selectable model list from pi's model catalogue (`models-store.json`).
///
/// The catalogue is a `{ provider: { models: [{ id, name, .. }] } }` map; pi accepts
/// `provider/model-id` (optionally with `:<thinking>`), so each entry becomes one `ModelInfo`.
/// pi's documented skill locations: `~/.pi/agent/skills`, `~/.agents/skills` (always loaded) and the project-local
/// `.pi/skills` / `.agents/skills` (only when pi trusts the project — see [`project_is_trusted`]).
fn skill_dirs(repo_path: Option<&Path>) -> Vec<std::path::PathBuf> {
    let mut dirs = Vec::new();
    if let Some(home) = dirs::home_dir() {
        dirs.push(home.join(".pi").join("agent").join("skills"));
        dirs.push(home.join(".agents").join("skills"));
    }
    if let Some(repo) = repo_path.filter(|repo| project_is_trusted(repo)) {
        dirs.push(repo.join(".agents").join("skills"));
        dirs.push(repo.join(".pi").join("skills"));
    }
    dirs
}

/// pi only loads project-local skills when the project (or a parent directory) is trusted in
/// `~/.pi/agent/trust.json`; worktrees Vibe Kanban creates under `/var/tmp` are usually not, and advertising commands
/// pi cannot run would be a false affordance. Returns false when the trust file is missing or unreadable.
fn project_is_trusted(repo_path: &Path) -> bool {
    let Some(trust_path) = pi_agent_dir().map(|dir| dir.join("trust.json")) else {
        return false;
    };
    let Ok(contents) = std::fs::read_to_string(trust_path) else {
        return false;
    };
    let Ok(trusted) = serde_json::from_str::<serde_json::Value>(&contents) else {
        return false;
    };
    let Some(entries) = trusted.as_object() else {
        return false;
    };

    let mut candidate = Some(repo_path);
    while let Some(path) = candidate {
        if entries.contains_key(&path.to_string_lossy().to_string()) {
            return true;
        }
        candidate = path.parent();
    }
    false
}

fn parse_skill_frontmatter(contents: &str) -> Option<(String, Option<String>, bool)> {
    let body = contents.strip_prefix("---")?;
    let end = body.find("\n---")?;
    let mut name = None;
    let mut description = None;
    let mut user_invocable = true;
    for line in body[..end].lines() {
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        let value = value
            .trim()
            .trim_matches('"')
            .trim_matches('\'')
            .to_string();
        match key.trim() {
            "name" => name = Some(value),
            "description" => description = Some(value),
            "user-invocable" => user_invocable = value != "false",
            _ => {}
        }
    }
    Some((
        name?,
        description.filter(|d| !d.trim().is_empty()),
        user_invocable,
    ))
}

/// pi skills exposed as `/skill:<name>` commands, mirroring how pi-acp announces them.
fn slash_commands_from_skills(repo_path: Option<&Path>) -> Vec<SlashCommandDescription> {
    let mut commands: Vec<SlashCommandDescription> = Vec::new();
    for dir in skill_dirs(repo_path) {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let skill_file = entry.path().join("SKILL.md");
            let Ok(contents) = std::fs::read_to_string(&skill_file) else {
                continue;
            };
            let Some((name, description, user_invocable)) = parse_skill_frontmatter(&contents)
            else {
                continue;
            };
            if !user_invocable {
                continue;
            }
            let command = SlashCommandDescription {
                name: format!("skill:{name}"),
                description,
            };
            if !commands
                .iter()
                .any(|existing| existing.name == command.name)
            {
                commands.push(command);
            }
        }
    }
    commands.sort_by(|a, b| a.name.cmp(&b.name));
    commands
}

/// Slash commands pi can actually run: one entry per installed user skill.
///
/// pi's own commands (`/model`, `/compact`, ...) and any extension commands live inside a pi session; the adapter
/// announces them over ACP at runtime, so they are deliberately not hardcoded here — a list would advertise commands a
/// given installation may not have (`handoff`/`pickup`, for example, come from optional packages, not pi core).
fn pi_slash_commands(repo_path: Option<&Path>) -> Vec<SlashCommandDescription> {
    merge_slash_commands(Vec::new(), slash_commands_from_skills(repo_path))
}

/// Concatenate command lists, keeping the first entry for each name.
fn merge_slash_commands(
    first: Vec<SlashCommandDescription>,
    second: Vec<SlashCommandDescription>,
) -> Vec<SlashCommandDescription> {
    let mut commands: Vec<SlashCommandDescription> = Vec::new();
    for command in first.into_iter().chain(second) {
        if !commands
            .iter()
            .any(|existing| existing.name == command.name)
        {
            commands.push(command);
        }
    }
    commands
}

fn models_from_catalogue(catalogue: &serde_json::Value) -> Vec<ModelInfo> {
    let mut models = Vec::new();
    let Some(providers) = catalogue.as_object() else {
        return models;
    };

    for (provider_id, provider) in providers {
        let Some(entries) = provider.get("models").and_then(|value| value.as_array()) else {
            continue;
        };
        for entry in entries {
            let Some(id) = entry.get("id").and_then(|value| value.as_str()) else {
                continue;
            };
            let name = entry
                .get("name")
                .and_then(|value| value.as_str())
                .unwrap_or(id);
            let provider_name = entry
                .get("provider")
                .and_then(|value| value.as_str())
                .unwrap_or(provider_id);
            models.push(ModelInfo {
                id: id.to_string(),
                name: name.to_string(),
                provider_id: Some(provider_name.to_string()),
                reasoning_options: reasoning_options_for_entry(entry),
            });
        }
    }

    models.sort_by(|a, b| full_model_id(a).cmp(&full_model_id(b)));
    models.dedup_by(|a, b| full_model_id(a) == full_model_id(b));
    models
}

fn providers_from_models(models: &[ModelInfo]) -> Vec<ModelProvider> {
    let mut providers: Vec<ModelProvider> = models
        .iter()
        .filter_map(|model| model.provider_id.clone())
        .map(|id| ModelProvider {
            name: id.clone(),
            id,
        })
        .collect();
    providers.sort_by(|a, b| a.id.cmp(&b.id));
    providers.dedup_by(|a, b| a.id == b.id);
    providers
}

fn providers_from_catalogue(catalogue: &serde_json::Value) -> Vec<ModelProvider> {
    let mut providers: Vec<ModelProvider> = catalogue
        .as_object()
        .map(|map| map.keys())
        .into_iter()
        .flatten()
        .map(|id| ModelProvider {
            id: id.clone(),
            name: id.clone(),
        })
        .collect();
    providers.sort_by(|a, b| a.id.cmp(&b.id));
    providers
}

/// Read pi's model catalogue. Returns `None` when the file is missing or unreadable,
/// in which case discovery falls back to permissions-only (existing behaviour).
fn read_model_catalogue() -> Option<serde_json::Value> {
    let path = Pi::model_catalogue_path()?;
    read_catalogue_from(&path)
}

/// Read pi's catalogue from an explicit path, warning (rather than failing) when it is missing or malformed.
fn read_catalogue_from(path: &Path) -> Option<serde_json::Value> {
    let contents = match std::fs::read_to_string(&path) {
        Ok(contents) => contents,
        Err(error) => {
            // The picker then shows no models at all, which is confusing without a hint.
            tracing::warn!(
                "pi model catalogue unavailable at {} ({error}); run `pi update` to download it, the model list will be empty",
                path.display()
            );
            return None;
        }
    };
    match serde_json::from_str(&contents) {
        Ok(catalogue) => Some(catalogue),
        Err(error) => {
            tracing::warn!(
                "pi model catalogue at {} is not valid JSON ({error}); run `pi update` to refresh it",
                path.display()
            );
            None
        }
    }
}

/// pi's configured default model (`provider/model`), from its `settings.json`.
fn default_model_from_settings() -> Option<String> {
    let path = pi_agent_dir()?.join("settings.json");
    let contents = std::fs::read_to_string(path).ok()?;
    let settings: serde_json::Value = serde_json::from_str(&contents).ok()?;
    default_model_from_settings_value(&settings)
}

fn default_model_from_settings_value(settings: &serde_json::Value) -> Option<String> {
    let provider = settings.get("defaultProvider")?.as_str()?;
    let model = settings.get("defaultModel")?.as_str()?;
    if provider.is_empty() || model.is_empty() {
        return None;
    }
    Some(format!("{provider}/{model}"))
}

#[async_trait]
impl StandardCodingAgentExecutor for Pi {
    fn apply_overrides(&mut self, executor_config: &ExecutorConfig) {
        if let Some(model_id) = executor_config.model_id.as_ref() {
            self.model = Some(model_id.clone());
        }

        if let Some(reasoning_id) = executor_config.reasoning_id.as_ref() {
            self.reasoning = Some(reasoning_id.clone());
        }

        if let Some(permission_policy) = executor_config.permission_policy.clone() {
            self.yolo = Some(matches!(permission_policy, PermissionPolicy::Auto));
        }
    }

    fn use_approvals(&mut self, approvals: Arc<dyn ExecutorApprovalService>) {
        self.approvals = Some(approvals);
    }

    async fn spawn(
        &self,
        current_dir: &Path,
        prompt: &str,
        env: &ExecutionEnv,
    ) -> Result<SpawnedChild, ExecutorError> {
        let pi_command = self.build_command_builder()?.build_initial()?;
        let combined_prompt = self.append_prompt.combine_prompt(prompt);
        let mut harness = AcpAgentHarness::with_session_namespace("pi_sessions");
        if let Some(model) = self.effective_model() {
            harness = harness.with_model(model);
        }
        let approvals = if self.yolo.unwrap_or(false) {
            None
        } else {
            self.approvals.clone()
        };
        harness
            .spawn_with_command(
                current_dir,
                combined_prompt,
                pi_command,
                env,
                &self.cmd,
                approvals,
            )
            .await
    }

    async fn spawn_follow_up(
        &self,
        current_dir: &Path,
        prompt: &str,
        session_id: &str,
        _reset_to_message_id: Option<&str>,
        env: &ExecutionEnv,
    ) -> Result<SpawnedChild, ExecutorError> {
        let pi_command = self.build_command_builder()?.build_follow_up(&[])?;
        let combined_prompt = self.append_prompt.combine_prompt(prompt);
        let mut harness = AcpAgentHarness::with_session_namespace("pi_sessions");
        if let Some(model) = self.effective_model() {
            harness = harness.with_model(model);
        }
        let approvals = if self.yolo.unwrap_or(false) {
            None
        } else {
            self.approvals.clone()
        };
        harness
            .spawn_follow_up_with_command(
                current_dir,
                combined_prompt,
                session_id,
                pi_command,
                env,
                &self.cmd,
                approvals,
            )
            .await
    }

    fn normalize_logs(
        &self,
        msg_store: Arc<MsgStore>,
        worktree_path: &Path,
    ) -> Vec<tokio::task::JoinHandle<()>> {
        crate::executors::acp::normalize_logs(msg_store, worktree_path)
    }

    /// pi has no MCP support (see `pi` README: "No MCP"), and `pi-acp` advertises
    /// `mcpCapabilities: { http: false, sse: false }`, so there is no config file to write.
    fn default_mcp_config_path(&self) -> Option<std::path::PathBuf> {
        None
    }

    fn get_availability_info(&self) -> AvailabilityInfo {
        availability_info(pi_agent_dir().as_deref())
    }

    fn get_preset_options(&self) -> ExecutorConfig {
        ExecutorConfig {
            executor: BaseCodingAgent::Pi,
            variant: None,
            model_id: self.model.clone(),
            agent_id: None,
            reasoning_id: self.reasoning.clone(),
            permission_policy: Some(if self.yolo.unwrap_or(false) {
                PermissionPolicy::Auto
            } else {
                PermissionPolicy::Supervised
            }),
        }
    }

    async fn discover_options(
        &self,
        _workdir: Option<&std::path::Path>,
        repo_path: Option<&std::path::Path>,
    ) -> Result<futures::stream::BoxStream<'static, json_patch::Patch>, ExecutorError> {
        // Prefer pi's own list (auth-filtered); the downloaded catalogue is the fallback when `pi` is not runnable,
        // and is also used to enrich the CLI list with per-model thinking levels (xhigh/max).
        let catalogue = read_model_catalogue();
        let from_cli = read_models_from_cli(catalogue.as_ref());
        let mut models = match (&from_cli, &catalogue) {
            (Some(models), _) => models.clone(),
            (None, Some(catalogue)) => models_from_catalogue(catalogue),
            (None, None) => vec![],
        };
        let providers = match (&from_cli, &catalogue) {
            (Some(models), _) => providers_from_models(models),
            (None, Some(catalogue)) => providers_from_catalogue(catalogue),
            (None, None) => vec![],
        };
        // Keep the list sorted and unique after any merge.
        models.sort_by(|a, b| full_model_id(a).cmp(&full_model_id(b)));
        models.dedup_by(|a, b| full_model_id(a) == full_model_id(b));
        // Surface pi's configured default when the user has not pinned one, so the picker shows the real model
        // instead of a bare "Default" (the id only — the thinking suffix is applied at spawn time).
        let default_model = self.model.clone().or_else(default_model_from_settings);

        // pi's configured model is not always in the downloaded catalogue (custom providers live in
        // `models.json`), so add it explicitly — otherwise the picker cannot select the default at all.
        let models = with_configured_default(models, default_model.as_deref());

        let slash_commands = pi_slash_commands(repo_path);
        let permissions = vec![PermissionPolicy::Auto, PermissionPolicy::Supervised];
        let model_selector = if MODEL_SELECTION_SUPPORTED {
            ModelSelectorConfig {
                providers,
                models,
                default_model,
                permissions,
                ..Default::default()
            }
        } else {
            // Honest empty selector: a list here would be a false affordance.
            ModelSelectorConfig {
                permissions,
                ..Default::default()
            }
        };
        let options = ExecutorDiscoveredOptions {
            model_selector,
            slash_commands,
            ..Default::default()
        };
        Ok(Box::pin(futures::stream::once(async move {
            patch::executor_discovered_options(options)
        })))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::executors::CodingAgent;

    fn pi_with(model: Option<&str>) -> Pi {
        Pi {
            append_prompt: Default::default(),
            model: model.map(str::to_string),
            reasoning: None,
            yolo: None,
            cmd: CmdOverrides::default(),
            approvals: None,
        }
    }

    #[test]
    fn model_selection_is_advertised_when_supported() {
        if !MODEL_SELECTION_SUPPORTED {
            return; // selection is switched off: discovery must offer no models
        }
        let t = tokio::runtime::Runtime::new().expect("rt");
        let options = t.block_on(async {
            use futures::StreamExt;
            let pi = pi_with(None);
            let mut stream = pi.discover_options(None, None).await.expect("discovery");
            let patch = stream.next().await.expect("patch");
            serde_json::to_value(patch).expect("json")
        });
        let value = options
            .as_array()
            .and_then(|ops| {
                ops.iter()
                    .find(|op| op["path"] == "/options")
                    .map(|op| op["value"].clone())
            })
            .expect("an /options patch");
        let models = value["model_selector"]["models"]
            .as_array()
            .expect("models array");
        assert!(
            !models.is_empty(),
            "the adapter applies model choices, so they must be offered"
        );
        assert!(
            models.iter().any(|m| m["reasoning_options"]
                .as_array()
                .is_some_and(|options| !options.is_empty())),
            "at least one model should expose thinking levels"
        );
    }

    #[test]
    fn list_models_output_is_parsed_with_thinking_flag() {
        let output = "provider     model        context  max-out  thinking  images\n\
empiriolabs  glm-5-3     1.0M     131.1K   yes       yes   \n\
kimi-coding  k3          1.0M     131.1K   yes       no    \n\
acme         plain-1     8K       4K       no        no    \n";
        let models = models_from_list_models_output(output, &std::collections::HashMap::new());
        let ids: Vec<&str> = models.iter().map(|m| m.id.as_str()).collect();
        assert_eq!(ids, vec!["plain-1", "glm-5-3", "k3"]);
        let thinking: Vec<bool> = models
            .iter()
            .map(|m| !m.reasoning_options.is_empty())
            .collect();
        assert_eq!(thinking, vec![false, true, true]);
        assert_eq!(models[1].provider_id.as_deref(), Some("empiriolabs"));
        assert_eq!(models[2].provider_id.as_deref(), Some("kimi-coding"));
        assert_eq!(full_model_id(&models[2]), "kimi-coding/k3");
        // Header-only output yields nothing, so discovery can fall back to the catalogue.
        assert!(
            models_from_list_models_output("provider model\n", &std::collections::HashMap::new())
                .is_empty()
        );

        // Catalogue extras are carried onto matching CLI rows.
        let mut extras = std::collections::HashMap::new();
        extras.insert("kimi-coding/k3".to_string(), vec!["xhigh".to_string()]);
        let enriched = models_from_list_models_output(output, &extras);
        let k3 = enriched
            .iter()
            .find(|m| full_model_id(m) == "kimi-coding/k3")
            .expect("k3");
        assert!(k3.reasoning_options.iter().any(|o| o.id == "xhigh"));
    }

    #[test]
    fn slash_commands_are_only_what_is_installed() {
        let commands = pi_slash_commands(None);
        assert!(
            commands.iter().all(|c| c.name.starts_with("skill:")),
            "only verified skills may be advertised, got {:?}",
            commands.iter().map(|c| &c.name).collect::<Vec<_>>()
        );
        // `handoff`/`pickup` come from optional pi packages, not pi core, so they must not be hardcoded.
        assert!(
            !commands
                .iter()
                .any(|c| c.name == "handoff" || c.name == "pickup")
        );
    }

    #[test]
    fn skill_scan_matches_pis_documented_locations() {
        let dirs = skill_dirs(None);
        let rendered: Vec<String> = dirs
            .iter()
            .map(|d| d.to_string_lossy().to_string())
            .collect();
        assert!(
            rendered.iter().any(|d| d.ends_with(".pi/agent/skills")),
            "{rendered:?}"
        );
        assert!(
            rendered.iter().any(|d| d.ends_with(".agents/skills")),
            "{rendered:?}"
        );
        assert_eq!(
            rendered.len(),
            2,
            "project dirs must be gated on trust: {rendered:?}"
        );
    }

    #[test]
    fn catalogue_reader_handles_missing_valid_and_broken_files() {
        let dir = std::env::temp_dir().join(format!("pi-cat-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).expect("temp dir");
        let good = dir.join("good.json");
        let broken = dir.join("broken.json");
        let missing = dir.join("missing.json");

        std::fs::write(
            &good,
            r#"{"cerebras": {"models": [{"id": "gemma", "name": "Gemma"}]}}"#,
        )
        .unwrap();
        std::fs::write(&broken, "{ not json").unwrap();

        let parsed = read_catalogue_from(&good).expect("valid catalogue");
        assert_eq!(models_from_catalogue(&parsed).len(), 1);
        assert!(read_catalogue_from(&broken).is_none());
        assert!(read_catalogue_from(&missing).is_none());

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn configured_default_is_added_to_the_model_list() {
        let catalogue = models_from_catalogue(&serde_json::json!({
            "cerebras": { "models": [ { "id": "gemma", "name": "Gemma", "provider": "cerebras", "reasoning": false } ] }
        }));

        // A configured model from a provider missing from the catalogue is added at the front.
        let models = with_configured_default(catalogue.clone(), Some("zenmux/deepseek/v4.1"));
        assert_eq!(models[0].id, "deepseek/v4.1");
        assert_eq!(models[0].provider_id.as_deref(), Some("zenmux"));
        assert_eq!(full_model_id(&models[0]), "zenmux/deepseek/v4.1");
        assert_eq!(models.len(), 2);

        // Already present or absent: unchanged.
        assert_eq!(
            with_configured_default(catalogue.clone(), Some("cerebras/gemma")).len(),
            1
        );
        assert_eq!(with_configured_default(catalogue, None).len(), 1);
    }

    #[test]
    fn discovery_defaults_to_pis_configured_model() {
        // The picker should reflect pi's own default rather than an opaque "Default" entry.
        let configured = default_model_from_settings();
        if let Some(expected) = configured {
            let pi = pi_with(None);
            assert_eq!(
                pi.model
                    .clone()
                    .or_else(default_model_from_settings)
                    .as_deref(),
                Some(expected.as_str())
            );
        }
        let pinned = pi_with(Some("kimi-coding/k3"));
        assert_eq!(
            pinned
                .model
                .clone()
                .or_else(default_model_from_settings)
                .as_deref(),
            Some("kimi-coding/k3")
        );
    }

    #[test]
    fn slash_commands_are_deduplicated_by_name() {
        let builtins = vec![
            SlashCommandDescription {
                name: "handoff".into(),
                description: Some("builtin".into()),
            },
            SlashCommandDescription {
                name: "pickup".into(),
                description: None,
            },
        ];
        let skills = vec![
            // Same name as a built-in: the built-in wins.
            SlashCommandDescription {
                name: "handoff".into(),
                description: Some("skill".into()),
            },
            SlashCommandDescription {
                name: "skill:builder".into(),
                description: Some("build".into()),
            },
            SlashCommandDescription {
                name: "skill:builder".into(),
                description: None,
            },
        ];
        let merged = merge_slash_commands(builtins, skills);
        let names: Vec<&str> = merged.iter().map(|c| c.name.as_str()).collect();
        assert_eq!(names, vec!["handoff", "pickup", "skill:builder"]);
        assert_eq!(merged[0].description.as_deref(), Some("builtin"));
    }

    #[test]
    fn overrides_and_presets_round_trip() {
        let mut pi = pi_with(None);
        let config = ExecutorConfig {
            executor: BaseCodingAgent::Pi,
            variant: None,
            model_id: Some("kimi-coding/k3".to_string()),
            agent_id: None,
            reasoning_id: Some("minimal".to_string()),
            permission_policy: Some(PermissionPolicy::Supervised),
        };
        pi.apply_overrides(&config);

        assert_eq!(pi.model.as_deref(), Some("kimi-coding/k3"));
        assert_eq!(pi.reasoning.as_deref(), Some("minimal"));
        assert_eq!(pi.yolo, Some(false));
        assert_eq!(
            pi.effective_model().as_deref(),
            Some("kimi-coding/k3:minimal")
        );

        let preset = pi.get_preset_options();
        assert_eq!(preset.executor, BaseCodingAgent::Pi);
        assert_eq!(preset.model_id.as_deref(), Some("kimi-coding/k3"));
        assert_eq!(preset.reasoning_id.as_deref(), Some("minimal"));
        assert_eq!(preset.permission_policy, Some(PermissionPolicy::Supervised));
    }

    #[test]
    fn pi_does_not_offer_an_mcp_config() {
        // pi has no MCP support, so Vibe Kanban must never try to write a config for it.
        let pi = CodingAgent::Pi(pi_with(None));
        assert!(!pi.supports_mcp());
        assert!(pi.default_mcp_config_path().is_none());
    }

    #[test]
    fn model_combines_with_thinking_level() {
        let mut pi = pi_with(Some("kimi-coding/k3"));
        assert_eq!(pi.effective_model().as_deref(), Some("kimi-coding/k3"));
        pi.reasoning = Some("high".to_string());
        assert_eq!(pi.effective_model().as_deref(), Some("kimi-coding/k3:high"));
        pi.reasoning = Some(String::new());
        assert_eq!(pi.effective_model().as_deref(), Some("kimi-coding/k3"));
    }

    #[test]
    fn thinking_level_falls_back_to_pi_default_model() {
        let settings = serde_json::json!({
            "defaultProvider": "zenmux",
            "defaultModel": "deepseek/deepseek-v4.1-flash",
        });
        assert_eq!(
            default_model_from_settings_value(&settings).as_deref(),
            Some("zenmux/deepseek/deepseek-v4.1-flash")
        );
        assert_eq!(
            default_model_from_settings_value(&serde_json::json!({})),
            None
        );
        // No explicit model: the thinking level rides on pi's configured default model.
        let mut pi = pi_with(None);
        pi.reasoning = Some("minimal".to_string());
        if let Some(effective) = pi.effective_model() {
            assert!(effective.ends_with(":minimal"), "got {effective}");
        }
    }

    #[test]
    fn thinking_levels_match_pi_cli_order() {
        // `pi --help`: off, minimal, low, medium, high, xhigh, max (the last two are per model).
        let options = ReasoningOption::from_names(Pi::THINKING_LEVELS.map(String::from));
        let mut ids: Vec<&str> = options.iter().map(|o| o.id.as_str()).collect();
        ids.sort_by_key(|id| {
            Pi::THINKING_LEVELS
                .iter()
                .position(|l| l == id)
                .unwrap_or(99)
        });
        assert_eq!(ids, vec!["off", "minimal", "low", "medium", "high"]);
        assert!(options.iter().any(|o| o.id == "high" && o.is_default));
    }

    #[test]
    fn command_builder_pins_pi_acp_package_and_no_model_flag() {
        let cmd = format!(
            "{:?}",
            pi_with(None)
                .build_command_builder()
                .unwrap()
                .build_initial()
                .unwrap()
        );
        assert!(cmd.contains(PI_ACP_PACKAGE));
        assert!(!cmd.contains("--model"));
    }

    #[test]
    fn model_is_not_passed_on_the_command_line() {
        // The model is applied over ACP (`set_session_model`), not as a CLI flag.
        let cmd = format!(
            "{:?}",
            pi_with(Some("kimi-coding/k3"))
                .build_command_builder()
                .unwrap()
                .build_initial()
                .unwrap()
        );
        assert!(!cmd.contains("kimi-coding/k3"));
    }

    #[test]
    fn catalogue_expands_to_provider_qualified_models() {
        let catalogue = serde_json::json!({
            "kimi-coding": { "models": [
                { "id": "k3", "name": "Kimi K3", "provider": "kimi-coding", "reasoning": true },
                { "id": "k3-256k", "name": "Kimi K3 256K", "provider": "kimi-coding", "reasoning": false }
            ] },
            "openrouter": { "models": [
                { "id": "ai21/jamba", "name": "AI21: Jamba" }
            ] }
        });
        let models = models_from_catalogue(&catalogue);
        let ids: Vec<&str> = models.iter().map(|m| m.id.as_str()).collect();
        assert_eq!(ids, vec!["k3", "k3-256k", "ai21/jamba"]);
        let full: Vec<String> = models.iter().map(full_model_id).collect();
        assert_eq!(
            full,
            vec![
                "kimi-coding/k3",
                "kimi-coding/k3-256k",
                "openrouter/ai21/jamba"
            ]
        );
        assert_eq!(models[0].name, "Kimi K3");
        // Only models pi reports as reasoning-capable offer thinking levels, and they carry pi's base set.
        let levels: Vec<&str> = models[0]
            .reasoning_options
            .iter()
            .map(|o| o.id.as_str())
            .collect();
        assert_eq!(levels, vec!["off", "minimal", "low", "medium", "high"]);
        assert!(models[1].reasoning_options.is_empty());
        assert!(models[2].reasoning_options.is_empty());
        let providers = providers_from_catalogue(&catalogue);
        assert_eq!(
            providers.iter().map(|p| p.id.as_str()).collect::<Vec<_>>(),
            vec!["kimi-coding", "openrouter"]
        );
    }

    #[test]
    fn reasoning_options_include_extra_thinking_levels() {
        let entry = serde_json::json!({
            "id": "claude-fable-5",
            "reasoning": true,
            "thinkingLevelMap": { "off": null, "xhigh": "xhigh", "max": "max" }
        });
        let options = reasoning_options_for_entry(&entry);
        let ids: Vec<&str> = options.iter().map(|o| o.id.as_str()).collect();
        for expected in ["minimal", "low", "medium", "high", "off", "xhigh", "max"] {
            assert!(ids.contains(&expected), "missing {expected} in {ids:?}");
        }
        let non_reasoning = serde_json::json!({ "id": "jamba", "reasoning": false });
        assert!(reasoning_options_for_entry(&non_reasoning).is_empty());
    }

    #[test]
    fn pi_acp_package_is_pinned_to_an_exact_version() {
        // Version bumps must be explicit commits, never a floating ref: either `pi-acp@x.y.z` or a git spec pinned to a
        // release tag / commit.
        for forbidden in [
            "latest", "^", "~", ">=", "*", "next", "#main", "#master", "#HEAD", "#head",
        ] {
            assert!(!PI_ACP_PACKAGE.contains(forbidden), "found {forbidden}");
        }
        if let Some((name, version)) = PI_ACP_PACKAGE.split_once('@') {
            assert_eq!(name, "pi-acp");
            assert_eq!(
                version.split('.').count(),
                3,
                "expected x.y.z, got {version}"
            );
            assert!(
                version.chars().next().is_some_and(|c| c.is_ascii_digit()),
                "got {version}"
            );
        } else if let Some((repo, reference)) = PI_ACP_PACKAGE.split_once('#') {
            assert!(repo.starts_with("github:"), "got {repo}");
            let tag = reference.strip_prefix('v').is_some_and(|rest| {
                rest.split('.').count() == 3 && rest.chars().all(|c| c.is_ascii_digit() || c == '.')
            });
            let commit = reference.len() == 40 && reference.chars().all(|c| c.is_ascii_hexdigit());
            assert!(
                tag || commit,
                "git spec must pin a release tag or commit, got {reference}"
            );
        } else {
            panic!("unpinned package spec: {PI_ACP_PACKAGE}");
        }
    }

    #[test]
    fn availability_distinguishes_login_install_and_absence() {
        let base = std::env::temp_dir().join(format!("pi-avail-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&base).expect("temp dir");

        assert!(matches!(
            availability_info(Some(&base)),
            AvailabilityInfo::NotFound
        ));
        assert!(matches!(
            availability_info(None),
            AvailabilityInfo::NotFound
        ));

        // Installed, no credentials yet.
        std::fs::write(base.join("settings.json"), "{}").expect("settings");
        assert!(matches!(
            availability_info(Some(&base)),
            AvailabilityInfo::InstallationFound
        ));

        // Authenticated (auth file present => LoginDetected with a real timestamp).
        std::fs::write(base.join("auth.json"), "{}").expect("auth");
        match availability_info(Some(&base)) {
            AvailabilityInfo::LoginDetected {
                last_auth_timestamp,
            } => assert!(last_auth_timestamp > 0),
            other => panic!("expected LoginDetected, got {other:?}"),
        }

        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn skill_frontmatter_is_parsed_and_gated_by_user_invocable() {
        let invocable =
            "---\nname: builder\ndescription: Build things\nuser-invocable: true\n---\n\n# Body\n";
        assert_eq!(
            parse_skill_frontmatter(invocable),
            Some((
                "builder".to_string(),
                Some("Build things".to_string()),
                true
            ))
        );

        let internal = "---\nname: secret\ndescription: nope\nuser-invocable: false\n---\n";
        assert_eq!(
            parse_skill_frontmatter(internal),
            Some(("secret".to_string(), Some("nope".to_string()), false))
        );

        assert_eq!(parse_skill_frontmatter("no frontmatter"), None);
    }
}
