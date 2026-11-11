DO BEGIN


	/*
	  Ajuste dinâmico de Roteiro no BEAS (Master / Slave)
	  - Filtro fixado para teste no item especificado (SA3032001)
	  - Utiliza CURSOR explícito com FETCH (sintaxe padrão compatível com todas as versões do HANA)
	*/

	DECLARE itemcode NVARCHAR(50) = 'UN13112041';
	DECLARE v_old_pos INT;
	DECLARE v_new_pos INT;
	DECLARE v_new_sort INT;
	DECLARE v_novo_master INT;

	-- 1. Tabela temporária para calcular a nova ordenação
	CREATE LOCAL TEMPORARY TABLE #TMP_APL_NOVA_ORDEM (
		"ItemCode" NVARCHAR(50),
		"OLD_POS_ID" INT,
		"NEW_POS_ID" INT,
		"NEW_SORT_ID" INT,
		"IS_MASTER" INT
	);

	-- 2. Define a ordenação dinâmica: operações comuns primeiro e a Master (UDF1 = '1') por último
	INSERT INTO #TMP_APL_NOVA_ORDEM ("ItemCode", "OLD_POS_ID", "NEW_POS_ID", "NEW_SORT_ID", "IS_MASTER")
	SELECT
		T."ItemCode",
		T."POS_ID" AS "OLD_POS_ID",
		(ROW_NUMBER() OVER(
			PARTITION BY T."ItemCode" 
			ORDER BY CASE WHEN COALESCE(T."UDF1", '') = '1' THEN 1 ELSE 0 END, T."POS_ID"
		)) * 10 AS "NEW_POS_ID",
		ROW_NUMBER() OVER(
			PARTITION BY T."ItemCode" 
			ORDER BY CASE WHEN COALESCE(T."UDF1", '') = '1' THEN 1 ELSE 0 END, T."POS_ID"
		) AS "NEW_SORT_ID",
		CASE WHEN COALESCE(T."UDF1", '') = '1' THEN 1 ELSE 0 END AS "IS_MASTER"
	FROM "BEAS_APL" T
	WHERE T."ItemCode" = :itemcode;

	-- 3. Tabela temporária com o POS_ID final da Master do item
	CREATE LOCAL TEMPORARY TABLE #TMP_APL_MASTER_FINAL (
		"ItemCode" NVARCHAR(50),
		"MASTER_POS_ID_FINAL" INT
	);

	INSERT INTO #TMP_APL_MASTER_FINAL ("ItemCode", "MASTER_POS_ID_FINAL")
	SELECT
		"ItemCode",
		"NEW_POS_ID"
	FROM #TMP_APL_NOVA_ORDEM
	WHERE "IS_MASTER" = 1;

	-- 4. Passo 1 do UPDATE: Mover para faixa temporária (+100000) evitando colisão de PK
	UPDATE "BEAS_APL"
	SET
		"POS_ID" = "POS_ID" + 100000,
		"POS_TEXT" = CAST("POS_ID" + 100000 AS NVARCHAR(50)),
		"MASTER_POS_ID" = NULL
	WHERE "ItemCode" = :itemcode;

	-- 5. Passo 2 do UPDATE: Usando CURSOR explícito compatível com todas as versões do HANA
	BEGIN
		DECLARE CURSOR c_cursor FOR
			SELECT 
				TMP."OLD_POS_ID",
				TMP."NEW_POS_ID",
				TMP."NEW_SORT_ID",
				CASE 
					WHEN TMP."IS_MASTER" = 1 THEN NULL 
					ELSE MF."MASTER_POS_ID_FINAL" 
				END AS "NOVO_MASTER_POS_ID"
			FROM #TMP_APL_NOVA_ORDEM TMP
			LEFT JOIN #TMP_APL_MASTER_FINAL MF ON TMP."ItemCode" = MF."ItemCode"
			WHERE TMP."ItemCode" = :itemcode;

		FOR cur_row AS c_cursor DO
			UPDATE "BEAS_APL"
			SET
				"POS_ID" = cur_row."NEW_POS_ID",
				"POS_TEXT" = CAST(cur_row."NEW_POS_ID" AS NVARCHAR(50)),
				"SortId" = cur_row."NEW_SORT_ID",
				"MASTER_POS_ID" = cur_row."NOVO_MASTER_POS_ID"
			WHERE "ItemCode" = :itemcode
			  AND "POS_ID" = cur_row."OLD_POS_ID" + 100000;
		END FOR;
	END;

	-- 6. Limpeza das tabelas temporárias
	DROP TABLE #TMP_APL_NOVA_ORDEM;
	DROP TABLE #TMP_APL_MASTER_FINAL;
	
	-- 7. Remove vinculo com operação da lista de materiais
	UPDATE "BEAS_STL" SET
	"APLANPOS_ID" = NULL
	WHERE "ItemCode" = :itemcode;

	-- 8. Consulta final para conferência do resultado
	SELECT
		T."ItemCode",
		T."POS_ID",
		T."POS_TEXT",
		T."SortId",
		T."AG_ID",
		T."APLATZ_ID",
		T."UDF1",
		T."MASTER_POS_ID"
	FROM "BEAS_APL" T
	WHERE T."ItemCode" = :itemcode
	ORDER BY T."POS_ID";

END;
