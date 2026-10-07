import logging
import json
from sqlalchemy.engine import Engine
from sqlalchemy import text
from datetime import datetime, timezone

logger = logging.getLogger(__name__)


def load_openmeteo_raw(
    data: dict,
    engine: Engine,
    airport_iata: str,
    source: str = "open_meteo_api",
    schema: str = "raw",
    table_name: str = "weather_raw",
):
    """
    Загрузка сырых данных Open-Meteo (JSON) в PostgreSQL.
    """

    # проверка на пустые данные
    if not data:
        logger.warning("Получены пустые данные, загрузка пропущена")
        return

    # время загрузки 
    loaded_at = datetime.now(timezone.utc)

    try:
        logger.info(f"Начало загрузки погодных данных для аэропорта {airport_iata}")

        with engine.begin() as conn:

            # создаём схему 
            conn.execute(text(f"create schema if not exists {schema}"))

            # создаём таблицу
            conn.execute(text(f"""
                create table if not exists {schema}.{table_name} (
                    source text,
                    airport_iata text,
                    latitude float,
                    longitude float,
                    start_date date,
                    end_date date,
                    loaded_at timestamptz,
                    payload jsonb,
                    unique (airport_iata, latitude, longitude, start_date, end_date)
                )
            """))

            # вставка данных 
            conn.execute(
                text(f"""
                    insert into {schema}.{table_name}
                    (source, airport_iata, latitude, longitude, start_date, end_date, loaded_at, payload)
                    values
                    (:source, :airport_iata, :latitude, :longitude, :start_date, :end_date, :loaded_at, :payload)
                    on conflict (airport_iata, latitude, longitude, start_date, end_date) do nothing
                """),
                {
                    "source": source,
                    "airport_iata": airport_iata,

                    # ключевые метаданные из extract
                    "latitude": data["lat"],
                    "longitude": data["lon"],
                    "start_date": data["start_date"],
                    "end_date": data["end_date"],

                    # служебное время загрузки
                    "loaded_at": loaded_at,

                    # сам JSON (как ты и хотела — через dumps)
                    "payload": json.dumps(data["data"]),
                },
            )

        logger.info(f"Данные успешно загружены для аэропорта {airport_iata}")

    except Exception as e:
        logger.error(f"Ошибка при загрузке погодных данных: {e}")
        raise