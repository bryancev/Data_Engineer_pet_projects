import logging
from pathlib import Path
import pandas as pd
import json

logger = logging.getLogger(__name__)

def extract_json(path: str, lines: bool = False, record_path: str | None = None) -> pd.DataFrame:

    # Конвертируем строку в объект Path для удобной работы с файловой системой
    path = Path(path)

    # Проверяем, что файл существует
    if not path.exists():
        raise FileNotFoundError(f"File not found: {path}")

    # Принимаем только .json файлы
    if path.suffix.lower() != ".json":
        raise ValueError(f"Invalid file format: {path.name}. Expected .json")

    logger.info(f"Reading JSON file: {path.name}")

    try:

        # Формат JSON Lines: каждая строка файла — отдельный JSON объект
        if lines:
            df = pd.read_json(path, lines=True)
            if df.empty:
                logger.warning(f"File {path.name} loaded but contains no data")
            logger.info(f"Loaded {len(df)} rows, {len(df.columns)} columns")
            return df

        # --- Читаем как обычный JSON ---
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)

    except json.JSONDecodeError as e:

        # Файл не является валидным JSON
        logger.error(f"Invalid JSON format in {path.name}: {e}")
        raise

    except ValueError as e:
        # Ошибки pandas при чтении (например, несовместимая структура)
        logger.error(f"Pandas error while reading {path.name}: {e}")
        raise

    except Exception as e:
        # Любые другие неожиданные ошибки
        logger.error(f"Unexpected error while reading {path.name}: {e}")
        raise

    # --- Преобразование структуры ---
    try:
        if isinstance(data, list):

            df = pd.DataFrame(data)

        elif isinstance(data, dict):
            if record_path:
                # Данные лежат внутри конкретного ключа словаря

                if record_path not in data:
                    raise ValueError(f"Key '{record_path}' not found in JSON")
                df = pd.json_normalize(data[record_path])

            else:

                # Весь словарь — одна запись, разворачиваем в одну строку
                df = pd.json_normalize(data)

        else:

            # Например, если JSON содержит просто число или строку
            raise ValueError(f"Unsupported JSON structure in {path.name}")

        if df.empty:
            logger.warning(f"File {path.name} loaded but contains no data")
        logger.info(f"Loaded {len(df)} rows, {len(df.columns)} columns")
        return df

    except Exception as e:
        logger.error(f"Failed to transform JSON structure {path.name}: {e}")
        raise