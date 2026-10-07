import logging
import os
import sys
import time
from sqlalchemy import text
from pathlib import Path
from datetime import datetime, timedelta

# extract
from etl.extract.csv_source import extract_csv
from etl.extract.excel_source import extract_excel
from etl.extract.parquet_source import extract_parquet
from etl.extract.json_source import extract_json
from etl.extract.open_meteo_hourly import extract_openmeteo_raw
from etl.extract.aerodatabox_api import extract_aerodatabox_fids_range_batch

# load
from etl.load.raw_load import load_to_raw
from etl.load.open_meteo_api_load import load_openmeteo_raw
from etl.load.aerodatabox_api_load import load_aerodatabox_raw

# db
from db import get_engine

# логирование
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# читаем переменные из файла .env
RAW_DIR = Path(os.getenv("RAW_DATA_PATH", "data/raw"))
AIRPORT_IATA = os.getenv("AIRPORT_IATA", "HKT")
LAT = float(os.getenv("LAT", "0") or 0)
LON = float(os.getenv("LON", "0") or 0)
START_DATE = os.getenv("START_DATE")
END_DATE = os.getenv("END_DATE")

# ожидание готовности базы данных
def wait_for_db(engine, retries=10, delay=2):
    for i in range(retries):
        try:
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            logger.info("База данных готова")
            return
        except Exception:
            logger.info("Ожидание базы данных...")
            time.sleep(delay)

    raise Exception("База данных недоступна")

def run_file_sources(engine):
    # загрузка файлов в raw-слой

    for file_path in RAW_DIR.glob("*.*"):
        logger.info(f"Обработка файла {file_path.name}")

        try:
            if file_path.suffix.lower() == ".csv":
                df = extract_csv(file_path)

            elif file_path.suffix.lower() in (".xls", ".xlsx"):
                df = extract_excel(file_path)

            elif file_path.suffix.lower() == ".parquet":
                df = extract_parquet(file_path)

            elif file_path.suffix.lower() == ".json":
                df = extract_json(file_path)

            else:
                logger.warning(f"Неподдерживаемый формат: {file_path.name}")
                continue

            table_name = file_path.stem.lower()
            load_to_raw(df, engine, table_name)

            logger.info(f"Файл {file_path.name} успешно загружен")

        except Exception as e:
            logger.error(f"Ошибка при обработке {file_path.name}: {e}")
            continue


def get_default_dates(start_date=None, end_date=None):
    # если даты не заданы, то считаем последние 30 дней

    today = datetime.today()

    if not end_date:
        end_date_dt = today
    else:
        end_date_dt = datetime.strptime(end_date, "%Y-%m-%d")

    if not start_date:
        start_date_dt = end_date_dt - timedelta(days=30)
    else:
        start_date_dt = datetime.strptime(start_date, "%Y-%m-%d")

    return (
        start_date_dt.strftime("%Y-%m-%d"),
        end_date_dt.strftime("%Y-%m-%d"),
    )


def run_api_sources(engine):
    # загрузка данных из API

    airport_code = AIRPORT_IATA
    lat = LAT
    lon = LON

    start_date, end_date = get_default_dates(START_DATE, END_DATE)

    logger.info(f"Загрузка данных API с {start_date} по {end_date}")

    # Open-Meteo API
    try:
        weather_data = extract_openmeteo_raw(
            lat=lat,
            lon=lon,
            start_date=start_date,
            end_date=end_date,
        )

        load_openmeteo_raw(
            data=weather_data,
            engine=engine,
            airport_iata=airport_code
        )

    except Exception as e:
        logger.error(f"Ошибка Open-Meteo API: {e}")

    # AeroDataBox API
    try:
        aerodata = extract_aerodatabox_fids_range_batch(
            airport_code=airport_code, 
            code_type="IATA",
            start_date=start_date,
            end_date=end_date
        )

        load_aerodatabox_raw(
            data=aerodata,
            engine=engine
        )

    except Exception as e:
        logger.error(f"Ошибка AeroDataBox API: {e}")


def main(engine):
    logger.info("Запуск ETL-пайплайна")

    try:
        run_file_sources(engine)
        run_api_sources(engine)

        logger.info("ETL-пайплайн успешно завершён")

    except Exception as e:
        logger.error(f"Ошибка в пайплайне: {e}")
        raise


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "run"

    # создаём engine 
    engine = get_engine()

    # ждём готовность БД
    wait_for_db(engine)

    if command == "run":
        main(engine)

    elif command == "files":
        run_file_sources(engine)

    elif command == "api":
        run_api_sources(engine)

    else:
        raise ValueError(f"Неизвестная команда: {command}")