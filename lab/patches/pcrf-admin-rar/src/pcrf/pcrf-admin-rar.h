/* DRAFT, NOT COMPILED, NOT TESTED — WIP v1 2026-11-06 20:21:01 +07 */
/* Dev-only authenticated admin trigger for database-sourced Gx RAR. */
#ifndef PCRF_ADMIN_RAR_H
#define PCRF_ADMIN_RAR_H
int pcrf_admin_rar_init(void);
void pcrf_admin_rar_final(void);
void pcrf_admin_rar_dispatch(void);
#endif
