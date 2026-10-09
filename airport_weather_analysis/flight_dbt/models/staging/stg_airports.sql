select
    -- названия и география
    cast(nullif(nullif(trim("Name"), ''), '\N') as text) as airport_name,
    cast(nullif(nullif(trim("City"), ''), '\N') as text) as airport_city,
    cast(nullif(nullif(trim("Country"), ''), '\N') as text) as airport_country,

    -- коды аэропортов
    cast(
        case 
            when upper(trim("IATA")) in ('', '\N') then null
            else upper(trim("IATA"))
        end as text
    ) as airport_iata,

    cast(
        case 
            when upper(trim("ICAO")) in ('', '\N') then null
            else upper(trim("ICAO"))
        end as text
    ) as airport_icao,

    -- координаты
    cast(
        case 
            when trim("Latitude") ~ '^-?[0-9]+(\.[0-9]+)?$' then trim("Latitude")
            else null
        end as numeric
    ) as airport_latitude,

    cast(
        case 
            when trim("Longitude") ~ '^-?[0-9]+(\.[0-9]+)?$' then trim("Longitude")
            else null
        end as numeric
    ) as airport_longitude,

    cast(
        case 
            when trim("Altitude") ~ '^-?[0-9]+(\.[0-9]+)?$' then trim("Altitude")
            else null
        end as numeric
    ) as airport_altitude,

    -- временные зоны
    cast(nullif(nullif(trim("Timezone"), ''), '\N') as text) as airport_timezone_offset,
    cast(nullif(nullif(trim("Timezone_1"), ''), '\N') as text) as airport_timezone,

    -- техполе из источника
    _load_dt as source_loaded_at

from {{ source('raw', 'airports') }}