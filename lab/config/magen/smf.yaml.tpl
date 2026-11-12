logger:
  level: info
smf:
  freeDiameter: /etc/o5/fd/smf.conf
  pfcp:
    server:
    - address: @O5G_SMF_CORE@
    client:
      upf:
      - address: @O5G_UPF_CORE@
  gtpc:
    server:
    - address: @O5G_SMF_CORE@
  session:
    - subnet: @O5G_UE_POOL@
      gateway: @O5G_UE_TUN_ADDR@
      dnn: internet
  dns:
  - @O5G_DNS_ADDR@
  mtu: 1400
