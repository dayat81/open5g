logger:
  level: info
sgwc:
  gtpc:
    server:
    - address: @O5G_SGWC_CORE@
  pfcp:
    server:
    - address: @O5G_SGWC_CORE@
    client:
      sgwu:
      - address: @O5G_SGWU_CORE@
