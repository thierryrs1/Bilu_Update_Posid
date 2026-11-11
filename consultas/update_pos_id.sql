DO BEGIN

	/*
	  Ajuste dinâmico de Roteiro no BEAS (Master / Slave) EM LOTE
	  - Identifica todos os itens na BEAS_APL que atendem ao cenário:
	      * Possuem uma operação marcada como MES/Master (UDF1 = '1')
	      * A operação MES atualmente NÃO é a última (existe operação com POS_ID maior)
	  - Reordena as operações para que a Master (UDF1 = '1') vá para o final de cada item
	  - Define todas as outras operações como Slaves dela (MASTER_POS_ID = novo POS_ID final)
	  - Reseta a ligação da lista de materiais na BEAS_STL (aplanpos_id = null)
	*/

	-- 1. Tabela temporária para listar os itens candidatos elegíveis
	CREATE LOCAL TEMPORARY TABLE #TMP_ITENS_ELEGIVEIS (
		"ItemCode" NVARCHAR(50)
	);

	INSERT INTO #TMP_ITENS_ELEGIVEIS ("ItemCode")
	SELECT DISTINCT A."ItemCode"
	FROM "BEAS_APL" A
	WHERE COALESCE(A."UDF1", '') = '1'
	  AND EXISTS (
		  -- Garante que só pega itens onde a operação MES ainda não é a última
		  SELECT 1 
		  FROM "BEAS_APL" O 
		  WHERE O."ItemCode" = A."ItemCode" 
		    AND O."POS_ID" > A."POS_ID"
	  );

	-- 2. Tabela temporária para calcular a nova ordenação particionada por ItemCode
	CREATE LOCAL TEMPORARY TABLE #TMP_APL_NOVA_ORDEM (
		"ItemCode" NVARCHAR(50),
		"OLD_POS_ID" INT,
		"NEW_POS_ID" INT,
		"NEW_SORT_ID" INT,
		"IS_MASTER" INT
	);

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
	INNER JOIN #TMP_ITENS_ELEGIVEIS I ON T."ItemCode" = I."ItemCode";

	-- 3. Tabela temporária com o POS_ID final da Master de cada item
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

	-- 4. Passo 1 do UPDATE: Mover para faixa temporária (+100000) nos itens elegíveis
	UPDATE "BEAS_APL"
	SET
		"POS_ID" = "POS_ID" + 100000,
		"POS_TEXT" = CAST("POS_ID" + 100000 AS NVARCHAR(50)),
		"MASTER_POS_ID" = NULL
	WHERE "ItemCode" IN (SELECT "ItemCode" FROM #TMP_ITENS_ELEGIVEIS);

	-- 5. Passo 2 do UPDATE: Cursor iterativo para aplicar a reordenação em lote
	BEGIN
		DECLARE CURSOR c_cursor FOR
			SELECT 
				TMP."ItemCode",
				TMP."OLD_POS_ID",
				TMP."NEW_POS_ID",
				TMP."NEW_SORT_ID",
				CASE 
					WHEN TMP."IS_MASTER" = 1 THEN NULL 
					ELSE MF."MASTER_POS_ID_FINAL" 
				END AS "NOVO_MASTER_POS_ID"
			FROM #TMP_APL_NOVA_ORDEM TMP
			LEFT JOIN #TMP_APL_MASTER_FINAL MF ON TMP."ItemCode" = MF."ItemCode";

		FOR cur_row AS c_cursor DO
			UPDATE "BEAS_APL"
			SET
				"POS_ID" = cur_row."NEW_POS_ID",
				"POS_TEXT" = CAST(cur_row."NEW_POS_ID" AS NVARCHAR(50)),
				"SortId" = cur_row."NEW_SORT_ID",
				"MASTER_POS_ID" = cur_row."NOVO_MASTER_POS_ID"
			WHERE "ItemCode" = cur_row."ItemCode"
			  AND "POS_ID" = cur_row."OLD_POS_ID" + 100000;
		END FOR;
	END;

	-- 6. Atualização da estrutura de materiais (BEAS_STL) para os itens alterados
	UPDATE "BEAS_STL"
	SET "APLANPOS_ID" = NULL
	WHERE "ItemCode" IN (SELECT "ItemCode" FROM #TMP_ITENS_ELEGIVEIS);

	-- 7. Limpeza das tabelas temporárias
	DROP TABLE #TMP_ITENS_ELEGIVEIS;
	DROP TABLE #TMP_APL_NOVA_ORDEM;
	DROP TABLE #TMP_APL_MASTER_FINAL;

	-- 8. Conferência dos registros processados
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
	WHERE COALESCE(T."UDF1", '') = '1' OR T."MASTER_POS_ID" IS NOT NULL
	ORDER BY T."ItemCode", T."POS_ID";

END;
