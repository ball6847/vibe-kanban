use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, SqlitePool, Type};
use strum_macros::{Display, EnumString};
use ts_rs::TS;
use uuid::Uuid;

#[derive(
    Debug, Clone, Type, Serialize, Deserialize, PartialEq, TS, EnumString, Display, Default,
)]
#[sqlx(type_name = "task_status", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub enum TaskStatus {
    #[default]
    Todo,
    InProgress,
    InReview,
    Done,
    Cancelled,
}

/// Automation may only ever move a task forward. An operator's `Done` or `Cancelled` is
/// never undone, `Cancelled` is terminal, and a task that has been worked on does not
/// silently fall back to `Todo` (a finished run is reviewable even if the start was never
/// recorded, e.g. after a restart).
impl TaskStatus {
    pub fn can_transition_to(self, next: TaskStatus) -> bool {
        use TaskStatus::*;

        if self == next {
            return false;
        }

        match (self, next) {
            (Todo, InProgress | InReview | Done) => true,
            (InProgress, InReview | Done) => true,
            // Review can send work back for another pass.
            (InReview, InProgress | Done) => true,
            (Cancelled, _) | (Done, _) => false,
            (_, Cancelled) => true,
            // Everything else would walk the task backwards.
            _ => false,
        }
    }
}

#[derive(Debug, Clone, FromRow, Serialize, Deserialize, TS)]
pub struct Task {
    pub id: Uuid,
    pub project_id: Uuid, // Foreign key to Project
    pub title: String,
    pub description: Option<String>,
    pub status: TaskStatus,
    pub parent_workspace_id: Option<Uuid>, // Foreign key to parent Workspace
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, TS)]
pub struct CreateTask {
    pub project_id: Uuid,
    pub title: String,
    pub description: Option<String>,
}

#[derive(Debug, Deserialize, TS)]
pub struct UpdateTask {
    pub title: Option<String>,
    pub description: Option<String>,
    pub status: Option<TaskStatus>,
}

/// Merge a description update: None keeps existing, Some("") clears to NULL.
fn merge_description(existing: Option<String>, update: Option<String>) -> Option<String> {
    match update {
        None => existing,
        Some(text) if text.is_empty() => None,
        Some(text) => Some(text),
    }
}

impl Task {
    pub async fn find_all(pool: &SqlitePool) -> Result<Vec<Self>, sqlx::Error> {
        sqlx::query_as!(
            Task,
            r#"SELECT id as "id!: Uuid", project_id as "project_id!: Uuid", title, description, status as "status!: TaskStatus", parent_workspace_id as "parent_workspace_id: Uuid", created_at as "created_at!: DateTime<Utc>", updated_at as "updated_at!: DateTime<Utc>"
               FROM tasks
               ORDER BY created_at ASC"#
        )
        .fetch_all(pool)
        .await
    }

    pub async fn find_by_id(pool: &SqlitePool, id: Uuid) -> Result<Option<Self>, sqlx::Error> {
        sqlx::query_as!(
            Task,
            r#"SELECT id as "id!: Uuid", project_id as "project_id!: Uuid", title, description, status as "status!: TaskStatus", parent_workspace_id as "parent_workspace_id: Uuid", created_at as "created_at!: DateTime<Utc>", updated_at as "updated_at!: DateTime<Utc>"
               FROM tasks
               WHERE id = $1"#,
            id
        )
        .fetch_optional(pool)
        .await
    }

    pub async fn find_by_project_id(
        pool: &SqlitePool,
        project_id: Uuid,
    ) -> Result<Vec<Self>, sqlx::Error> {
        sqlx::query_as!(
            Task,
            r#"SELECT id as "id!: Uuid", project_id as "project_id!: Uuid", title, description, status as "status!: TaskStatus", parent_workspace_id as "parent_workspace_id: Uuid", created_at as "created_at!: DateTime<Utc>", updated_at as "updated_at!: DateTime<Utc>"
               FROM tasks
               WHERE project_id = $1
               ORDER BY created_at ASC"#,
            project_id
        )
        .fetch_all(pool)
        .await
    }

    pub async fn create(pool: &SqlitePool, data: &CreateTask) -> Result<Self, sqlx::Error> {
        let id = Uuid::new_v4();
        sqlx::query_as!(
            Task,
            r#"INSERT INTO tasks (id, project_id, title, description)
               VALUES ($1, $2, $3, $4)
               RETURNING id as "id!: Uuid", project_id as "project_id!: Uuid", title, description, status as "status!: TaskStatus", parent_workspace_id as "parent_workspace_id: Uuid", created_at as "created_at!: DateTime<Utc>", updated_at as "updated_at!: DateTime<Utc>""#,
            id,
            data.project_id,
            data.title,
            data.description
        )
        .fetch_one(pool)
        .await
    }

    pub async fn update(
        pool: &SqlitePool,
        id: Uuid,
        data: &UpdateTask,
    ) -> Result<Self, sqlx::Error> {
        let existing = Self::find_by_id(pool, id)
            .await?
            .ok_or(sqlx::Error::RowNotFound)?;

        let title = data.title.as_ref().unwrap_or(&existing.title);
        let description = merge_description(existing.description, data.description.clone());
        let status = data.status.as_ref().unwrap_or(&existing.status);

        sqlx::query_as!(
            Task,
            r#"UPDATE tasks
               SET title = $2, description = $3, status = $4, updated_at = datetime('now', 'subsec')
               WHERE id = $1
               RETURNING id as "id!: Uuid", project_id as "project_id!: Uuid", title, description, status as "status!: TaskStatus", parent_workspace_id as "parent_workspace_id: Uuid", created_at as "created_at!: DateTime<Utc>", updated_at as "updated_at!: DateTime<Utc>""#,
            id,
            title,
            description,
            status
        )
        .fetch_one(pool)
        .await
    }

    /// Move a task to `status` when the automation rules allow it, mirroring
    /// `TaskStatus::can_transition_to`. Returns the task as it stands afterwards (the
    /// unchanged one when the transition is refused), or `None` when the task is gone.
    pub async fn update_status(
        pool: &SqlitePool,
        id: Uuid,
        status: TaskStatus,
    ) -> Result<Option<Self>, sqlx::Error> {
        let Some(existing) = Self::find_by_id(pool, id).await? else {
            return Ok(None);
        };

        let current = existing.status.clone();
        if !current.can_transition_to(status.clone()) {
            return Ok(Some(existing));
        }

        // Runtime query on purpose: this needs no compile-time cache entry, so adding it
        // cannot invalidate the offline SQLx cache in environments that cannot build
        // every workspace member (the Tauri crate needs system glib/GTK).
        sqlx::query_as::<_, Task>(
            r#"UPDATE tasks
               SET status = ?, updated_at = datetime('now', 'subsec')
               WHERE id = ?
               RETURNING id, project_id, title, description, status, parent_workspace_id, created_at, updated_at"#,
        )
        .bind(status)
        .bind(id)
        .fetch_one(pool)
        .await
        .map(Some)
    }

    pub async fn delete(pool: &SqlitePool, id: Uuid) -> Result<u64, sqlx::Error> {
        let result = sqlx::query!("DELETE FROM tasks WHERE id = $1", id)
            .execute(pool)
            .await?;
        Ok(result.rows_affected())
    }
}

#[cfg(test)]
mod tests {
    use super::TaskStatus::*;
    use super::{TaskStatus, UpdateTask, merge_description};

    #[test]
    fn task_status_serializes_to_db_check_constraint_values() {
        // Must match CHECK (status IN (...)) in 20250617183714_init.sql.
        let cases = [
            (TaskStatus::Todo, "\"todo\""),
            (TaskStatus::InProgress, "\"inprogress\""),
            (TaskStatus::InReview, "\"inreview\""),
            (TaskStatus::Done, "\"done\""),
            (TaskStatus::Cancelled, "\"cancelled\""),
        ];
        for (status, expected) in cases {
            assert_eq!(serde_json::to_string(&status).unwrap(), expected);
        }
    }

    #[test]
    fn merge_description_keeps_sets_and_clears() {
        assert_eq!(
            merge_description(Some("old".into()), None),
            Some("old".to_string())
        );
        assert_eq!(
            merge_description(Some("old".into()), Some("new".into())),
            Some("new".to_string())
        );
        assert_eq!(merge_description(Some("old".into()), Some("".into())), None);
        assert_eq!(merge_description(None, Some("".into())), None);
    }

    #[test]
    fn update_task_accepts_partial_status_only_payload() {
        let payload: UpdateTask =
            serde_json::from_str(r#"{"title":null,"description":null,"status":"inprogress"}"#)
                .unwrap();
        assert!(matches!(payload.status, Some(TaskStatus::InProgress)));
        assert!(payload.title.is_none());
    }


    #[test]
    fn automation_moves_a_task_forward() {
        assert!(TaskStatus::Todo.can_transition_to(InProgress));
        assert!(TaskStatus::Todo.can_transition_to(InReview));
        assert!(TaskStatus::InProgress.can_transition_to(InReview));
        assert!(TaskStatus::InProgress.can_transition_to(Done));
        assert!(TaskStatus::InReview.can_transition_to(Done));
        // Review can send work back for another pass.
        assert!(TaskStatus::InReview.can_transition_to(InProgress));
    }

    #[test]
    fn automation_never_walks_a_task_back() {
        assert!(!TaskStatus::InProgress.can_transition_to(Todo));
        assert!(!TaskStatus::InReview.can_transition_to(Todo));
        assert!(!TaskStatus::Done.can_transition_to(InProgress));
        assert!(!TaskStatus::Done.can_transition_to(InReview));
        assert!(!TaskStatus::Done.can_transition_to(Done));
        assert!(!TaskStatus::Todo.can_transition_to(Todo));
    }

    #[test]
    fn cancelled_and_done_are_terminal() {
        assert!(TaskStatus::Todo.can_transition_to(Cancelled));
        assert!(TaskStatus::InProgress.can_transition_to(Cancelled));
        assert!(!TaskStatus::Cancelled.can_transition_to(Todo));
        assert!(!TaskStatus::Cancelled.can_transition_to(InProgress));
        assert!(!TaskStatus::Cancelled.can_transition_to(Done));
    }
}
