import logging
from pathlib import Path
import pandas as pd

# создаём логгер для текущего модуля
logger = logging.getLogger(__name__)

def extract_parquet(path: str) -> pd.DataFrame:

    # преобразуем строку в объект Path для удобной работы с путями
    path = Path(path)

    # проверяем, что файл существует
    if not path.exists():
        raise FileNotFoundError(f"File not found: {path}")

    # проверяем расширение файла (с учётом регистра)
    if path.suffix.lower() != ".parquet":
        raise ValueError(f"File must have .parquet extension: {path.name}")

    try:
        # логируем начало чтения файла
        logger.info(f"Reading Parquet file: {path}")

        # читаем parquet файл в DataFrame
        df = pd.read_parquet(path)

        # логируем результат — сколько строк и колонок загрузилось
        logger.info(f"Loaded {len(df)} rows, {len(df.columns)} columns")
        return df

    # отдельная обработка ошибки зависимостей (если не установлен pyarrow или fastparquet)
    except ImportError:
        logger.error("Missing dependency for parquet. Install 'pyarrow' or 'fastparquet'")
        raise

    # обработка всех остальных ошибок
    except Exception as e:
        logger.error(f"Failed to read parquet file {path.name}: {e}")
        raise