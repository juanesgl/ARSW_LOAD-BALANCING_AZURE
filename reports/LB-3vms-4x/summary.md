## Prueba de carga - LB-3vms-4x

Host: `68.155.198.102` · 4 ejecuciones paralelas × 10 iteraciones · duración total 82.5 s

| Ejecución | Peticiones | Exitosas | Fallidas | Mín (ms) | Prom (ms) | Máx (ms) | Errores |
|---|---|---|---|---|---|---|---|
| 1 | 10 | 10 | 0 | 6196 | 7342 | 11847 | - |
| 2 | 10 | 7 | 3 | 6197 | 8781 | 12622 | ECONNRESET |
| 3 | 10 | 9 | 1 | 6210 | 7603 | 12365 | ECONNRESET |
| 4 | 10 | 10 | 0 | 6249 | 6865 | 12321 | - |

**Tasa de éxito:** 36/40 (90.0 %)
