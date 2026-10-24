select distinct

    md5(
        coalesce(iata_code, '') ||
        coalesce(icao_code, '') ||
        coalesce(airline_name, '')
    ) as airline_key,

    airline_name,
    iata_code,
    icao_code,
    callsign,
    airline_country,
    airline_active

from {{ ref('stg_airlines') }}