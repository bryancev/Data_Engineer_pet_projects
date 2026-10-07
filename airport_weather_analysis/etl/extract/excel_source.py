import logging
import pandas as pd
from pathlib import Path

logger = logging.getLogger(__name__)

def extract_excel(path: str, sheet_name=0) -> pd.DataFrame:
    # Конвертируем строку в объект Path для удобной работы с файловой системой
    path = Path(path)

    # Проверяем, что файл существует
    if not path.exists():
        raise FileNotFoundError(f"File not found: {path}")

    # Проверяем расширение — принимаем только .xls и .xlsx
    if path.suffix.lower() not in (".xls", ".xlsx"):
        raise ValueError(f"Unsupported file format: {path.suffix}")

    try:
        # sheet_name=0 по умолчанию — читаем первый лист
        # можно передать название листа строкой, например sheet_name="Данные"

        df = pd.read_excel(path, sheet_name=sheet_name)
        logger.info(f"Successfully read {path.name}, sheet={sheet_name}")
        return df

    except Exception as e:
        # Логируем ошибку и пробрасываем её дальше, не глотаем
        logger.error(f"Failed to read Excel file {path.name}: {e}")
        raise
