FROM python:3.12-slim



# Рабочая директория внутри контейнера
WORKDIR /app



# Сначала зависимости (так быстрее пересобирается)
COPY requirements.txt .



RUN python -m pip install --no-cache-dir -r requirements.txt


# Потом код
COPY . .