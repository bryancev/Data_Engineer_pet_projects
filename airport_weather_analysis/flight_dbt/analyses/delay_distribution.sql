select
    departure_time_status,
    count(*) as flights_count
from {{ ref('fact_flights') }}
group by departure_time_status