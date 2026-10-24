{% macro get_raw_source() %}
  {% if target.name == 'ci' %}
    {{ return(ref('raw_aerodatabox_fids_sample')) }}
  {% else %}
    {{ return(source('raw', 'aerodatabox_fids_range')) }}
  {% endif %}
{% endmacro %}