import os
import time
import logging
import requests
from datetime import datetime, timedelta

# создаём логгер для текущего модуля
logger = logging.getLogger(__name__)


def extract_aerodatabox_fids_range_batch(
    airport_code: str,
    code_type: str,
    start_date: str, 
    end_date: str,   
    direction: str = "Both",
    with_cancelled: bool = True,
    with_cargo: bool = True,
    with_codeshared: bool = True,
    with_leg: bool = True,
    with_location: bool = False,
    with_private: bool = True,
):
    """
    Extract данных из AeroDataBox API (батчами по 12 часов)
    Возвращается список JSON-ответов (payload + мета)
    """

    # получаем API-ключ из переменных окружения
    api_key = os.getenv("AERODATABOX_API_KEY")

    if not api_key:
        raise RuntimeError("AERODATABOX_API_KEY not set")

    # заголовки для авторизации
    headers = {
        "x-rapidapi-key": api_key,
        "x-rapidapi-host": "aerodatabox.p.rapidapi.com",
        "content-type": "application/json",
        "x-rapidapi-ua": "RapidAPI-Playground",
    }

    results = []

    # работа с датами
    if not start_date or not end_date:
        raise ValueError("Both start_date and end_date must be provided")

    start_dt = datetime.strptime(start_date, "%Y-%m-%d")
    end_dt = datetime.strptime(end_date, "%Y-%m-%d")

    if end_dt < start_dt:
        raise ValueError("end_date must be greater than or equal to start_date")

    # количество дней в диапазоне
    days = (end_dt - start_dt).days + 1

    # цикл по дням
    for day_offset in range(days):
        day_start = start_dt + timedelta(days=day_offset)

        # делим сутки на 2 окна по 12 часов
        for window in [(0, 12), (12, 24)]:

            # формируем временной интервал, который нас интересует
            from_local = (day_start + timedelta(hours=window[0])).strftime("%Y-%m-%dT%H:%M")
            to_local = (day_start + timedelta(hours=window[1])).strftime("%Y-%m-%dT%H:%M")

            # логируем текущий запрос
            logger.info(f"AeroDataBox {airport_code} {from_local} → {to_local}")

            # формируем URL (path-параметры в строке)
            url = (
                f"https://aerodatabox.p.rapidapi.com/flights/airports/"
                f"{code_type}/{airport_code}/{from_local}/{to_local}"
            )

            # параметры запроса
            params = {
                "direction": direction,
                "withCancelled": str(with_cancelled).lower(),
                "withCargo": str(with_cargo).lower(),
                "withCodeshared": str(with_codeshared).lower(),
                "withLeg": str(with_leg).lower(),
                "withLocation": str(with_location).lower(),
                "withPrivate": str(with_private).lower()
            }

            # настройки retry
            max_retries = 6
            attempt = 0

            # цикл повторных попыток
            while attempt < max_retries:
                try:
                    # выполняем HTTP-запрос
                    response = requests.get(
                        url,
                        headers=headers,
                        params=params,
                        timeout=30
                    )

                    # обработка rate limit
                    if response.status_code == 429:
                        attempt += 1

                        retry_after = response.headers.get("Retry-After")
                        wait = int(retry_after) if retry_after else 2 ** attempt

                        logger.warning(f"429 rate limit — sleep {wait}s")

                        time.sleep(wait)
                        continue

                    # обработка пустого ответа
                    if response.status_code == 204:
                        payload = {"flights": []}
                    else:
                        response.raise_for_status()
                        payload = response.json()

                    # --- ВАЛИДАЦИЯ ДАННЫХ ---
                    # проверяем, что ответ — словарь
                    if not isinstance(payload, dict):
                        raise ValueError("Response is not dict")

                    # проверяем наличие ожидаемых ключей
                    if "departures" not in payload and "arrivals" not in payload:
                        logger.warning("Нет ключей arrivals/departures")

                    # сохраняем результат
                    results.append({
                        "airport_code": airport_code,
                        "code_type": code_type,
                        "from_local": from_local,
                        "to_local": to_local,
                        "direction": direction,
                        "payload": payload
                    })

                    # если всё успешно, то выходим из retry
                    break

                # обработка сетевых ошибок (таймаут, соединение и т.д.)
                except (requests.RequestException, ValueError) as e:
                    logger.warning(f"Ошибка сети (attempt {attempt}): {e}")

                    attempt += 1
                    
                    # экспоненциальная задержка
                    time.sleep(2 ** attempt)

            # если все попытки не удались
            else:
                logger.error(f" skipped {from_local} → {to_local}")
                continue

            # имитируем задержки между запросами
            time.sleep(1.2)

    # логируем итог
    logger.info(f"Extract completed: {len(results)} batches")

    # возвращаем все собранные данные
    return results