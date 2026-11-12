logger:
  level: info
upf:
  pfcp:
    server:
    - address: @O5G_UPF_CORE@
  gtpu:
    server:
    - address: @O5G_UPF_CORE@
  session:
    - subnet: @O5G_UE_POOL@
      gateway: @O5G_UE_TUN_ADDR@
      dnn: internet
