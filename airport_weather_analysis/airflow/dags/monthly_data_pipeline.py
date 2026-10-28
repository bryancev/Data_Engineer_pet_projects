from airflow.sdk import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta

default_args = {
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="monthly_data_pipeline",
    start_date=datetime(2026, 1, 1),
    schedule="0 0 1 * *",
    catchup=False,
    tags=["flight_project"],
    default_args=default_args,
) as dag:

    load_files = BashOperator(
        task_id="load_files",
        bash_command="cd /app && python main.py files",
    )

    # load_api = BashOperator(
    #     task_id="load_api",
    #     bash_command=(
    #         "cd /app && "
    #         "START_DATE={{ macros.ds_add(ds, -1 * var.value.load_lookback_days|int) }} "
    #         "END_DATE={{ ds }} "
    #         "python main.py api"
    #     ),
    # )

    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command="cd /app/flight_dbt && dbt run",
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command="cd /app/flight_dbt && dbt test",
    )

    # load_files >> load_api >> dbt_run >> dbt_test
    load_files >> dbt_run >> dbt_test