import logging
import json
import pandas as pd
from datetime import datetime, timezone
from sqlalchemy import text
from sqlalchemy.engine import Engine


logger = logging.getLogger(__name__)


def load_to_raw(
    df: pd.DataFrame,
    engine: Engine,
    table_name: str,
    schema: str = "raw",
):

    # проверяем DataFrame
    if df.empty:
        logger.warning(
            f"{schema}.{table_name} пустая, загрузка пропущена"
        )

        return

    # текущее время UTC
    load_dt = datetime.now(timezone.utc)

    # копируем DataFrame
    df = df.copy()

    # технические поля
    df["_load_dt"] = load_dt
    df["_batch_id"] = load_dt.strftime("%Y%m%d%H%M%S")

    try:
        logger.info(
            f"Загрузка {len(df)} строк в {schema}.{table_name}"
        )

        # преобразуем dict/list в JSON
        for col in df.columns:
            if df[col].apply(
                lambda x: isinstance(x, (dict, list))
            ).any():

                logger.info(
                    f"Преобразование столбца {col} в JSON"
                )

                df[col] = df[col].apply(
                    lambda x:
                        json.dumps(x)
                        if isinstance(x, (dict, list))
                        else x
                )

        with engine.begin() as conn:
            # проверяем существование таблицы
            table_exists = conn.execute(
                text(f"""
                    SELECT to_regclass(
                        '{schema}.{table_name}'
                    )
                """)
            ).scalar()

            # если таблица существует — очищаем
            if table_exists:
                logger.info(
                    f"Очистка таблицы {schema}.{table_name}"
                )

                conn.execute(
                    text(
                        f"TRUNCATE TABLE {schema}.{table_name}"
                    )
                )

            else:
                logger.info(
                    f"Таблица {schema}.{table_name} "
                    f"будет создана"
                )

            # загружаем данные
            df.to_sql(
                table_name,
                conn,
                schema=schema,
                if_exists="append",
                index=False,
                method="multi",
            )

        logger.info(
            f"Успешно загружено {len(df)} строк "
            f"в {schema}.{table_name}"
        )

    except Exception as e:
        logger.error(
            f"Ошибка при загрузке данных "
            f"в {schema}.{table_name}: {e}"
        )

        raise