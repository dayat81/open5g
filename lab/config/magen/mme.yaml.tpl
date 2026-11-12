logger:
  level: info
mme:
  freeDiameter: /etc/o5/fd/mme.conf
  s1ap:
    server:
    - address: @O5G_MME_S1@
  gtpc:
    server:
    - address: @O5G_MME_CORE@
    client:
      sgwc:
      - address: @O5G_SGWC_CORE@
      smf:
      - address: @O5G_SMF_CORE@
  gummei:
  - plmn_id: {mcc: @MCC@, mnc: @MNC@}
    mme_gid: 2
    mme_code: 1
  tai:
  - plmn_id: {mcc: @MCC@, mnc: @MNC@}
    tac: 1
  security:
    integrity_order: [EIA2, EIA1, EIA0]
    ciphering_order: [EEA0, EEA1, EEA2]
  network_name: {full: Open5G, short: o5g}
  mme_name: o5g-mme0
