import json
import logging
from sqlalchemy import text
from sqlalchemy.engine import Engine

# создаём логгер для текущего модуля
logger = logging.getLogger(__name__)


def load_aerodatabox_raw(
    data: list,
    engine: Engine,
    schema: str = "raw",
    table_name: str = "aerodatabox_fids_range",
):
    # проверяем, есть ли данные для загрузки
    if not data:
        logger.warning("No data to load")
        return

    # открываем транзакцию
    with engine.begin() as conn:

        # создаём схему, если она ещё не существует
        conn.execute(text(f"create schema if not exists {schema}"))

        # создаём таблицу, если она ещё не существует
        conn.execute(text(f"""
            create table if not exists {schema}.{table_name} (
                source text,                -- источник данных (aerodatabox)
                airport_code text,          -- код аэропорта
                code_type text,             -- тип кода (IATA / ICAO)
                from_local text,            -- начало интервала
                to_local text,              -- конец интервала
                direction text,             -- направление (Arrival / Departure / Both)
                extracted_at timestamptz,   -- время загрузки (с таймзоной)
                payload jsonb,              -- сырой JSON от API
                unique (airport_code, code_type, from_local, to_local, direction)
                -- уникальный ключ защищает от повторной загрузки одного и того же батча
            )
        """))

        # подготавливаем список строк 
        # каждая строка — это один батч 
        rows = []
        for row in data:
            rows.append({
                # фиксируем источник данных
                "source": "aerodatabox",

                # мета-информация, полученная на этапе extract
                # используем .get(), чтобы не упасть при отсутствии ключа
                "airport_code": row.get("airport_code"),
                "code_type": row.get("code_type"),
                "from_local": row.get("from_local"),
                "to_local": row.get("to_local"),
                "direction": row.get("direction"),

                # payload сохраняем как JSON-строку
                "payload": json.dumps(row.get("payload")),
            })

        # SQL-запрос для вставки всех строк
        stmt = text(f"""
            insert into {schema}.{table_name}
            (source, airport_code, code_type, from_local, to_local, direction, extracted_at, payload)
            values (:source, :airport_code, :code_type, :from_local, :to_local, :direction, now(), :payload)

            -- если запись с таким ключом уже существует — пропускаем
            on conflict (airport_code, code_type, from_local, to_local, direction) do nothing
        """)

        # выполняем вставку
        result = conn.execute(stmt, rows)

        # получаем количество реально вставленных строк
        inserted = result.rowcount if result.rowcount is not None else 0

    # логируем итог загрузки
    logger.info(f"Loaded {inserted} batches into {schema}.{table_name}")