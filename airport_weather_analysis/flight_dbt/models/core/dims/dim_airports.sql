select distinct

    md5(
        coalesce(airport_iata, '') ||
        coalesce(airport_icao, '') ||
        coalesce(airport_name, '')
    ) as airport_key,

    airport_iata,
    airport_icao,

    airport_name,

    airport_country,
    airport_city,

    airport_latitude,
    airport_longitude,
    airport_altitude,

    airport_timezone,
    airport_timezone_offset

from {{ ref('stg_airports') }}

where airport_country is not null
and airport_name is not null