select distinct

    md5(
        coalesce(aircraft_type, '') ||
        coalesce(manufacturer, '')
    ) as aircraft_key,

    aircraft_type,
    manufacturer,
    seats,
    range_km,
    category

from {{ ref('stg_aircraft_reference') }}