select *
from {{ ref('fact_flights') }}
where airport_departure_iata = airport_arrival_iata