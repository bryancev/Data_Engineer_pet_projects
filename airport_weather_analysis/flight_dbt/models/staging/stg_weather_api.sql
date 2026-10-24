{{ config(
    materialized='table',
    indexes=[
      {'columns': ['airport_iata', 'weather_time_utc']}
    ]
) }}

with source_data as (

    select
        source,
        upper(trim(airport_iata)) as airport_iata,
        loaded_at,
        cast(payload as jsonb)    as payload
    from {{ source('raw', 'weather_raw') }}

),

exploded as (

    select
        source,
        airport_iata,
        loaded_at,

        jsonb_array_elements_text(payload -> 'hourly' -> 'time')            as weather_time,

        jsonb_array_elements(payload -> 'hourly' -> 'temperature_2m')       as temperature_2m,
        jsonb_array_elements(payload -> 'hourly' -> 'apparent_temperature') as apparent_temperature,
        jsonb_array_elements(payload -> 'hourly' -> 'dewpoint_2m')          as dewpoint_2m,

        jsonb_array_elements(payload -> 'hourly' -> 'relativehumidity_2m')  as relative_humidity_2m,

        jsonb_array_elements(payload -> 'hourly' -> 'precipitation')        as precipitation_mm,
        jsonb_array_elements(payload -> 'hourly' -> 'rain')                 as rain_mm,
        jsonb_array_elements(payload -> 'hourly' -> 'snowfall')             as snowfall_cm,

        jsonb_array_elements(payload -> 'hourly' -> 'cloudcover')           as cloudcover_pct,
        jsonb_array_elements(payload -> 'hourly' -> 'cloudcover_low')       as cloudcover_low_pct,
        jsonb_array_elements(payload -> 'hourly' -> 'cloudcover_mid')       as cloudcover_mid_pct,
        jsonb_array_elements(payload -> 'hourly' -> 'cloudcover_high')      as cloudcover_high_pct,

        jsonb_array_elements(payload -> 'hourly' -> 'surface_pressure')     as surface_pressure_hpa,
        jsonb_array_elements(payload -> 'hourly' -> 'pressure_msl')         as pressure_msl_hpa,

        jsonb_array_elements(payload -> 'hourly' -> 'visibility')           as visibility_m,

        jsonb_array_elements(payload -> 'hourly' -> 'windspeed_10m')        as windspeed_10m_ms,
        jsonb_array_elements(payload -> 'hourly' -> 'windgusts_10m')        as windgusts_10m_ms,
        jsonb_array_elements(payload -> 'hourly' -> 'winddirection_10m')    as winddirection_10m_deg,

        jsonb_array_elements(payload -> 'hourly' -> 'weathercode')          as weathercode

    from source_data

),

typed as (

    select
        source,
        airport_iata,
        cast(loaded_at as timestamp)   as loaded_at,

        cast(weather_time as timestamp) as weather_time_utc,

        cast(cast(temperature_2m       as text) as double precision) as temperature_2m_c,
        cast(cast(apparent_temperature as text) as double precision) as apparent_temperature_c,
        cast(cast(dewpoint_2m          as text) as double precision) as dewpoint_2m_c,

        case
            when cast(relative_humidity_2m as text) ~ '^-?[0-9]+$'
                then cast(cast(relative_humidity_2m as text) as integer)
            else null
        end                                                as relative_humidity_2m_pct,

        cast(cast(precipitation_mm as text) as double precision) as precipitation_mm,
        cast(cast(rain_mm          as text) as double precision) as rain_mm,
        cast(cast(snowfall_cm      as text) as double precision) as snowfall_cm,

        case
            when cast(cloudcover_pct as text) ~ '^-?[0-9]+$'
                then cast(cast(cloudcover_pct as text) as integer)
            else null
        end                                                as cloudcover_pct,

        case
            when cast(cloudcover_low_pct as text) ~ '^-?[0-9]+$'
                then cast(cast(cloudcover_low_pct as text) as integer)
            else null
        end                                                as cloudcover_low_pct,

        case
            when cast(cloudcover_mid_pct as text) ~ '^-?[0-9]+$'
                then cast(cast(cloudcover_mid_pct as text) as integer)
            else null
        end                                                as cloudcover_mid_pct,

        case
            when cast(cloudcover_high_pct as text) ~ '^-?[0-9]+$'
                then cast(cast(cloudcover_high_pct as text) as integer)
            else null
        end                                                as cloudcover_high_pct,

        cast(cast(surface_pressure_hpa as text) as double precision) as surface_pressure_hpa,
        cast(cast(pressure_msl_hpa     as text) as double precision) as pressure_msl_hpa,

        case
            when cast(visibility_m as text) ~ '^-?[0-9]+(\.[0-9]+)?$'
                then cast(cast(visibility_m as text) as double precision)
            else null
        end                                                as visibility_m,

        cast(cast(windspeed_10m_ms as text) as double precision) as windspeed_10m_ms,
        cast(cast(windgusts_10m_ms as text) as double precision) as windgusts_10m_ms,

        case
            when cast(winddirection_10m_deg as text) ~ '^-?[0-9]+$'
                then cast(cast(winddirection_10m_deg as text) as integer)
            else null
        end                                                as winddirection_10m_deg,

        case
            when cast(weathercode as text) ~ '^-?[0-9]+$'
                then cast(cast(weathercode as text) as integer)
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

with_description as (

    select
        d.source,
        d.airport_iata,
        d.loaded_at,
        d.weather_time_utc,

        d.temperature_2m_c,
        d.apparent_temperature_c,
        d.dewpoint_2m_c,
        d.relative_humidity_2m_pct,

        d.precipitation_mm,
        d.rain_mm,
        d.snowfall_cm,

        d.cloudcover_pct,
        d.cloudcover_low_pct,
        d.cloudcover_mid_pct,
        d.cloudcover_high_pct,

        d.surface_pressure_hpa,
        d.pressure_msl_hpa,
        d.visibility_m,

        d.windspeed_10m_ms,
        d.windgusts_10m_ms,
        d.winddirection_10m_deg,

        d.weathercode,
        coalesce(w.description, 'Unknown') as weather_description

    from deduplicated d
    left join {{ ref('wmo_weather_codes') }} w
        on d.weathercode = w.weathercode

),

final as (

    select
        source,
        airport_iata,
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
        weather_description

    from with_description

)

select * from final