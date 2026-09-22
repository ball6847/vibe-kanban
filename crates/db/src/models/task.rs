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

    pub async fn delete(pool: &SqlitePool, id: Uuid) -> Result<u64, sqlx::Error> {
        let result = sqlx::query!("DELETE FROM tasks WHERE id = $1", id)
            .execute(pool)
            .await?;
        Ok(result.rows_affected())
    }
}

#[cfg(test)]
mod tests {
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
}
