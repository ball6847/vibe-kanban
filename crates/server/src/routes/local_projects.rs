use axum::{
    Router,
    extract::{Json, Path, Query, State},
    response::Json as ResponseJson,
    routing::{get, patch},
};
use db::models::{
    project::{CreateProject, Project, UpdateProject},
    task::{CreateTask, Task, UpdateTask},
};
use deployment::Deployment;
use serde::Deserialize;
use utils::response::ApiResponse;
use uuid::Uuid;

use crate::{DeploymentImpl, error::ApiError};

#[derive(Deserialize)]
pub struct TaskListParams {
    #[serde(default)]
    pub project_id: Option<Uuid>,
}

pub async fn list_projects(
    State(deployment): State<DeploymentImpl>,
) -> Result<ResponseJson<ApiResponse<Vec<Project>>>, ApiError> {
    let projects = Project::find_all(&deployment.db().pool).await?;
    Ok(ResponseJson(ApiResponse::success(projects)))
}

pub async fn list_tasks(
    State(deployment): State<DeploymentImpl>,
    Query(params): Query<TaskListParams>,
) -> Result<ResponseJson<ApiResponse<Vec<Task>>>, ApiError> {
    let tasks = match params.project_id {
        Some(project_id) => Task::find_by_project_id(&deployment.db().pool, project_id).await?,
        None => Task::find_all(&deployment.db().pool).await?,
    };
    Ok(ResponseJson(ApiResponse::success(tasks)))
}

pub async fn create_project(
    State(deployment): State<DeploymentImpl>,
    Json(payload): Json<CreateProject>,
) -> Result<ResponseJson<ApiResponse<Project>>, ApiError> {
    let project = Project::create(&deployment.db().pool, &payload).await?;
    Ok(ResponseJson(ApiResponse::success(project)))
}

pub async fn update_project(
    State(deployment): State<DeploymentImpl>,
    Path(id): Path<Uuid>,
    Json(payload): Json<UpdateProject>,
) -> Result<ResponseJson<ApiResponse<Project>>, ApiError> {
    let project = Project::update(&deployment.db().pool, id, &payload).await?;
    Ok(ResponseJson(ApiResponse::success(project)))
}

pub async fn delete_project(
    State(deployment): State<DeploymentImpl>,
    Path(id): Path<Uuid>,
) -> Result<ResponseJson<ApiResponse<()>>, ApiError> {
    let rows_affected = Project::delete(&deployment.db().pool, id).await?;
    if rows_affected == 0 {
        Err(ApiError::Database(sqlx::Error::RowNotFound))
    } else {
        Ok(ResponseJson(ApiResponse::success(())))
    }
}

pub async fn create_task(
    State(deployment): State<DeploymentImpl>,
    Json(payload): Json<CreateTask>,
) -> Result<ResponseJson<ApiResponse<Task>>, ApiError> {
    let task = Task::create(&deployment.db().pool, &payload).await?;
    Ok(ResponseJson(ApiResponse::success(task)))
}

pub async fn update_task(
    State(deployment): State<DeploymentImpl>,
    Path(id): Path<Uuid>,
    Json(payload): Json<UpdateTask>,
) -> Result<ResponseJson<ApiResponse<Task>>, ApiError> {
    let task = Task::update(&deployment.db().pool, id, &payload).await?;
    Ok(ResponseJson(ApiResponse::success(task)))
}

pub async fn delete_task(
    State(deployment): State<DeploymentImpl>,
    Path(id): Path<Uuid>,
) -> Result<ResponseJson<ApiResponse<()>>, ApiError> {
    let rows_affected = Task::delete(&deployment.db().pool, id).await?;
    if rows_affected == 0 {
        Err(ApiError::Database(sqlx::Error::RowNotFound))
    } else {
        Ok(ResponseJson(ApiResponse::success(())))
    }
}

pub fn router() -> Router<DeploymentImpl> {
    Router::new()
        .route("/projects", get(list_projects).post(create_project))
        .route(
            "/projects/{id}",
            patch(update_project).delete(delete_project),
        )
        .route("/tasks", get(list_tasks).post(create_task))
        .route("/tasks/{id}", patch(update_task).delete(delete_task))
}
