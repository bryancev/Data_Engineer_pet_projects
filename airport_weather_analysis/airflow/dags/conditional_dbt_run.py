from airflow.sdk import DAG, task
from airflow.operators.bash import BashOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.exceptions import AirflowSkipException

from datetime import datetime

with DAG(
    dag_id="conditional_dbt_run",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
) as dag:

    @task
    def count_raw_rows():
        hook = PostgresHook(postgres_conn_id="flight_db")

        records = hook.get_records(
            "SELECT COUNT(*) FROM raw.weather_raw"
        )

        row_count = records[0][0]
        print(f"Количество строк: {row_count}")

        return row_count

    @task
    def check_data_exists(row_count):
        if row_count == 0:
            raise AirflowSkipException("Таблица raw.weather_raw пустая, dbt не запускается")

        print(f"Данные есть ({row_count} строк), можно запускать dbt")

    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command="cd /app/flight_dbt && dbt run",
    )

    row_count = count_raw_rows()
    check_data_exists(row_count) >> dbt_run