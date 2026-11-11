# Projeto de Scripts e Ajustes de Custos / BEAS

Repositório contendo scripts SQL e consultas de apoio para manutenção de dados no SAP Business One / Beas Manufacturing.

## Estrutura
- `consultas/`: Contém consultas de conferência e scripts de atualização.
  - `begin.sql`: Bloco DO BEGIN / Consulta base das operações no Beas (`BEAS_APL`).
  - `resultado.csv`: Amostra de dados extraídos para validação de roteiro/operações.
  - `update_pos_id.sql`: Script em lote no SAP HANA para reordenar dinamicamente todos os itens que possuem roteiro no Beas (`BEAS_APL`) com operação de MES (`UDF1 = '1'`) fora da última posição, ajustando os `POS_ID`, `SortId` e vinculando todas as operações intermediárias como escravas (`MASTER_POS_ID`).
