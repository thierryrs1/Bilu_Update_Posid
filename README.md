# Projeto de Scripts e Ajustes de Custos / BEAS

Repositório contendo scripts SQL e consultas de apoio para manutenção de dados no SAP Business One / Beas Manufacturing.

## Estrutura
- `consultas/`: Contém consultas de conferência e scripts de atualização.
  - `begin.sql`: Bloco DO BEGIN / Consulta base das operações no Beas (`BEAS_APL`).
  - `resultado.csv`: Amostra de dados extraídos para validação de roteiro/operações.
  - `update_pos_id.sql`: Script dinâmico em SAP HANA para reordenar operações por item (utiliza declaração explícita de `CURSOR c_cursor FOR ...` dentro de sub-bloco BEGIN/END compatível com versões legadas e atuais do HANA).
