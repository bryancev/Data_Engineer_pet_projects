{{ config(
    materialized='table',
    indexes=[
      {'columns': ['airport_iata', 'weather_time_utc']}
    ]
) }}

with source_data as (

    select
        weather_data,
        _load_dt   as loaded_at,
        _batch_id  as batch_id
    from {{ source('raw', 'weather_hourly_history') }}

),

unnested as (

    select
        loaded_at,
        batch_id,
        jsonb_array_elements(cast(weather_data as jsonb)) as record
    from source_data

),

exploded as (

    select
        record ->> 'source'                                                         as source,
        record ->> 'airport_iata'                                                   as airport_iata,
        loaded_at,
        batch_id,

        jsonb_array_elements_text(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'time'
        )                                                                           as weather_time,

        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'temperature_2m'
        )                                                                           as temperature_2m,
        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'apparent_temperature'
        )                                                                           as apparent_temperature,
        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'dewpoint_2m'
        )                                                                           as dewpoint_2m,

        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'relativehumidity_2m'
        )                                                                           as relative_humidity_2m,

        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'precipitation'
        )                                                                           as precipitation_mm,
        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'rain'
        )                                                                           as rain_mm,
        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'snowfall'
        )                                                                           as snowfall_cm,

        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'cloudcover'
        )                                                                           as cloudcover_pct,
        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'cloudcover_low'
        )                                                                           as cloudcover_low_pct,
        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'cloudcover_mid'
        )                                                                           as cloudcover_mid_pct,
        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'cloudcover_high'
        )                                                                           as cloudcover_high_pct,

        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'surface_pressure'
        )                                                                           as surface_pressure_hpa,
        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'pressure_msl'
        )                                                                           as pressure_msl_hpa,

        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'visibility'
        )                                                                           as visibility_m,

        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'windspeed_10m'
        )                                                                           as windspeed_10m_ms,
        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'windgusts_10m'
        )                                                                           as windgusts_10m_ms,
        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'winddirection_10m'
        )                                                                           as winddirection_10m_deg,

        jsonb_array_elements(
            cast(record ->> 'payload' as jsonb) -> 'hourly' -> 'weathercode'
        )                                                                           as weathercode

    from unnested

),

typed as (

    select
        source,
        airport_iata,
        batch_id,
        cast(loaded_at as timestamp)                       as loaded_at,

        cast(weather_time as timestamp)                    as weather_time_utc,

        cast(cast(temperature_2m       as text) as double precision) as temperature_2m_c,
        cast(cast(apparent_temperature as text) as double precision) as apparent_temperature_c,
        cast(cast(dewpoint_2m          as text) as double precision) as dewpoint_2m_c,

        case
            when relative_humidity_2m::text ~ '^-?[0-9]+$'
                then cast(relative_humidity_2m::text as integer)
            else null
        end                                                as relative_humidity_2m_pct,

        cast(cast(precipitation_mm as text) as double precision) as precipitation_mm,
        cast(cast(rain_mm          as text) as double precision) as rain_mm,
        cast(cast(snowfall_cm      as text) as double precision) as snowfall_cm,

        case
            when cloudcover_pct::text ~ '^-?[0-9]+$'
                then cast(cloudcover_pct::text as integer)
            else null
        end                                                as cloudcover_pct,

        case
            when cloudcover_low_pct::text ~ '^-?[0-9]+$'
                then cast(cloudcover_low_pct::text as integer)
            else null
        end                                                as cloudcover_low_pct,

        case
            when cloudcover_mid_pct::text ~ '^-?[0-9]+$'
                then cast(cloudcover_mid_pct::text as integer)
            else null
        end                                                as cloudcover_mid_pct,

        case
            when cloudcover_high_pct::text ~ '^-?[0-9]+$'
                then cast(cloudcover_high_pct::text as integer)
            else null
        end                                                as cloudcover_high_pct,

        cast(cast(surface_pressure_hpa as text) as double precision) as surface_pressure_hpa,
        cast(cast(pressure_msl_hpa     as text) as double precision) as pressure_msl_hpa,

        case
            when visibility_m::text ~ '^-?[0-9]+(\.[0-9]+)?$'
                then cast(visibility_m::text as double precision)
            else null
        end                                                as visibility_m,

        cast(cast(windspeed_10m_ms as text) as double precision) as windspeed_10m_ms,
        cast(cast(windgusts_10m_ms as text) as double precision) as windgusts_10m_ms,

        case
            when winddirection_10m_deg::text ~ '^-?[0-9]+$'
                then cast(winddirection_10m_deg::text as integer)
            else null
        end                                                as winddirection_10m_deg,

        case
            when weathercode::text ~ '^-?[0-9]+$'
                then cast(weathercode::text as integer)
            else null
        end                                                as weathercode

    from exploded

),

deduplicated as (

    select
        *,
        row_number() over (
            partition by source, airport_iata, weather_time_utc
            order by loaded_at desc
        ) as rn
    from typed

),

final as (

    select
        source,
        airport_iata,
        batch_id,
        loaded_at,
        weather_time_utc,

        temperature_2m_c,
        apparent_temperature_c,
        dewpoint_2m_c,
        relative_humidity_2m_pct,

        precipitation_mm,
        rain_mm,
        snowfall_cm,

        cloudcover_pct,
        cloudcover_low_pct,
        cloudcover_mid_pct,
        cloudcover_high_pct,

        surface_pressure_hpa,
        pressure_msl_hpa,
        visibility_m,

        windspeed_10m_ms,
        windgusts_10m_ms,
        winddirection_10m_deg,

        weathercode,

        case weathercode
            when 0  then 'Clear sky'
            when 1  then 'Mainly clear'
            when 2  then 'Partly cloudy'
            when 3  then 'Overcast'
            when 45 then 'Fog'
            when 48 then 'Depositing rime fog'
            when 51 then 'Light drizzle'
            when 53 then 'Moderate drizzle'
            when 55 then 'Dense drizzle'
            when 56 then 'Light freezing drizzle'
            when 57 then 'Dense freezing drizzle'
            when 61 then 'Slight rain'
            when 63 then 'Moderate rain'
            when 65 then 'Heavy rain'
            when 66 then 'Light freezing rain'
            when 67 then 'Heavy freezing rain'
            when 71 then 'Slight snowfall'
            when 73 then 'Moderate snowfall'
            when 75 then 'Heavy snowfall'
            when 77 then 'Snow grains'
            when 80 then 'Slight rain showers'
            when 81 then 'Moderate rain showers'
            when 82 then 'Violent rain showers'
            when 85 then 'Slight snow showers'
            when 86 then 'Heavy snow showers'
            when 95 then 'Thunderstorm'
            when 96 then 'Thunderstorm with hail'
            when 99 then 'Heavy thunderstorm with hail'
            else 'Unknown'
        end as weather_description

    from deduplicated
    where rn = 1

)

select * from final